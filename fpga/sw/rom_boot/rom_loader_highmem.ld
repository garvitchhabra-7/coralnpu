/* Copyright 2026 Google LLC. */
/* Licensed under the Apache License, Version 2.0, see LICENSE for details. */
/* SPDX-License-Identifier: Apache-2.0 */

/* ROM UART loader (rom_uart_loader.c). Same as rom_highmem.ld, except that the
 * loader's RAM (data, bss, stack, receive buffer) sits in the top 64 KB of
 * DTCM. The loader refuses writes there, and programs linked with the default
 * TCM linker script only put loadable data at the bottom of DTCM. */

MEMORY {
    ROM(rx) : ORIGIN = 0x10000000, LENGTH = 32K
    LOADER_RAM(rw) : ORIGIN = 0x001F0000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS {
    .text : {
        *(._init)
        *(.text)
        *(.text.*)
    } > ROM

    .rodata : ALIGN(4) {
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
    } > ROM

    . = ALIGN(4);
    _data_load = LOADADDR(.data);
    .data : ALIGN(4) {
        _data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > LOADER_RAM AT > ROM

    .bss : ALIGN(4) {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        . = ALIGN(4);
        _bss_end = .;
    } > LOADER_RAM

    .stack : {
        . = ALIGN(16);
        . += 4096;
        _stack_top = .;
    } > LOADER_RAM
}
