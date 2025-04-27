#!/bin/bash

# Creates 1 Mbit (128KB) ROM image filled with copies of the ROM loader image.

# Function to display help information
show_help() {
    echo "Usage: $0 [OPTION]"
    echo "Fills a 1Mbit (128KB) file with copies of the ROM loader image."
    echo
    echo "Options:"
    echo "  x000        Use x000 image (default if no option specified is 9000)"
    echo "  -h, -?, --help  Display this help and exit"
    echo
    echo "Example:"
    echo "  $0          # Uses 9000 image by default"
    echo "  $0 a000     # Uses A000 image"
    echo "  $0 --help   # Displays this help message"
    exit 0
}

# Process command line argument
IMAGE_TYPE="9000"  # Default value
if [ $# -gt 0 ]; then
    case "$1" in
        "-h"|"-?"|"--help")
            show_help
            ;;
        "9000"|"a000"|"b000"|"c000"|"d000"|"e000"|"f000")
            IMAGE_TYPE="$1"
            ;;
        *)
            echo "Error: Unrecognized option '$1'"
            echo "Use '$0 --help' for more information."
            exit 1
            ;;
    esac
fi

# Input and output files based on the image type
INPUT_FILE="loader/build/${IMAGE_TYPE}-loader-rom.bin"
OUTPUT_FILE="loader/build/${IMAGE_TYPE}-loader-rom-1mbit.bin"

COPIES=32

# Create/truncate output file
> "$OUTPUT_FILE"

# Add complete copies
for ((i=0; i<COPIES; i++)); do
    cat "$INPUT_FILE" >> "$OUTPUT_FILE"
done