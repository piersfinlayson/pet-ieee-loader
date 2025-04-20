# Commodore PET IEEE Loader Makefile

# Tools
CA65 = ca65
LD65 = ld65
C1541 = c1541

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
D64_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).d64
LINK_FILE = ./link.cfg
DISK_NAME = "piers.rocks"

# Default target
.PHONY: all
all: $(PRG_FILE) $(D64_FILE)

# Create build directory
$(BUILD_DIR):
	@mkdir -p $@

# Compile assembly to object file
$(OBJ_FILE): $(SRC_FILE) | $(BUILD_DIR)
	@$(CA65) $(CA65_FLAGS) $< -o $@

# Link object file to binary - this is a PRG file as we've included the 2-byte
# load address at the start.
$(PRG_FILE): $(OBJ_FILE) $(LINK_FILE)
	@$(LD65) -C $(LINK_FILE) $< -o $@
	@echo "Built PRG file:"
	@ls -l $@

$(D64_FILE): $(PRG_FILE)
	@$(C1541) -format "$(DISK_NAME),01" d64 $(D64_FILE) -write $(PRG_FILE) ieee-loader > /dev/null
	@echo "Created D64 image:"
	@ls -l $@

# Clean build artifacts
.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR)
