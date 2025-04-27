#!/bin/bash

# check_ram_filesize.sh - Check effective file size minus trailing null bytes
# and header
#
# This script calculates the effective size of a binary file by:
# 1. Getting the total file size
# 2. Counting the number of trailing null bytes ($00)
# 3. Subtracting the trailing nulls and a 2-byte header
# 4. Comparing the result against size limits based on memory layout
#
# Usage: ./check_file_size.sh [FILENAME] [CODE_START] [RAM_VAR_START] [MAX_FILE_SIZE]
#
# Example: ./check_file_size.sh myfile.bin '$7C00' '$7FE0' '$402'
#

# Display help information
show_help() {
    echo "Usage: $0 [FILENAME] [CODE_START] [RAM_VAR_START] [MAX_FILE_SIZE]"
    echo ""
    echo "Check if the RAM PRG file's effective size is within limits."
    echo "Effective size = total size - trailing nulls - 2 byte PRG header"
    echo ""
    echo "Arguments:"
    echo "  FILENAME       Path to the binary file to check"
    echo "  CODE_START     Starting address of code in hex (e.g. '$7C00')"
    echo "  RAM_VAR_START  Starting address of RAM variables in hex (e.g. '$7FE0')"
    echo "  MAX_FILE_SIZE  Maximum file size in hex (e.g. '$402')"
    echo ""
    echo "The script will report the file's effective size and whether it fits"
    echo "within the available memory space."
    exit 1
}

# Check if we have the right number of arguments
if [ $# -ne 4 ]; then
    show_help
fi

# Check if help was requested
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
fi

# Store the arguments
FILENAME="$1"
CODE_START="$2"
RAM_VAR_START="$3"
MAX_FILE_SIZE="$4"

# Check if file exists
if [ ! -f "$FILENAME" ]; then
    echo "Error: File '$FILENAME' not found."
    exit 2
fi

# Get the total file size in bytes
FILESIZE=$(stat -c %s "$FILENAME")
echo "- Total file size: $FILESIZE bytes"

# Count trailing null ($00) bytes
# This dumps the file as hex bytes, reverses the order with tac,
# and counts consecutive 00 bytes from the end
TRAILING_NULLS=$(hexdump -ve '1/1 "%02x\n"' "$FILENAME" | tac | awk '{ if ($1 == "00") count++; else exit } END { print count }')
echo "- Trailing null bytes: $TRAILING_NULLS"

# Calculate effective size (total - nulls - 2 bytes for header)
EFFECTIVE_SIZE=$((FILESIZE - TRAILING_NULLS - 2))
echo "- Effective size: $EFFECTIVE_SIZE bytes (after removing trailing nulls and 2-byte header)"

# Extract hex values, handling potential escaping
CODE_START_HEX=$(echo "$CODE_START" | sed 's/[\\$]//g')
RAM_VAR_START_HEX=$(echo "$RAM_VAR_START" | sed 's/[\\$]//g')
MAX_FILE_SIZE_HEX=$(echo "$MAX_FILE_SIZE" | sed 's/[\\$]//g')

# Convert to decimal
CODE_START_DEC=$((16#${CODE_START_HEX}))
RAM_VAR_START_DEC=$((16#${RAM_VAR_START_HEX}))
MAX_FILE_SIZE_DEC=$((16#${MAX_FILE_SIZE_HEX}))

# Debug info
echo "- Start address: $CODE_START_DEC (0x${CODE_START_HEX})"
echo "- RAM var address: $RAM_VAR_START_DEC (0x${RAM_VAR_START_HEX})"
echo "- Max code and header space: $MAX_FILE_SIZE_DEC (0x${MAX_FILE_SIZE_HEX})"

# Calculate code end location
CODE_END_DEC=$((CODE_START_DEC + (MAX_FILE_SIZE_DEC - 2)))
echo "- Code end address: 0x$(printf "%X" $CODE_END_DEC) ($CODE_END_DEC)"

# Calculate available space
AVAILABLE_SPACE=$((RAM_VAR_START_DEC - CODE_START_DEC))
echo "- Available code space: $AVAILABLE_SPACE bytes"

# Check if the effective size is within the available space
if [ $EFFECTIVE_SIZE -le $AVAILABLE_SPACE ]; then
    echo "PASS: Size is within the available space ($EFFECTIVE_SIZE of $AVAILABLE_SPACE bytes used)"
    exit 0
else
    echo "FAIL: Size exceeds the available space by $((EFFECTIVE_SIZE - AVAILABLE_SPACE)) bytes"
    exit 3
fi