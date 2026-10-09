// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// ROM-resident UART loader for VCU118 (highmem memory map). Runs from ROM
// (0x10000000) with autoboot and lets the host write programs and data into
// ITCM, DTCM, SRAM and DDR over UART1, check them with a CRC, and start the
// program. The host side is fpga/uart_loader.py, which documents the protocol.
//
// - The LSU faults on stores to ITCM, so ITCM writes go through the DMA engine
//   (DTCM receive buffer -> coralnpu_device -> ITCM), like rom_boot/main.c.
// - The loader's own RAM is the top 64 KB of DTCM (rom_loader_highmem.ld).
//   Writes there are refused.
// - DDR commands are refused until DDR calibration is done (gpio_i[0]):
//   touching 0x80000000 before that hangs the crossbar.
// - After a BAUD command the loader falls back to 115200 if no valid frame
//   arrives for BAUD_FALLBACK_SECONDS, so a host that dies mid-session does not
//   leave it at an unknown rate.
//
// Must never return: rom_boot/crt0.S tail-calls main with no exit handler.

#include <stdint.h>

#include "fpga/sw/clk.h"
#include "fpga/sw/dma.h"
#include "fpga/sw/gpio.h"
#include "fpga/sw/uart.h"

#define LOADER_VERSION 0x00010000u

// UART1 registers (OpenTitan uart, see uart_reg_pkg.sv).
#define UART_INTR_STATE (UART1_BASE + 0x00)
#define UART_CTRL (UART1_BASE + 0x10)
#define UART_STATUS (UART1_BASE + 0x14)
#define UART_RDATA (UART1_BASE + 0x18)
#define UART_FIFO_CTRL (UART1_BASE + 0x20)
#define UART_STATUS_TXIDLE (1u << 3)
#define UART_STATUS_RXEMPTY (1u << 5)
// rx_overflow, rx_frame_err, rx_break_err, rx_parity_err.
#define UART_INTR_RX_ERRORS ((1u << 3) | (1u << 4) | (1u << 5) | (1u << 7))
#define UART_FIFO_CTRL_RXRST (1u << 0)

#define DEFAULT_BAUD 115200u
#define BAUD_FALLBACK_SECONDS 3u

// Memory map (CrossbarConfig.scala, highmem layout).
#define ITCM_BASE 0x00000000u
#define ITCM_END 0x00100000u
#define DTCM_BASE 0x00100000u
#define LOADER_RAM_BASE 0x001F0000u  // rom_loader_highmem.ld
#define SRAM_BASE 0x20000000u
#define SRAM_END 0x20400000u
#define DDR_BASE 0x80000000u
#define DDR_END 0x100000000ull
#define DDR_CAL_DONE_GPIO_MASK 0x1u

// Protocol constants, mirrored in fpga/uart_loader.py.
#define REQ_SYNC 0xA5u
#define RSP_SYNC 0x5Au
#define REQ_HEADER_BYTES 20u  // sync, cmd, 2 pad, arg0, arg1, arg2, crc32
#define MAX_WRITE_BYTES 4096u

#define CMD_PING 'P'
#define CMD_BAUD 'B'
#define CMD_WRITE 'W'
#define CMD_CRC 'C'
#define CMD_GO 'G'

#define ST_OK 0u
#define ST_BAD_HEADER_CRC 1u
#define ST_BAD_CMD 2u
#define ST_BAD_RANGE 3u
#define ST_BAD_DATA_CRC 4u
#define ST_TIMEOUT 5u
#define ST_RX_ERROR 6u
#define ST_DDR_NOT_READY 7u
#define ST_DMA_ERROR 8u
#define ST_BAD_ALIGN 9u
#define ST_BAD_LEN 10u
#define ST_BAD_BAUD 11u

#define REG32(addr) (*(volatile uint32_t*)(uintptr_t)(addr))
#define REG8(addr) (*(volatile uint8_t*)(uintptr_t)(addr))

static uint32_t g_crc_table[256];
static uint32_t g_buf[MAX_WRITE_BYTES / 4];
static struct dma_descriptor g_desc;
static uint32_t g_clk_hz;
static uint32_t g_baud;

static uint32_t read_mcycle(void) {
  uint32_t v;
  asm volatile("csrr %0, mcycle" : "=r"(v));
  return v;
}

static void put_kv(const char* key, uint32_t value) {
  uart_puts(key);
  uart_puts("0x");
  uart_puthex32(value);
  uart_puts("\r\n");
}

__attribute__((aligned(4), noreturn)) static void trap_handler(void) {
  uint32_t mcause, mepc, mtval;
  asm volatile("csrr %0, mcause" : "=r"(mcause));
  asm volatile("csrr %0, mepc" : "=r"(mepc));
  asm volatile("csrr %0, mtval" : "=r"(mtval));
  uart_puts("\r\n*** LOADER TRAP ***\r\n");
  put_kv("  mcause: ", mcause);
  put_kv("  mepc:   ", mepc);
  put_kv("  mtval:  ", mtval);
  uart_puts("press CPU_RESET to restart the loader\r\n");
  while (1) {
  }
}

// --- CRC-32 (IEEE 802.3, same as Python's zlib.crc32) ---

static void crc_init(void) {
  for (uint32_t i = 0; i < 256; i++) {
    uint32_t c = i;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
    }
    g_crc_table[i] = c;
  }
}

// Takes and returns the inverted running value; start with 0xFFFFFFFF and
// invert at the end.
static inline uint32_t crc_byte(uint32_t crc, uint8_t b) {
  return g_crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8);
}

static inline uint32_t crc_word(uint32_t crc, uint32_t w) {
  crc = crc_byte(crc, (uint8_t)w);
  crc = crc_byte(crc, (uint8_t)(w >> 8));
  crc = crc_byte(crc, (uint8_t)(w >> 16));
  return crc_byte(crc, (uint8_t)(w >> 24));
}

static uint32_t crc_buf(const uint8_t* p, uint32_t len) {
  uint32_t crc = 0xFFFFFFFFu;
  for (uint32_t i = 0; i < len; i++) {
    crc = crc_byte(crc, p[i]);
  }
  return ~crc;
}

// --- UART ---

static void uart_wait_tx_idle(void) {
  while (!(REG32(UART_STATUS) & UART_STATUS_TXIDLE)) {
  }
}

static int uart_set_baud(uint32_t baud) {
  const uint64_t nco = ((uint64_t)baud << 20) / g_clk_hz;
  if (nco == 0 || nco > 0xFFFF) {
    return 0;
  }
  uart_wait_tx_idle();
  REG32(UART_CTRL) = (uint32_t)((nco << 16) | 3);
  REG32(UART_FIFO_CTRL) = UART_FIFO_CTRL_RXRST;
  REG32(UART_INTR_STATE) = UART_INTR_RX_ERRORS;
  g_baud = baud;
  return 1;
}

static int uart_rx_ready(void) {
  return !(REG32(UART_STATUS) & UART_STATUS_RXEMPTY);
}

// Returns the byte, or -1 if nothing arrives within timeout_cycles.
static int uart_getc_timeout(uint32_t timeout_cycles) {
  const uint32_t start = read_mcycle();
  while (!uart_rx_ready()) {
    if ((uint32_t)(read_mcycle() - start) > timeout_cycles) {
      return -1;
    }
  }
  return (int)(REG32(UART_RDATA) & 0xFF);
}

// Throws away input until the line has been quiet for quiet_cycles, so the
// host can resynchronise after an error.
static void uart_drain(uint32_t quiet_cycles) {
  while (uart_getc_timeout(quiet_cycles) >= 0) {
  }
}

static void send_response(uint32_t status, uint32_t value) {
  uart_putc((char)RSP_SYNC);
  uart_putc((char)status);
  uart_putc(0);
  uart_putc(0);
  for (int i = 0; i < 4; i++) {
    uart_putc((char)(value >> (8 * i)));
  }
}

// --- Address checks ---

static int ddr_ready(void) { return gpio_read() & DDR_CAL_DONE_GPIO_MASK; }

static int in_range(uint32_t addr, uint32_t len, uint64_t base, uint64_t end) {
  return addr >= base && (uint64_t)addr + len <= end;
}

static int is_itcm(uint32_t addr, uint32_t len) {
  return in_range(addr, len, ITCM_BASE, ITCM_END);
}

// Returns ST_OK if [addr, addr + len) lies inside one writable region.
static uint32_t check_range(uint32_t addr, uint32_t len) {
  if (is_itcm(addr, len) || in_range(addr, len, DTCM_BASE, LOADER_RAM_BASE) ||
      in_range(addr, len, SRAM_BASE, SRAM_END)) {
    return ST_OK;
  }
  if (in_range(addr, len, DDR_BASE, DDR_END)) {
    return ddr_ready() ? ST_OK : ST_DDR_NOT_READY;
  }
  return ST_BAD_RANGE;
}

// --- Commands ---

// Receives the payload of a WRITE into g_buf and copies it to its destination.
static uint32_t do_write(uint32_t addr, uint32_t len, uint32_t expected_crc,
                         uint32_t byte_timeout) {
  if (len == 0 || len > MAX_WRITE_BYTES) {
    return ST_BAD_LEN;
  }
  uint8_t* buf = (uint8_t*)g_buf;
  uint32_t crc = 0xFFFFFFFFu;
  for (uint32_t i = 0; i < len; i++) {
    int c = uart_getc_timeout(byte_timeout);
    if (c < 0) {
      return ST_TIMEOUT;
    }
    buf[i] = (uint8_t)c;
    crc = crc_byte(crc, (uint8_t)c);
  }
  if (REG32(UART_INTR_STATE) & UART_INTR_RX_ERRORS) {
    return ST_RX_ERROR;
  }
  if (~crc != expected_crc) {
    return ST_BAD_DATA_CRC;
  }
  uint32_t st = check_range(addr, len);
  if (st != ST_OK) {
    return st;
  }

  if (is_itcm(addr, len)) {
    // The DMA moves whole words; the host pads ITCM data to 4 bytes.
    if ((addr | len) & 3) {
      return ST_BAD_ALIGN;
    }
    g_desc.src_addr = (uint32_t)(uintptr_t)g_buf;
    g_desc.dst_addr = addr;
    g_desc.len_flags = dma_make_len_flags(len, 2, 0, 0, 0);
    g_desc.next_desc = 0;
    g_desc.poll_addr = 0;
    g_desc.poll_mask = 0;
    g_desc.poll_value = 0;
    g_desc.reserved = 0;
    // The DMA reads the descriptor and g_buf from DTCM over the bus.
    asm volatile("fence" ::: "memory");
    dma_start((uint32_t)(uintptr_t)&g_desc);
    return dma_wait_done() == 0 ? ST_OK : ST_DMA_ERROR;
  }

  if (((addr | len) & 3) == 0) {
    volatile uint32_t* dst = (volatile uint32_t*)(uintptr_t)addr;
    for (uint32_t i = 0; i < len / 4; i++) {
      dst[i] = g_buf[i];
    }
  } else {
    volatile uint8_t* dst = (volatile uint8_t*)(uintptr_t)addr;
    for (uint32_t i = 0; i < len; i++) {
      dst[i] = buf[i];
    }
  }
  return ST_OK;
}

// CRC of memory as the core reads it back, so the host can check what really
// landed in ITCM/DTCM/SRAM/DDR.
static uint32_t crc_memory(uint32_t addr, uint32_t len) {
  uint32_t crc = 0xFFFFFFFFu;
  uint32_t i = 0;
  if ((addr & 3) == 0) {
    for (; i + 4 <= len; i += 4) {
      crc = crc_word(crc, REG32(addr + i));
    }
  }
  for (; i < len; i++) {
    crc = crc_byte(crc, REG8(addr + i));
  }
  return ~crc;
}

__attribute__((noreturn)) static void do_go(uint32_t entry) {
  // Programs print with uart_init() at 115200; switch back before jumping so
  // the host can follow along even if the program never touches the UART.
  uart_wait_tx_idle();
  uart_set_baud(DEFAULT_BAUD);
  // ITCM was written behind the fetch unit's back.
  asm volatile("fence.i" ::: "memory");
  void (*fn)(void) = (void (*)(void))(uintptr_t)entry;
  fn();
  // A program that returns lands here: report it instead of running off.
  uart_puts("\r\nprogram returned to loader; press CPU_RESET\r\n");
  while (1) {
  }
}

static uint32_t le32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

int main(void) {
  asm volatile("csrw mtvec, %0" ::"r"(&trap_handler));

  uart_init();
  g_clk_hz = clk_get_main_freq_mhz() * 1000000u;
  g_baud = DEFAULT_BAUD;
  crc_init();

  // Keep 'Z' (RSP_SYNC) out of all text: the host scans for it.
  uart_puts("\r\nCoralNPU ROM UART loader\r\n");
  put_kv("version: ", LOADER_VERSION);
  put_kv("main clk MHz: ", clk_get_main_freq_mhz());
  uart_puts("waiting for host (fpga/uart_loader.py)\r\n");

  const uint32_t byte_timeout = g_clk_hz / 5;  // 200 ms
  const uint32_t quiet_time = g_clk_hz / 10;   // 100 ms
  uint32_t last_frame = read_mcycle();
  uint8_t hdr[REQ_HEADER_BYTES];

  while (1) {
    // Wait for a sync byte; fall back to the default rate if the host went
    // away after changing it.
    if (!uart_rx_ready()) {
      if (g_baud != DEFAULT_BAUD &&
          (uint32_t)(read_mcycle() - last_frame) >
              BAUD_FALLBACK_SECONDS * g_clk_hz) {
        uart_set_baud(DEFAULT_BAUD);
      }
      continue;
    }
    if ((REG32(UART_RDATA) & 0xFF) != REQ_SYNC) {
      continue;
    }
    REG32(UART_INTR_STATE) = UART_INTR_RX_ERRORS;

    hdr[0] = REQ_SYNC;
    uint32_t st = ST_OK;
    for (uint32_t i = 1; i < REQ_HEADER_BYTES; i++) {
      int c = uart_getc_timeout(byte_timeout);
      if (c < 0) {
        st = ST_TIMEOUT;
        break;
      }
      hdr[i] = (uint8_t)c;
    }
    if (st == ST_OK && crc_buf(hdr, 16) != le32(hdr + 16)) {
      st = ST_BAD_HEADER_CRC;
    }
    if (st != ST_OK) {
      uart_drain(quiet_time);
      send_response(st, 0);
      continue;
    }

    last_frame = read_mcycle();
    const uint8_t cmd = hdr[1];
    const uint32_t arg0 = le32(hdr + 4);
    const uint32_t arg1 = le32(hdr + 8);
    const uint32_t arg2 = le32(hdr + 12);
    uint32_t value = 0;

    switch (cmd) {
      case CMD_PING:
        value = LOADER_VERSION | (ddr_ready() ? 0x80000000u : 0);
        break;
      case CMD_BAUD: {
        const uint64_t nco = ((uint64_t)arg0 << 20) / g_clk_hz;
        if (nco == 0 || nco > 0xFFFF) {
          st = ST_BAD_BAUD;
          break;
        }
        // Answer at the old rate, then switch.
        send_response(ST_OK, arg0);
        uart_set_baud(arg0);
        last_frame = read_mcycle();
        continue;
      }
      case CMD_WRITE:
        st = do_write(arg0, arg1, arg2, byte_timeout);
        value = arg2;
        break;
      case CMD_CRC:
        st = check_range(arg0, arg1);
        if (st == ST_OK) {
          value = crc_memory(arg0, arg1);
        }
        break;
      case CMD_GO:
        if (arg0 >= ITCM_END || (arg0 & 1)) {
          st = ST_BAD_RANGE;
          break;
        }
        send_response(ST_OK, arg0);
        do_go(arg0);
      default:
        st = ST_BAD_CMD;
        break;
    }
    if (st != ST_OK) {
      uart_drain(quiet_time);
    }
    send_response(st, value);
    last_frame = read_mcycle();
  }
  return 0;
}
