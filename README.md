# 📡PET IEEE Loader

A lightweight utility that turns your Commodore PET into an IEEE-488 device, allowing remote loading and execution of programs from an external controller.

## 📝Contents

- [✨Features](#features)
- [🔧Installation](#installation)
- [🚀Usage](#usage)
- [🔌Controllers](#controllers)
- [💻PET Compatibility](#️pet-compatibility)
- [🧠Technical Details](#technical-details)
- [📜License](#license)
- [🤝Contributing](#contributing)

## ✨Features

- Transform your PET from controller to device on the IEEE-488 bus
- Receive and execute programs remotely from another controller
- Supports machine language and BASIC programs
- Loads programs 4x faster than using IEEE-488 disk drives
- Suitable for embedding in development/testing workflows with real hardware
- Small - program fits into less than 1K of space
- Can be loaded into RAM, at any address, or into ROM
- Easy to set up and configure with one-line `BASIC` commands
- Data received using standard IEEE-488 protocols
- Includes both loader program for the PET and sender program for linux using xum1541/pico1541 USB-IEEE-488 adapters
- Compatible with OpenCBM - OpenCBM can be used directly to send command if you'd prefer 

## 🔧Installation

Pre-built Loader binaries are available on the [github releases](https://github.com/piersfinlayson/pet-ieee-loader/releases) page.  This allows you to skip the build process below.

To build the sender program you will need Rust installed - full instructions in [💻Sender](#sender).

### 💻PET Loader

See [📚Dependencies](#dependencies) for an explanation of the required dependencies.

1. Compile the loader program using the provided Makefile:
   ```bash
   sudo apt-get -y install cc65 gawk make vice
   make loader
   ```

   This creates:
    ```bash
    loader/build/7c00-loader.prg      # The PET program in PRG format, which will load to $7C00
    loader/build/loader.d64           # A D64 disk image containing the program 
    loader/build/9000-loader-rom.bin  # A 4KB ROM image, with the loader program located at $9000
    ```

2. Transfer the resulting binary (`loader/build/pet-ieee-loader.bin`) to your PET using:
   - A physical disk/tape
   - Another IEEE-488 device
   - An emulator that supports file loading
   - Typing the program in using a machine language monitor

3. On the PET, you can load the program from disk using the created D64 image:
    ```basic
    LOAD"7C00-LOADER",8,1
    ```

Or burn a 4KB 2332 compatible (E)EPROM with `loader/build/9000-loader-rom.bin` to use the loader as a ROM and install in your PET's $9000 ROM slot.

### 💻Sender

1. Install Rust
    ```bash
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    . "$HOME/.cargo/env"
    ```

2. Build the sender program:
   ```bash
   make sender
   ```

3. Connect your xum1541 (ZoomFloppy) or pico1541 to your PC, and connect the IEEE-488 port to your PET's IEEE-488 port.  Power on the PET.

### 📚Build Dependencies

Building the loader program requires the following dependencies:
- [cc65](https://cc65.github.io/cc65/) - 6502 cross compiler
- [gawk](https://www.gnu.org/software/gawk/) - GNU version of AWK, required by build verification script
- [make](https://www.gnu.org/software/make/) - Build tool
- [vice](https://vice-emu.sourceforge.io/) - Commodore emulator, required to create the loader D64 image
- [Rust](https://www.rust-lang.org/) - Required to build the sender program

## 🚀Usage

### 💻PET

1. After loading the program, activate the IEEE loader with:
   ```basic
   SYS 31744
   ```

2. By default the PET will identify as device 30.  To change this `POKE` a different value to `31753`.  Values 0-30 inclusive are valid:
    ```basic
    POKE 31753,8
    ```

3. Your PET is now ready to receive data and commands from an IEEE-488 controller.

4. If finished, you can restore the original interrupt handler with:
   ```basic
   SYS 31747
   ```
   The program automatically restores the original interrupt handler when an execute command is received and actioned.

#### ROM version

To use the $9000 ROM version:
```basic
SYS 36864
```

Change the device ID with:
```basic
POKE 634,8
```

To disable it:
```basic
SYS 36867
```

### 💻Sender

A sample machine language program is included at `loader/build/test.bin`.

1. Run the sender program:
   ```bash
   sender --load --addr 6000 test.bin  # Loads test.bin to $6000
   sender --execute --addr $6000       # Executes the program at $6000
   ```

While the executed routine is running, the loader will be disabled.  Once the routine returns, the loader will be re-enabled.

If you run a BASIC program the loader will be disabled, until you manually re-enable it with the `SYS` command.

## 🔌Controllers

The PET IEEE Loader works with any of these controllers:
- PC with IEEE-488 interface (xum1541/ZoomFloppy)
- Another Commodore PET
- Commodore 64 with IEEE-488 interface cartridge
- Any IEEE-488 controller which can send LISTEN commands and write raw data to the bus

## 💻PET Compatibility

This program is compiled to load to $7C00-$7FFF, which requires a 32KB PET.  To change where it loads to, change all of:
```makefile
RAM_LOAD_ADDR ?= $$7C00
RAM_VAR_ADDR ?= $$7FD0
PRG_PREFIX_ADDR ?= $$7BFE
```
in the Makefile.
- `RAM_VAR_ADDR` must be at least 32 bytes from the end of the program space (defined by `MAX_PRG_SIZE`).
- `PRG_PREFIX_ADDR` must be 2 less than `LOAD_ADDR`.

To change the location of the ROM version, change `ROM_LOAD_ADDR` in the Makefile:
```makefile
ROM_LOAD_ADDR ?= $$9000
```

`$A000` is another reasonable value, if your $A000 ROM slot is empty.  Your `SYS` addresses will move accordingly.

### 🏠Changing RAM version Load Address

For example, to load to $3C00, set:
```makefile
LOAD_ADDR ?= $$3C00
PRG_PREFIX_ADDR ?= $$3BFE
make clean-loader loader
```

This will create:
```bash
loader/build/3c00-loader.prg  # The PET program in PRG format, which will load to $3C00
loader/build/loader.d64       # A D64 disk image containing the program 
```

In this example, to activate the loader, you would use:
```basic
SYS 15360
```

To deactivate the loader, you would use:
```basic
SYS 15363
```

And to change the PET's device ID to 8 you would use:
```basic
POKE 15359,8
```

## 🧠Technical Details

The loader operates by:

1. Installing a custom hardware interrupt handler for the IEEE-488 ATN line, chaining onto the standard hardware interrupt handler when ATN is not asserted
2. Listening for LISTEN commands from the bus controller, directed at this device's configured ID
3. Supporting two commands:
   - Load data to a specified memory address
   - Execute, using JSR, code at a specified address
   - Run a BASIC program

Data is transmitted by the controller using the standard (DAV, NRFD, NDAC) handshake protocol and EOI line, with data being made available on the 8-bit DIO lines.

The expected data sequence is:
- Single LISTEN byte identifying the PET's device ID ($20 | device ID from $00-$1E inclusive).
- Subsequent channel/secondary address byte - this is read but ignored, so you can use any channel value. 
- The next byte transmitted encodes the command (load or execute):
    - $C0 Run (BASIC program)
    - $80 Execute (JSR)
    - $40 Load
- The subsequent 2 bytes are expected for Execute and Load, and contain the appropriate address with low byte first - either the address to execute or to load into.
- When loading data the last byte is signalled with EOI asserted - and at least one byte of data must be transmitted.

The program loads to $7C00 (31744 decimal) by default and takes no more than 1KB (finishing by $7FFF).

Before running a BASIC program, the loader resets BASIC pointers to by able to handle the loader's presence at $7C00.  Otherwise, BASIC fails to run, as the loader has been loaded into BASIC's string variable space.

Once a BASIC program has been run, the loader is disabled until re-enabled with `SYS 31744`). 

Once a machine language program is executed, and assuming it returned with `RTS`, the loader is automatically re-enabled.

## 📜License

Licensed under the MIT License. See LICENSE file for details.

## 🤝Contributing

Contributions are welcome.  Please feel free to submit a Pull Request.
