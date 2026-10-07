// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Standalone ROM-resident DDR4 test for VCU118: runs directly from ROM
// (0x10000000) with autoboot, no program loading required.
//
// 1. Prints the same banner as rom_hello_test.c.
// 2. Waits for DDR calibration (gpio_i[0], see chip_vcu118.sv), with a timeout.
//    Touching 0x80000000 before calibration hangs the crossbar.
// 3. Runs a set of write/read-back tests on DDR and prints PASS/FAIL.
// 4. Prints a heartbeat with the result once per second forever, so the result
//    is visible even if the terminal is opened late.
//
// A trap handler prints mcause/mepc/mtval, so a bus error shows up on the
// UART instead of as a silent hang.
// Must never return: rom_boot/crt0.S tail-calls main with no exit handler.

#include <stdint.h>

#include "fpga/sw/clk.h"
#include "fpga/sw/gpio.h"
#include "fpga/sw/uart.h"

#define DDR_BASE 0x80000000u
// The SoC crossbar maps 2 GB of DDR at DDR_BASE (CrossbarConfig.scala).
#define DDR_SIZE 0x80000000u
// The size ddr_system_bd's SmartConnect decodes. If it is smaller than
// DDR_SIZE, accesses above it get a decode error.
#define DDR_BD_SEGMENT_SIZE 0x20000000u
#define DDR_CAL_DONE_GPIO_MASK 0x1u
#define DDR_CAL_TIMEOUT_SECONDS 5u
#define BLOCK_TEST_BYTES (1u << 20)
#define MAX_REPORTED_ERRORS 8u

#define REG32(addr) (*(volatile uint32_t*)(uintptr_t)(addr))
#define REG16(addr) (*(volatile uint16_t*)(uintptr_t)(addr))
#define REG8(addr) (*(volatile uint8_t*)(uintptr_t)(addr))

static uint32_t g_errors;

static uint32_t read_mcycle(void) {
  uint32_t v;
  asm volatile("csrr %0, mcycle" : "=r"(v));
  return v;
}

static void delay_cycles(uint32_t cycles) {
  uint32_t start = read_mcycle();
  while ((uint32_t)(read_mcycle() - start) < cycles) {
  }
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
  uart_puts("\r\n*** TRAP ***\r\n");
  put_kv("  mcause: ", mcause);
  put_kv("  mepc:   ", mepc);
  put_kv("  mtval:  ", mtval);
  uart_puts("DDR test FAIL (trap)\r\n");
  while (1) {
  }
}

static void check(uint32_t addr, uint32_t expected, uint32_t actual) {
  if (expected == actual) {
    return;
  }
  if (g_errors < MAX_REPORTED_ERRORS) {
    uart_puts("    mismatch at 0x");
    uart_puthex32(addr);
    uart_puts(": expected 0x");
    uart_puthex32(expected);
    uart_puts(", read 0x");
    uart_puthex32(actual);
    uart_puts("\r\n");
  }
  g_errors++;
}

static void begin_test(const char* name) {
  uart_puts(name);
  uart_puts(" ... ");
}

static void end_test(uint32_t errors_before) {
  if (g_errors == errors_before) {
    uart_puts("ok\r\n");
  } else {
    uart_puts("FAIL\r\n");
  }
}

static int wait_for_calibration(uint32_t one_second) {
  for (uint32_t s = 0; s < DDR_CAL_TIMEOUT_SECONDS * 10; s++) {
    if (gpio_read() & DDR_CAL_DONE_GPIO_MASK) {
      return 1;
    }
    delay_cycles(one_second / 10);
  }
  return 0;
}

// The test the porting plan asks for: one word at the base address.
static void test_single_word(void) {
  begin_test("[1] single word at 0x80000000");
  uint32_t e = g_errors;
  REG32(DDR_BASE) = 0xC0FFEE01u;
  check(DDR_BASE, 0xC0FFEE01u, REG32(DDR_BASE));
  end_test(e);
}

// Sub-word writes exercise the AXI write strobes.
static void test_byte_strobes(void) {
  begin_test("[2] byte/halfword writes");
  uint32_t e = g_errors;
  const uint32_t a = DDR_BASE + 0x40;
  REG32(a) = 0x11223344u;
  REG8(a + 1) = 0xAAu;
  REG16(a + 2) = 0xBBCCu;
  check(a, 0xBBCCAA44u, REG32(a));
  check(a, 0xAAu, REG8(a + 1));
  check(a, 0xBBCCu, REG16(a + 2));
  end_test(e);
}

// Walking ones and zeros over 8 words (one 256-bit AXI beat), so every data
// bit of the bus is toggled on its own.
static void test_walking_bits(void) {
  begin_test("[3] walking 1s/0s, 32 bytes");
  uint32_t e = g_errors;
  const uint32_t a = DDR_BASE + 0x100;
  for (uint32_t bit = 0; bit < 32; bit++) {
    for (uint32_t w = 0; w < 8; w++) {
      REG32(a + 4 * w) = (w & 1) ? ~(1u << bit) : (1u << bit);
    }
    for (uint32_t w = 0; w < 8; w++) {
      uint32_t expected = (w & 1) ? ~(1u << bit) : (1u << bit);
      check(a + 4 * w, expected, REG32(a + 4 * w));
    }
  }
  end_test(e);
}

// Address-in-address over a block, then the inverse: catches stuck data bits,
// shorted address bits within the block, and lost writes.
static void test_block(void) {
  begin_test("[4] address pattern, 1 MB");
  uint32_t e = g_errors;
  uint32_t start = read_mcycle();
  for (uint32_t pass = 0; pass < 2; pass++) {
    const uint32_t flip = pass ? 0xFFFFFFFFu : 0;
    for (uint32_t a = DDR_BASE; a < DDR_BASE + BLOCK_TEST_BYTES; a += 4) {
      REG32(a) = a ^ flip;
    }
    for (uint32_t a = DDR_BASE; a < DDR_BASE + BLOCK_TEST_BYTES; a += 4) {
      check(a, a ^ flip, REG32(a));
    }
  }
  uint32_t cycles = read_mcycle() - start;
  end_test(e);
  // 4 passes over the block (2 x write + read).
  put_kv("    cycles for 4 MB of word accesses: ", cycles);
}

// One word at each power-of-two offset. A broken or aliased address line
// makes a later write overwrite an earlier one.
static uint32_t line_value(uint32_t bit) { return 0xA5000000u | bit; }

static void write_lines(uint32_t first_bit, uint32_t last_bit) {
  for (uint32_t bit = first_bit; bit <= last_bit; bit++) {
    REG32(DDR_BASE + (1u << bit)) = line_value(bit);
  }
}

static void check_lines(uint32_t first_bit, uint32_t last_bit) {
  for (uint32_t bit = first_bit; bit <= last_bit; bit++) {
    uint32_t a = DDR_BASE + (1u << bit);
    check(a, line_value(bit), REG32(a));
  }
}

static uint32_t log2_u32(uint32_t v) {
  uint32_t r = 0;
  while (v >>= 1) {
    r++;
  }
  return r;
}

static void test_address_lines(void) {
  // Offsets 4 B .. half the block design's segment: always decoded.
  const uint32_t low_last = log2_u32(DDR_BD_SEGMENT_SIZE) - 1;
  // Offsets from the segment size up to half the SoC's 2 GB window.
  const uint32_t high_first = low_last + 1;
  const uint32_t high_last = log2_u32(DDR_SIZE) - 1;
  const uint32_t top = DDR_BASE + DDR_SIZE - 4;

  begin_test("[5] address lines, offsets < 512 MB");
  uint32_t e = g_errors;
  REG32(DDR_BASE) = 0x5A5A5A5Au;
  write_lines(2, low_last);
  check(DDR_BASE, 0x5A5A5A5Au, REG32(DDR_BASE));
  check_lines(2, low_last);
  end_test(e);

  if (high_first > high_last) {
    return;
  }
  uart_puts("[6] address lines, offsets >= 512 MB\r\n");
  uart_puts("    (a trap or hang here means ddr_system_bd still decodes only"
            " 512 MB)\r\n");
  begin_test("    result");
  e = g_errors;
  write_lines(high_first, high_last);
  REG32(top) = 0x7E7E7E7Eu;
  check(top, 0x7E7E7E7Eu, REG32(top));
  check_lines(high_first, high_last);
  // Nothing above may alias onto the low addresses.
  check(DDR_BASE, 0x5A5A5A5Au, REG32(DDR_BASE));
  check_lines(2, low_last);
  end_test(e);
}

int main(void) {
  asm volatile("csrw mtvec, %0" ::"r"(&trap_handler));

  uart_init();
  uart_puts("\r\nCoralNPU ROM boot OK\r\n");
  put_kv("main clk MHz: ", clk_get_main_freq_mhz());

  const uint32_t one_second = clk_get_main_freq_mhz() * 1000000u;
  const char* result;

  uart_puts("waiting for DDR calibration ... ");
  if (!wait_for_calibration(one_second)) {
    uart_puts("TIMEOUT, DDR not touched\r\n");
    result = "DDR CAL TIMEOUT";
  } else {
    uart_puts("done\r\n");
    test_single_word();
    test_byte_strobes();
    test_walking_bits();
    test_block();
    test_address_lines();
    if (g_errors == 0) {
      result = "DDR PASS";
    } else {
      result = "DDR FAIL";
      put_kv("errors: ", g_errors);
    }
  }
  uart_puts(result);
  uart_puts("\r\n");

  uint32_t count = 0;
  while (1) {
    uart_puts("alive 0x");
    uart_puthex32(count++);
    uart_puts(" ");
    uart_puts(result);
    uart_puts("\r\n");
    delay_cycles(one_second);
  }
  return 0;
}
