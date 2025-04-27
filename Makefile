#
# Commodore PET IEEE Loader Makefile
#

# Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
#
# Licensed under the MIT License.  See [LICENSE] for details.

# Load address for the ROM version of the program.
ROM_LOAD_ADDR ?= 9000

# Maximum size for the ROM version
MAX_ROM_SIZE ?= 1000

# Load address for the RAM version of the program.
RAM_LOAD_ADDR ?= 7C00
RAM_VAR_ADDR ?= 7FE0

# Maximum size for the program, including the 2 byte PRG header and the RAM
# variable area.
MAX_PRG_SIZE = 402

# Dummy address for the first 2 bytes of the PRG file, which stores the load
# address for the RAM version of the program.
PRG_PREFIX_ADDR ?= 7BFE

# Tools
CA65 = ca65
LD65 = ld65
C1541 = c1541
CHECK_IMM = loader/check_immediate.sh
CHECK_RAM_FILESIZE = loader/check_ram_filesize.sh
MAKE_1MBIT_ROM = loader/make_1mbit_image.sh

# Directories
LOADER_SRC_DIR = loader
SENDER_DIR = sender
BUILD_DIR = $(LOADER_SRC_DIR)/build

# Extract the numeric part of LOAD_ADDRs for the filename and convert to lowercase
RAM_LOAD_ADDR_HEX = $(shell echo $(subst $$,,$(RAM_LOAD_ADDR)) | tr '[:upper:]' '[:lower:]')
ROM_LOAD_ADDR_HEX = $(shell echo $(subst $$,,$(ROM_LOAD_ADDR)) | tr '[:upper:]' '[:lower:]')

# Loader files common
LOADER_SUFFIX = loader
LOADER_MAIN_SRC_FILE = $(LOADER_SRC_DIR)/main.s
LOADER_IEEE_SRC_FILE = $(LOADER_SRC_DIR)/ieee.s
LOADER_TEST_SRC_FILE = $(LOADER_SRC_DIR)/test.s
INC_FILES = $(LOADER_SRC_DIR)/constants.inc $(LOADER_SRC_DIR)/macros.inc

# RAM version files
RAM_LOADER_PREFIX = $(RAM_LOAD_ADDR_HEX)-$(LOADER_SUFFIX)
RAM_LINK_TEMPLATE = $(LOADER_SRC_DIR)/ram_template.cfg
RAM_LINK_FILE = $(BUILD_DIR)/ram_config.cfg
RAM_MAP_FILE = $(BUILD_DIR)/$(RAM_LOADER_PREFIX).map
RAM_PRG_FILE = $(BUILD_DIR)/$(RAM_LOADER_PREFIX).prg
D64_FILE = $(BUILD_DIR)/$(LOADER_SUFFIX).d64

# ROM version files
ROM_LOADER_PREFIX = $(ROM_LOAD_ADDR_HEX)-$(LOADER_SUFFIX)-rom
ROM_LINK_TEMPLATE = $(LOADER_SRC_DIR)/rom_template.cfg
ROM_LINK_FILE = $(BUILD_DIR)/rom_config.cfg
ROM_MAP_FILE = $(BUILD_DIR)/$(ROM_LOADER_PREFIX).map
ROM_BIN_FILE = $(BUILD_DIR)/$(ROM_LOADER_PREFIX).bin

# Object files
LOADER_MAIN_RAM_OBJ_FILE = $(BUILD_DIR)/main_ram.o
LOADER_IEEE_RAM_OBJ_FILE = $(BUILD_DIR)/ieee_ram.o
LOADER_MAIN_ROM_OBJ_FILE = $(BUILD_DIR)/main_rom.o
LOADER_IEEE_ROM_OBJ_FILE = $(BUILD_DIR)/ieee_rom.o
LOADER_TEST_OBJ_FILE = $(BUILD_DIR)/test.o

RAM_OBJ_FILES = $(LOADER_MAIN_RAM_OBJ_FILE) $(LOADER_IEEE_RAM_OBJ_FILE)
ROM_OBJ_FILES = $(LOADER_MAIN_ROM_OBJ_FILE) $(LOADER_IEEE_ROM_OBJ_FILE)

# Test file
TEST_FILE = $(BUILD_DIR)/test.bin

# Disk name
DISK_NAME = "piers.rocks"

# Compile options
CA65_FLAGS = -I src
CA65_ROM_FLAGS = $(CA65_FLAGS) -D ROM_VERSION -D RAM_TAPE_BUF

# Link options
LD65_FLAGS =

# Default target
.PHONY: all
all: loader sender
loader: check_immediate loader-ram loader-rom loader-test

# Building RAM version
.PHONY: loader-ram
loader-ram: $(RAM_PRG_FILE) $(D64_FILE)

# Building ROM version
.PHONY: loader-rom
loader-rom: $(ROM_BIN_FILE)

# Building test
.PHONY: loader-test
loader-test: $(TEST_FILE)

check_immediate: $(CHECK_IMM)
	@$(CHECK_IMM) $(LOADER_SRC_DIR)/*.s || (echo "Immediate mode errors found!" && exit 1)

# Create build directory
$(BUILD_DIR):
	@mkdir -p $@

# Compile assembly to object file for RAM version
$(LOADER_MAIN_RAM_OBJ_FILE): $(LOADER_MAIN_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@echo "Compiling $(notdir $<) for RAM..."
	@$(CA65) $(CA65_FLAGS) $< -o $@

$(LOADER_IEEE_RAM_OBJ_FILE): $(LOADER_IEEE_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@echo "Compiling $(notdir $<) for RAM..."
	@$(CA65) $(CA65_FLAGS) $< -o $@

# Compile assembly to object file for ROM version
$(LOADER_MAIN_ROM_OBJ_FILE): $(LOADER_MAIN_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@echo "Compiling $(notdir $<) for ROM..."
	@$(CA65) $(CA65_ROM_FLAGS) $< -o $@

$(LOADER_IEEE_ROM_OBJ_FILE): $(LOADER_IEEE_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@echo "Compiling $(notdir $<) for ROM..."
	@$(CA65) $(CA65_ROM_FLAGS) $< -o $@

# Compile test object
$(LOADER_TEST_OBJ_FILE): $(LOADER_TEST_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@echo "Compiling $(notdir $<)..."
	@$(CA65) $(CA65_FLAGS) $< -o $@

# Generate the RAM config file from the template
$(RAM_LINK_FILE): $(RAM_LINK_TEMPLATE) | $(BUILD_DIR)
	@echo "Generating RAM linker config..."
	@echo "PRG_PREFIX_ADDR = $(PRG_PREFIX_ADDR)"
	@echo "MAX_PRG_SIZE = $(MAX_PRG_SIZE)"
	@echo "RAM_LOAD_ADDR = $(RAM_LOAD_ADDR)"
	@echo "RAM_VAR_ADDR = $(RAM_VAR_ADDR)"
	@sed -e 's/$${PRG_PREFIX_ADDR}/$$$(PRG_PREFIX_ADDR)/g' \
	    -e 's/$${MAX_PRG_SIZE}/$$$(MAX_PRG_SIZE)/g' \
	    -e 's/$${LOAD_ADDR}/$$$(RAM_LOAD_ADDR)/g' \
	    -e 's/$${VAR_ADDR}/$$$(RAM_VAR_ADDR)/g' \
	    $(RAM_LINK_TEMPLATE) > $@

# Generate the ROM config file from the template
$(ROM_LINK_FILE): $(ROM_LINK_TEMPLATE) | $(BUILD_DIR)
	@echo "Generating ROM linker config..."
	@sed -e 's/$${LOAD_ADDR}/$$$(ROM_LOAD_ADDR)/g' \
	    -e 's/$${MAX_ROM_SIZE}/$$$(MAX_ROM_SIZE)/g' \
	    $(ROM_LINK_TEMPLATE) > $@

# Link object file to RAM binary (PRG file)
$(RAM_PRG_FILE): $(RAM_OBJ_FILES) $(RAM_LINK_FILE) Makefile
	@echo "Linking RAM version..."
	@$(LD65) $(LD65_FLAGS) -m $(RAM_MAP_FILE) -C $(RAM_LINK_FILE) $(RAM_OBJ_FILES) -o $@
	@echo "Built PRG file:"
	@ls -l $@
	@echo "Checking RAM file size..."
	@$(CHECK_RAM_FILESIZE) $@ $(RAM_LOAD_ADDR) $(RAM_VAR_ADDR) $(MAX_PRG_SIZE)

# Link object file to ROM binary (BIN file)
$(ROM_BIN_FILE): $(ROM_OBJ_FILES) $(ROM_LINK_FILE) Makefile
	@echo "Linking ROM version..."
	@$(LD65) $(LD65_FLAGS) -m $(ROM_MAP_FILE) -C $(ROM_LINK_FILE) $(ROM_OBJ_FILES) -o $@
	@echo "Built ROM binary:"
	@ls -l $@
	@$(MAKE_1MBIT_ROM) $(ROM_LOAD_ADDR)

# Create D64 disk image
$(D64_FILE): $(RAM_PRG_FILE) Makefile
	@echo "Creating D64 disk image..."
	@$(C1541) -format "$(DISK_NAME),01" d64 $(D64_FILE) -write $(RAM_PRG_FILE) $(RAM_LOADER_PREFIX) > /dev/null
	@echo "Created D64 image:"
	@ls -l $@

# Build test binary
$(TEST_FILE): $(LOADER_TEST_OBJ_FILE) Makefile
	@echo "Building test binary..."
	@$(LD65) -t none $(LD65_FLAGS) $(LOADER_TEST_OBJ_FILE) -o $@
	@echo "Built test binary:"
	@ls -l $@

# Force sender targets to always run by making them phony targets
.PHONY: sender sender-debug sender-release
sender: sender-debug sender-release
	@echo "Sender built (debug and release versions)."

sender-debug: Makefile
	@echo "Building sender (debug)..."
	@cd $(SENDER_DIR) && cargo build
	@echo "Sender debug build completed."

sender-release: Makefile
	@echo "Building sender (release)..."
	@cd $(SENDER_DIR) && cargo build --release
	@echo "Sender release build completed."

# Clean build artifacts
.PHONY: clean
clean: clean-loader clean-sender
clean-loader:
	@rm -rf $(BUILD_DIR)
clean-sender:
	@cd $(SENDER_DIR) && \
		cargo clean -q