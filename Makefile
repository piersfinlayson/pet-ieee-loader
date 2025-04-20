# Commodore PET IEEE Loader Makefile

# Tools
CA65 = ca65
LD65 = ld65

# Compile options
CA65_FLAGS = -I src

# Directories
BUILD_DIR = build
SRC_DIR = src

# Files
LOADER_PREFIX = pet-ieee-loader
SRC_FILE = $(SRC_DIR)/$(LOADER_PREFIX).s
OBJ_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).o
PRG_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).prg
LINK_FILE = ./link.cfg

# Default target
.PHONY: all
all: $(PRG_FILE)

# Create build directory
$(BUILD_DIR):
	mkdir -p $@

# Compile assembly to object file
$(OBJ_FILE): $(SRC_FILE) | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) $< -o $@

# Link object file to binary - this is a PRG file as we've included the 2-byte
# load address at the start.
$(PRG_FILE): $(OBJ_FILE) $(LINK_FILE)
	$(LD65) -C $(LINK_FILE) $< -o $@
	@ls -l $@

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
