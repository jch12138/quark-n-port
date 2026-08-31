#!/usr/bin/env python3
"""Generate panel-mipi-dbi firmware for Atom-N's 240x135 ST7789VW."""

from pathlib import Path
import sys


COMMANDS = (
    # The generic driver has just issued HW reset + SWRESET.  Its SWRESET
    # delay is only 5-20 ms when reset-gpios is present, so wait the full
    # controller-safe interval before programming the panel.
    (0x00, (120,)),  # Delay 120 ms
    # Exact register values from the factory fb_st7789vw driver.
    (0x36, (0x70,)),  # MADCTL: factory 90-degree landscape orientation
    (0x3A, (0x05,)),  # RGB565
    (0xB2, (0x0C, 0x0C, 0x00, 0x33, 0x33)),
    (0xB7, (0x35,)),
    (0xBB, (0x19,)),
    (0xC0, (0x2C,)),
    (0xC2, (0x01,)),
    (0xC3, (0x12,)),
    (0xC4, (0x20,)),
    (0xC6, (0x0F,)),
    (0xD0, (0xA4, 0xA1)),
    (0xE0, (0xD0, 0x04, 0x0D, 0x11, 0x13, 0x2B, 0x3F,
            0x54, 0x4C, 0x18, 0x0D, 0x0B, 0x1F, 0x23)),
    (0xE1, (0xD0, 0x04, 0x0C, 0x11, 0x13, 0x2C, 0x3F,
            0x44, 0x51, 0x2F, 0x1F, 0x1F, 0x20, 0x23)),
    (0x21, ()),  # Inversion on for the IPS panel
    (0x11, ()),  # Exit sleep mode
    (0x00, (120,)),  # Required sleep-out settling time
    (0x29, ()),  # Display on
    (0x00, (200,)),  # Match the factory driver's final settle delay
)


def build() -> bytes:
    payload = bytearray(b"MIPI DBI" + b"\0" * 7 + b"\1")
    for command, parameters in COMMANDS:
        if len(parameters) > 255:
            raise ValueError(f"too many parameters for command 0x{command:02x}")
        payload.extend((command, len(parameters)))
        payload.extend(parameters)
    return bytes(payload)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build())
    print(f"wrote {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
