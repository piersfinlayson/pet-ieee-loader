# Commodore PET IEEE Loader Makefile

# Actual load address for the program - where the binary gets loaded into RAM.
LOAD_ADDR ?= $$7C00

# Dummy address for the first 2 bytes of the PRG file, which stores the load
# address.
PRG_PREFIX_ADDR ?= $$7BFE

# Tools
CA65 = ca65
LD65 = ld65
C1541 = c1541
CHECK_IMM = loader/check_immediate.sh

# Directories
LOADER_SRC_DIR = loader
SENDER_DIR = sender
BUILD_DIR = $(LOADER_SRC_DIR)/build

# Extract the numeric part of LOAD_ADDR for the filename and convert to lowercase
LOAD_ADDR_HEX = $(shell echo $(subst $$,,$(LOAD_ADDR)) | tr '[:upper:]' '[:lower:]')

# Loader files
LOADER_SUFFIX = loader
LOADER_PREFIX = $(LOAD_ADDR_HEX)-$(LOADER_SUFFIX)
LOADER_MAIN_SRC_FILE = $(LOADER_SRC_DIR)/main.s
LOADER_IEEE_SRC_FILE = $(LOADER_SRC_DIR)/ieee.s
LOADER_TEST_SRC_FILE = $(LOADER_SRC_DIR)/test.s
INC_FILES = $(LOADER_SRC_DIR)/constants.inc $(LOADER_SRC_DIR)/macros.inc
LOADER_MAIN_OBJ_FILE = $(BUILD_DIR)/main.o
LOADER_IEEE_OBJ_FILE = $(BUILD_DIR)/ieee.o
LOADER_TEST_OBJ_FILE = $(BUILD_DIR)/test.o
OBJ_FILES = $(LOADER_MAIN_OBJ_FILE) $(LOADER_IEEE_OBJ_FILE) $(LOADER_TEST_OBJ_FILE)
PRG_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).prg
D64_FILE = $(BUILD_DIR)/$(LOADER_SUFFIX).d64
TEST_FILE = $(BUILD_DIR)/test.bin
LINK_TEMPLATE_FILE = $(LOADER_SRC_DIR)/template.cfg
LINK_FILE = $(BUILD_DIR)/config.cfg
MAP_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).map
DISK_NAME = "piers.rocks"

# Maximum size for the program, including the 2 byte PRG header
MAX_PRG_SIZE = $$402

# Compile options
CA65_FLAGS = -I src

# Link options
LD65_FLAGS =

# Default target
.PHONY: all
all: loader sender
loader: check_immediate $(PRG_FILE) $(D64_FILE) $(TEST_FILE)

check_immediate: $(CHECK_IMM)
	@$(CHECK_IMM) $(LOADER_SRC_DIR)/*.s || (echo "Immediate mode errors found!" && exit 1)

# Create build directory
$(BUILD_DIR):
	@mkdir -p $@

# Compile assembly to object file
$(LOADER_MAIN_OBJ_FILE): $(LOADER_MAIN_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@$(CA65) $(CA65_FLAGS) $< -o $@
$(LOADER_IEEE_OBJ_FILE): $(LOADER_IEEE_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@$(CA65) $(CA65_FLAGS) $< -o $@
$(LOADER_TEST_OBJ_FILE): $(LOADER_TEST_SRC_FILE) $(INC_FILES) | $(BUILD_DIR)
	@$(CA65) $(CA65_FLAGS) $< -o $@

# Generate the config file from the template
$(LINK_FILE): $(LINK_TEMPLATE_FILE) | $(BUILD_DIR)
	@sed -e 's/$${PRG_PREFIX_ADDR}/$(PRG_PREFIX_ADDR)/g' \
	    -e 's/$${MAX_PRG_SIZE}/$(MAX_PRG_SIZE)/g' \
	    -e 's/$${LOAD_ADDR}/$(LOAD_ADDR)/g' \
	    $(LINK_TEMPLATE_FILE) > $@

# Link object file to binary - this is a PRG file as we've included the 2-byte
# load address at the start.
$(PRG_FILE): $(OBJ_FILES) $(LINK_FILE) Makefile
	@$(LD65) $(LD65_FLAGS) -m $(MAP_FILE) -C $(LINK_FILE) $(OBJ_FILES) -o $@
	@echo "Built PRG file:"
	@ls -l $@

$(D64_FILE): $(PRG_FILE) Makefile
	@$(C1541) -format "$(DISK_NAME),01" d64 $(D64_FILE) -write $(PRG_FILE) $(LOADER_PREFIX) > /dev/null
	@echo "Created D64 image:"
	@ls -l $@

$(TEST_FILE): $(LOADER_TEST_OBJ_FILE) Makefile
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
