# 📡PET IEEE Loader

A lightweight utility that turns your Commodore PET into an IEEE-488 device, allowing remote loading and execution of programs from an external controller.

## 📝Contents

- [✨Features](#features)
- [🔧Installation](#installation)
- [🚀Usage](#usage)
- [🔌Controllers](#controllers)
- [💻PET Compatibility](#️pet-compatibility)
- [🧠Technical Summary](#technical-summary)
- [🔍Technical Details](#technical-details)
- [📜License](#license)
- [🤝Contributing](#contributing)

## ✨Features

- Transform your PET from controller to device on the IEEE-488 bus
- Receive programs remotely from another controller
- Execute code with a simple command
- Quick loading for development/testing workflows
- Uses both cassette buffers on the PET
- Easy to use with simple SYS commands

## 🔧Installation

1. Compile the program using the provided Makefile:
   ```bash
   sudo apt-get -y install cc65 make
   make
   ```

2. Transfer the resulting binary (`build/pet-ieee-loader.bin`) to your PET using:
   - A physical disk/tape
   - Another IEEE-488 device
   - An emulator that supports file loading
   - Typing the program in using a machine language monitor

3. On the PET, you can load the program from disk:
    ```basic
    LOAD "PET-IEEE-LOADER",8,1
    ```

## 🚀Usage

1. After loading the program, activate the IEEE listener with:
   ```
   SYS 649
   ```

2. Your PET is now ready to receive data and commands from an IEEE-488 controller.

3. When finished, you can restore the original interrupt handler with:
   ```
   SYS 634
   ```

## 🔌Controllers

The PET IEEE Loader works with any of these controllers:
- Another Commodore PET
- Commodore 64 with IEEE-488 interface cartridge
- PC with IEEE-488 interface (xum1541/ZoomFloppy)

## 💻PET Compatibility

This program uses both cassette buffers as a convenient storage location, common to many PET models.  However, the second cassette buffer was not available on the earliest PET models, so this program is best suited for later PET models, or the early models with updated ROMs.

## 🧠Technical Summary

- Load address: $27A (634 decimal)
- Activation command: `SYS 649`
- Deactivation command: `SYS 634`
- Uses both cassette buffers:
  - Cassette buffer 1: $27A-$339 (192 bytes)
  - Overruns into cassette buffer 2: $33A-$3F9 (192 bytes)
- Command protocol:
  - Bit 7 set: Execute command (followed by 16-bit address)
  - Bit 6 set: Load command (followed by 16-bit address, 16-bit count, then count * data bytes)
- All addresses are in little-endian format (low byte first).

## 🔍Technical Details

The loader operates by:

1. Installing a custom interrupt handler for the IEEE-488 ATN line
2. Listening for commands from the bus controller
3. Supporting two main commands:
   - Load data to a specified memory address
   - Execute code at a specified address

Data is transmitted by the controller using the standard (DAV, NRFD, NDAC) handshake protocol, with data being made available on the 8-bit DIO lines.  No use is made of the EOI lines, in either direction as
- the first byte transmitted encodes the command (load or execute)
- the execute command is followed by 2 bytes encoding the address to execute in little-endian (low byte first) format
- the load command is followed by 2 bytes encoding (low endian) the address to load into, 2 bytes encoding (low endian) the number of bytes to load, and then the data bytes themselves.

The program loads at $27A (634 decimal) and extends into the second cassette buffer since it's larger than 192 bytes.

## 📜License

Licensed under the MIT License. See LICENSE file for details.

## 🤝Contributing

Contributions are welcome.  Please feel free to submit a Pull Request.
