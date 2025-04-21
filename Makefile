# Commodore PET IEEE Loader Makefile

# Tools
CA65 = ca65
LD65 = ld65
C1541 = c1541

# Compile options
CA65_FLAGS = -I src

# Directories
LOADER_SRC_DIR = loader
SENDER_DIR = sender
BUILD_DIR = $(LOADER_SRC_DIR)/build

# Files
LOADER_PREFIX = pet-ieee-loader
SRC_FILE = $(LOADER_SRC_DIR)/$(LOADER_PREFIX).s
OBJ_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).o
PRG_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).prg
D64_FILE = $(BUILD_DIR)/$(LOADER_PREFIX).d64
LINK_FILE = $(LOADER_SRC_DIR)/link.cfg
DISK_NAME = "piers.rocks"

# Rust output files
SENDER_DEBUG = $(SENDER_DIR)/target/debug/sender
SENDER_RELEASE = $(SENDER_DIR)/target/release/sender

# Default target
.PHONY: all
loader: $(PRG_FILE) $(D64_FILE)
all: loader sender

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

# Force sender targets to always run by making them phony targets
.PHONY: sender sender-debug sender-release
sender: sender-debug sender-release
	@echo "Sender built (debug and release versions)."

sender-debug:
	@echo "Building sender (debug)..."
	@cd $(SENDER_DIR) && cargo build
	@echo "Sender debug build completed."

sender-release:
	@echo "Building sender (release)..."
	@cd $(SENDER_DIR) && cargo build --release
	@echo "Sender release build completed."

# Clean build artifacts
.PHONY: clean
clean: clean_loader clean_sender
clean_loader:
	@rm -rf $(BUILD_DIR)
clean_sender:
	@cd $(SENDER_DIR) && \
		cargo clean
