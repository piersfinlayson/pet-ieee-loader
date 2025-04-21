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
- Easy to set up and use with `SYS`/`POKE` commands
- Data received using standard IEEE-488 LISTEN command
- Includes PET program and sender program for x86_64 using xum1541/pico1541

## 🔧Installation

Pre-built Loader and Sender binaries are available on the [github releases](https://github.com/piersfinlayson/pet-ieee-loader/releases) page.  This allows you to skip the build process below.

### 💻PET Loader

1. Compile the loader program using the provided Makefile:
   ```bash
   sudo apt-get -y install cc65 make vice
   make loader
   ```

   This creates:
    ```bash
    loader/build/pet-ieee-loader.prg  # The PET program in PRG format
    loader/build/pet-ieee-loader.d64  # A D64 disk image containing the program 
    ```

2. Transfer the resulting binary (`loader/build/pet-ieee-loader.bin`) to your PET using:
   - A physical disk/tape
   - Another IEEE-488 device
   - An emulator that supports file loading
   - Typing the program in using a machine language monitor

3. On the PET, you can load the program from disk using the created D64 image:
    ```basic
    LOAD"IEEE-LOADER",8,1
    ```

### 💻Sender

1. Install Rust
    ```bash
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    ```

2. Build the sender program:
   ```bash
   make sender
   ```

3. Connect your xum1541 (ZoomFloppy) or pico1541 to your PC, and connect the IEEE-488 port to your PET's IEEE-488 port.  Power on the PET.

## 🚀Usage

### 💻PET

1. After loading the program, activate the IEEE loader with:
   ```basic
   SYS 661
   ```

2. By default the PET will identify as device 30.  To change this `POKE` a different value to `660`.  Values 0-30 inclusive are valid:
    ```basic
    POKE 660,8
    ```

3. Your PET is now ready to receive data and commands from an IEEE-488 controller.

4. If finished, you can restore the original interrupt handler with:
   ```basic
   SYS 634
   ```
   The program automatically restores the original interrupt handler when an execute command is received and actioned.

### 💻Sender

1. Run the sender program:
   ```bash
   sender --load --file test.prg --use-file-addr
   sender --execute --addr 0401  # Assumes test.prg is a BASIC program
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
- Activation command: `SYS 661`
- Deactivation command: `SYS 634`
- Preconfigured as device 30, at address `660`
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
2. Listening for LISTEN commands from the bus controller, directed at this device's ID
3. Supporting two commands:
   - Load data to a specified memory address
   - Execute code at a specified address

Data is transmitted by the controller using the standard (DAV, NRFD, NDAC) handshake protocol, with data being made available on the 8-bit DIO lines.  No use is made of the EOI lines, in either direction.

The expected data sequence is:
- Single LISTEN byte identifying the PET's device ID ($20 | device ID from $00-$1E inclusive).
- (Subsequent channel/secondary address byte is not expected or supported) 
- The first byte transmitted encodes the command (load or execute):
    - $80 Execute
    - $40 Load
- The next 2 bytes are the address with low byte first - either the address to execute or to load into.
- The load command address bytes are then followed by 2 bytes encoding (low byte first) the number of bytes to load, and then the data bytes themselves.

The program loads at $27A (634 decimal) and extends into the second cassette buffer since it's larger than 192 bytes.

### Execute Byte Sequence

```
+------------+-------------+------------------+------------------+
| LISTEN     | COMMAND     | ADDRESS (LOW)    | ADDRESS (HIGH)   |
| $20+DEVICE | $80         | Low byte         | High byte        |
+------------+-------------+------------------+------------------+
  Byte 0       Byte 1        Byte 2             Byte 3
```

### Load Byte Sequence

```
+------------+-------------+------------------+------------------+----------------+----------------+----------+
| LISTEN     | COMMAND     | ADDRESS (LOW)    | ADDRESS (HIGH)   | SIZE (LOW)     | SIZE (HIGH)    | DATA...  |
| $20+DEVICE | $40         | Low byte         | High byte        | Low byte       | High byte      | N bytes  |
+------------+-------------+------------------+------------------+----------------+----------------+----------+
  Byte 0       Byte 1        Byte 2             Byte 3             Byte 4           Byte 5          Bytes 6+
```

## 📜License

Licensed under the MIT License. See LICENSE file for details.

## 🤝Contributing

Contributions are welcome.  Please feel free to submit a Pull Request.
