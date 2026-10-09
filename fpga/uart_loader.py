#!/usr/bin/env python3
# Copyright 2026 Google LLC
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Host side of the VCU118 ROM UART loader (fpga/sw/rom_uart_loader.c).

Writes an ELF's loadable segments and/or raw data files into ITCM, DTCM, SRAM
or DDR over the board's USB-UART, checks every region with a CRC computed by
the core, starts the program and prints its console output.

Only needs the Python 3.6 standard library, so it runs with the host's
/usr/bin/python3.

Examples:
  # Load and run a program, then show its output for 10 s:
  ./fpga/uart_loader.py --elf bazel-bin/fpga/uart_loader_hello.elf
  # Load an image into DDR without starting anything:
  ./fpga/uart_loader.py --data image.bin@0x80100000
  # Verilator sim: use the pty the uartdpi prints:
  ./fpga/uart_loader.py --port /dev/pts/7 --time-scale 1000 \
      --elf ... --expect PASS

Protocol (all integers little-endian):
  request:  0xA5, cmd, 0, 0, arg0:u32, arg1:u32, arg2:u32, crc32(first 16 bytes)
            [payload]
  response: 0x5A, status, 0, 0, value:u32
  'P' PING                     -> value = version | 0x80000000 if DDR calibrated
  'B' BAUD  arg0=rate          -> answered at the old rate, then switched. The
                                  loader falls back to 115200 after 3 s without
                                  a valid request.
  'W' WRITE arg0=addr arg1=len arg2=crc32(payload), payload of len <= 4096
                                  bytes. ITCM writes must be word aligned.
  'C' CRC   arg0=addr arg1=len -> value = crc32 of memory as the core reads it
  'G' GO    arg0=entry         -> answered, then the loader switches back to
                                  115200 and jumps (entry must be in ITCM).
"""

import argparse
import os
import select
import struct
import sys
import termios
import time
import zlib

REQ_SYNC = 0xA5
RSP_SYNC = 0x5A
DEFAULT_BAUD = 115200
MAX_WRITE_BYTES = 4096
BAUD_FALLBACK_SECONDS = 3.0
RETRIES = 3

ITCM = (0x00000000, 0x00100000)
DTCM = (0x00100000, 0x001F0000)  # The top 64 KB belongs to the loader.
LOADER_RAM = (0x001F0000, 0x00200000)
SRAM = (0x20000000, 0x20400000)
DDR = (0x80000000, 0x100000000)
REGIONS = [("ITCM", ITCM), ("DTCM", DTCM), ("SRAM", SRAM), ("DDR", DDR)]

STATUS_NAMES = {
    0: "OK",
    1: "BAD_HEADER_CRC",
    2: "BAD_CMD",
    3: "BAD_RANGE",
    4: "BAD_DATA_CRC",
    5: "TIMEOUT",
    6: "RX_ERROR",
    7: "DDR_NOT_READY",
    8: "DMA_ERROR",
    9: "BAD_ALIGN",
    10: "BAD_LEN",
    11: "BAD_BAUD",
}

# Errors that a retry can fix (line noise); the rest are caller mistakes.
RETRYABLE = {1, 4, 5, 6}


class LoaderError(Exception):
  pass


class Port:
  """Raw serial port on top of termios (no pyserial on the host)."""

  def __init__(self, path, baud):
    self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
    self.set_baud(baud)

  def set_baud(self, baud):
    speed = getattr(termios, "B%d" % baud, None)
    if speed is None:
      raise LoaderError("baud rate %d not supported by termios" % baud)
    attrs = termios.tcgetattr(self.fd)
    attrs[0] = 0  # iflag: no input processing
    attrs[1] = 0  # oflag: no output processing
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL  # 8N1
    attrs[3] = 0  # lflag: raw, no echo
    attrs[4] = speed
    attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
    self.baud = baud

  def write(self, data):
    view = memoryview(data)
    while view:
      n = os.write(self.fd, view)
      view = view[n:]
    termios.tcdrain(self.fd)

  def read(self, n, timeout):
    """Reads up to n bytes; returns fewer if timeout (s) runs out."""
    out = bytearray()
    deadline = time.monotonic() + timeout
    while len(out) < n:
      left = deadline - time.monotonic()
      if left <= 0:
        break
      ready, _, _ = select.select([self.fd], [], [], left)
      if ready:
        chunk = os.read(self.fd, n - len(out))
        if not chunk:
          break
        out += chunk
    return bytes(out)

  def flush_input(self):
    termios.tcflush(self.fd, termios.TCIFLUSH)

  def close(self):
    os.close(self.fd)


class Loader:

  def __init__(self, port, verbose, time_scale):
    self.port = port
    self.verbose = verbose
    # Simulation runs far slower than real time; stretch every timeout.
    self.time_scale = time_scale

  def _wire_seconds(self, nbytes):
    return nbytes * 10.0 / self.port.baud

  def _request(self, cmd, arg0=0, arg1=0, arg2=0, payload=b"", timeout=1.0):
    """Sends one request and returns (status, value), or None on timeout."""
    head = struct.pack("<BBHIII", REQ_SYNC, ord(cmd), 0, arg0, arg1, arg2)
    frame = head + struct.pack("<I", zlib.crc32(head)) + payload
    self.port.write(frame)
    deadline = time.monotonic() + self.time_scale * (
        timeout + self._wire_seconds(len(frame)))
    # Skip anything before the response sync byte (e.g. the banner).
    while True:
      left = deadline - time.monotonic()
      b = self.port.read(1, max(left, 0))
      if not b:
        return None
      if b[0] == RSP_SYNC:
        break
    rest = self.port.read(7, max(deadline - time.monotonic(),
                                 0.2 * self.time_scale))
    if len(rest) != 7:
      return None
    status, _, value = struct.unpack("<BHI", rest)
    return status, value

  def command(self, cmd, arg0=0, arg1=0, arg2=0, payload=b"", timeout=1.0):
    """Like _request, but retries line errors and raises on failure."""
    for attempt in range(RETRIES):
      rsp = self._request(cmd, arg0, arg1, arg2, payload, timeout)
      if rsp is not None and rsp[0] == 0:
        return rsp[1]
      if rsp is not None and rsp[0] not in RETRYABLE:
        raise LoaderError("%s 0x%08x: %s" %
                          (cmd, arg0, STATUS_NAMES.get(rsp[0], rsp[0])))
      what = "no response" if rsp is None else STATUS_NAMES.get(rsp[0])
      if self.verbose or attempt == RETRIES - 1:
        print("  %s 0x%08x: %s (attempt %d)" % (cmd, arg0, what, attempt + 1))
      # The loader drains until the line is quiet for 100 ms before replying.
      time.sleep(0.3 * self.time_scale)
      self.port.flush_input()
    raise LoaderError("%s 0x%08x failed after %d attempts" %
                      (cmd, arg0, RETRIES))

  def ping(self):
    rsp = self._request("P", timeout=0.5)
    if rsp is None or rsp[0] != 0:
      return None
    return rsp[1]

  def connect(self):
    """Finds the loader at 115200; returns the PING value."""
    self.port.flush_input()
    value = self.ping()
    if value is None:
      # It may still be at the rate of an aborted session.
      print("no answer at %d baud, waiting for the loader's fallback" %
            DEFAULT_BAUD)
      time.sleep(BAUD_FALLBACK_SECONDS + 0.5)
      self.port.flush_input()
      value = self.ping()
    if value is None:
      raise LoaderError(
          "no answer from the loader. Is the ROM-loader bitstream on the "
          "board? A loaded program may be running: press CPU_RESET.")
    return value

  def set_baud(self, baud):
    if baud == self.port.baud:
      return
    self.command("B", baud)
    self.port.set_baud(baud)
    time.sleep(0.05)
    self.port.flush_input()
    if self.ping() is None:
      print("no answer at %d baud, falling back to %d" % (baud, DEFAULT_BAUD))
      time.sleep(BAUD_FALLBACK_SECONDS + 0.5)
      self.port.set_baud(DEFAULT_BAUD)
      self.port.flush_input()
      if self.ping() is None:
        raise LoaderError("lost the loader after the baud change")

  def write(self, addr, data):
    """Writes data in chunks, then checks the whole region by CRC."""
    if region_of(addr, len(data)) == "ITCM":
      if addr % 4:
        raise LoaderError("ITCM address 0x%08x is not word aligned" % addr)
      data += b"\0" * (-len(data) % 4)
    start = time.monotonic()
    for off in range(0, len(data), MAX_WRITE_BYTES):
      chunk = data[off:off + MAX_WRITE_BYTES]
      self.command("W", addr + off, len(chunk), zlib.crc32(chunk), chunk,
                   timeout=1.0)
      if not self.verbose:
        print("\r  0x%08x: %d / %d bytes" % (addr, off + len(chunk),
                                             len(data)),
              end="")
        sys.stdout.flush()
    elapsed = time.monotonic() - start
    print("\r  0x%08x: %d bytes in %.1f s (%.1f KB/s)" %
          (addr, len(data), elapsed, len(data) / 1024.0 / max(elapsed, 1e-6)))
    # Read-back check. Generous timeout: DDR reads are slow from the core.
    crc = self.command("C", addr, len(data), timeout=2.0 + len(data) / 50e3)
    if crc != zlib.crc32(data):
      raise LoaderError("read-back CRC mismatch at 0x%08x: core 0x%08x, "
                        "host 0x%08x" % (addr, crc, zlib.crc32(data)))
    print("  0x%08x: read-back CRC ok (0x%08x)" % (addr, crc))

  def go(self, entry):
    self.command("G", entry)
    self.port.set_baud(DEFAULT_BAUD)


def region_of(addr, length):
  for name, (lo, hi) in REGIONS:
    if lo <= addr and addr + length <= hi:
      return name
  if addr < LOADER_RAM[1] and addr + length > LOADER_RAM[0]:
    raise LoaderError(
        "0x%08x+0x%x overlaps the loader's RAM (top 64 KB of DTCM)" %
        (addr, length))
  raise LoaderError("0x%08x+0x%x is not inside one of %s" %
                    (addr, length, ", ".join(n for n, _ in REGIONS)))


def elf_segments(path):
  """Returns (entry, [(paddr, bytes)]) for the PT_LOAD segments of an ELF32."""
  with open(path, "rb") as f:
    elf = f.read()
  if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
    raise LoaderError("%s is not a little-endian ELF32 file" % path)
  (entry, phoff, phentsize, phnum) = struct.unpack_from("<24xII10xHH", elf)
  segments = []
  for i in range(phnum):
    (p_type, p_offset, _, p_paddr, p_filesz,
     _) = struct.unpack_from("<IIIIII", elf, phoff + i * phentsize)
    if p_type == 1 and p_filesz > 0:  # PT_LOAD
      segments.append((p_paddr, elf[p_offset:p_offset + p_filesz]))
  return entry, segments


def parse_data_arg(arg):
  path, sep, addr = arg.rpartition("@")
  if not sep:
    raise argparse.ArgumentTypeError("expected FILE@ADDR, got %r" % arg)
  with open(path, "rb") as f:
    return int(addr, 0), f.read()


def monitor(port, seconds, expect):
  """Prints console output; returns False if `expect` was given but not seen."""
  print("--- console (%s) ---" %
        ("until '%s'" % expect if expect else "%.0f s" % seconds))
  seen = b""
  deadline = time.monotonic() + seconds
  while time.monotonic() < deadline:
    data = port.read(256, 0.1)
    if not data:
      continue
    sys.stdout.write(data.decode("ascii", "replace"))
    sys.stdout.flush()
    seen = (seen + data)[-4096:]
    if expect and expect.encode() in seen:
      print("\n--- found '%s' ---" % expect)
      return True
  print("\n--- end of console ---")
  return not expect


def main():
  parser = argparse.ArgumentParser(
      description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
  parser.add_argument("--port", default="/dev/ttyUSB4")
  parser.add_argument(
      "--baud",
      type=int,
      default=DEFAULT_BAUD,
      help="rate for the transfer (default 115200, which needs no switch; "
      "higher rates are untested on the board)")
  parser.add_argument("--elf", help="program to load (PT_LOAD segments)")
  parser.add_argument("--data",
                      type=parse_data_arg,
                      action="append",
                      default=[],
                      metavar="FILE@ADDR",
                      help="raw file to load at ADDR (repeatable)")
  parser.add_argument("--entry",
                      type=lambda x: int(x, 0),
                      help="entry point (default: the ELF's)")
  parser.add_argument("--no-go",
                      action="store_true",
                      help="load only, don't start the program")
  parser.add_argument("--monitor",
                      type=float,
                      default=10.0,
                      metavar="SECONDS",
                      help="how long to show console output after GO "
                      "(default 10; 0 = don't)")
  parser.add_argument("--expect",
                      help="stop monitoring when this text appears; exit 1 "
                      "if it doesn't within --monitor seconds")
  parser.add_argument("--time-scale",
                      type=float,
                      default=1.0,
                      help="multiply all protocol timeouts (e.g. 1000 for "
                      "the Verilator sim)")
  parser.add_argument("-v", "--verbose", action="store_true")
  args = parser.parse_args()

  loads = list(args.data)
  entry = args.entry
  if args.elf:
    elf_entry, segments = elf_segments(args.elf)
    loads = segments + loads
    if entry is None:
      entry = elf_entry
  try:
    for addr, data in loads:
      region_of(addr, len(data))  # Fail before touching the board.
  except LoaderError as e:
    print("error: %s" % e, file=sys.stderr)
    return 1

  port = Port(args.port, DEFAULT_BAUD)
  try:
    loader = Loader(port, args.verbose, args.time_scale)
    value = loader.connect()
    print("loader version 0x%05x, DDR %s" %
          (value & 0x7FFFFFFF, "calibrated" if value >> 31 else
           "NOT calibrated"))
    if loads:
      loader.set_baud(args.baud)
      print("transfer rate: %d baud" % port.baud)
    for addr, data in loads:
      print("%s 0x%08x, %d bytes" % (region_of(addr, len(data)), addr,
                                      len(data)))
      loader.write(addr, data)
    if args.no_go or entry is None:
      if not args.no_go:
        print("nothing to start (no --elf or --entry)")
      return 0
    print("starting at 0x%08x" % entry)
    loader.go(entry)
    if args.monitor > 0 or args.expect:
      ok = monitor(port, args.monitor if args.monitor > 0 else 60.0,
                   args.expect)
      return 0 if ok else 1
    return 0
  except LoaderError as e:
    print("\nerror: %s" % e, file=sys.stderr)
    return 1
  finally:
    port.close()


if __name__ == "__main__":
  sys.exit(main())
