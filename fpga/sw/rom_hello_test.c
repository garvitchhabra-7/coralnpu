// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Standalone ROM-resident test: runs directly from ROM (0x10000000) with
// autoboot, no program loading required. Prints a banner and then a heartbeat
// once per second forever, so output is visible whenever a UART is attached.
// Must never return: rom_boot/crt0.S tail-calls main with no exit handler.

#include <stdint.h>

#include "fpga/sw/clk.h"
#include "fpga/sw/uart.h"

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

int main(void) {
  uart_init();
  uart_puts("\r\nCoralNPU ROM boot OK\r\n");
  uart_puts("main clk MHz: 0x");
  uart_puthex32(clk_get_main_freq_mhz());
  uart_puts("\r\n");

  const uint32_t one_second = clk_get_main_freq_mhz() * 1000000u;
  uint32_t count = 0;
  while (1) {
    uart_puts("alive 0x");
    uart_puthex32(count++);
    uart_puts("\r\n");
    delay_cycles(one_second);
  }
  return 0;
}
