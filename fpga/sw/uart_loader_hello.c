// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// First program for the ROM UART loader (rom_uart_loader.c): loaded into
// ITCM/DTCM by fpga/uart_loader.py. Checks that initialised data arrived in
// both TCMs (.rodata lives in ITCM, .data in DTCM) and prints the result.

#include <stdint.h>

#include "fpga/sw/clk.h"
#include "fpga/sw/uart.h"

// volatile keeps the reads from being folded into constants.
static const volatile uint32_t kRodata[4] = {0x11111111u, 0x22222222u,
                                             0x33333333u, 0x44444444u};
static volatile uint32_t g_data[4] = {0xA0A0A0A0u, 0xB1B1B1B1u, 0xC2C2C2C2u,
                                      0xD3D3D3D3u};

int main(void) {
  uart_init();
  uart_puts("\r\nhello from ITCM (loaded over UART)\r\n");
  uart_puts("main clk MHz: 0x");
  uart_puthex32(clk_get_main_freq_mhz());
  uart_puts("\r\n");

  uint32_t errors = 0;
  for (uint32_t i = 0; i < 4; i++) {
    if (kRodata[i] != 0x11111111u * (i + 1)) errors++;
    if (g_data[i] != 0xA0A0A0A0u + 0x11111111u * i) errors++;
  }
  uart_puts(errors == 0 ? "uart_loader_hello PASS\r\n"
                        : "uart_loader_hello FAIL\r\n");
  return 0;
}
