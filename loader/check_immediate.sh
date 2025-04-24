#!/bin/bash

# Script to check for 6502 assembly operations that should use immediate mode but don't
# Also warns about using immediate decimal instead of hex
# Usage: ./check_immediate.sh [files]

# Operations that commonly use immediate values
OPS="AND ORA EOR ADC SBC CMP CPX CPY LDA LDX LDY BIT"

# If no files provided, search for assembly files
if [ $# -eq 0 ]; then
    FILES=$(find . -name "*.s" -o -name "*.asm")
else
    FILES="$@"
fi

FOUND_ERRORS=0

for FILE in $FILES; do
    # Process with awk for better pattern matching
    awk -v ops="$OPS" '
    BEGIN {
        split(ops, op_array, " ")
        for (i in op_array) ops_hash[op_array[i]] = 1
        found_errors = 0
    }
    
    # Skip comments and empty lines
    /^\s*;/ || /^\s*$/ { next }
    
    {
        # Remove inline comments
        gsub(/;.*$/, "")
        
        # Match operation at start of line (with optional whitespace)
        if (match($0, /^\s*([A-Za-z]+)/, op_match)) {
            op = op_match[1]
            
            # Check if this is an operation we care about
            if (op in ops_hash) {
                # Get the rest of the line after the operation
                rest = substr($0, RLENGTH + 1)
                
                # Check for immediate decimal values (warning only)
                if (match(rest, /^\s*#([0-9]+)/, dec_match)) {
                    if (!(dec_match[1] ~ /^\$/ || dec_match[1] ~ /^%/)) {
                        printf("%s:%d: note: immediate decimal value used: %s\n", 
                               FILENAME, FNR, $0)
                        printf("  Suggestion: %s #$%X\n", op, dec_match[1])
                    }
                    next
                }
                
                # Skip if already using immediate mode (#)
                if (rest ~ /^\s*#/) next
                
                # Skip if using indexed addressing (,X or ,Y)
                if (rest ~ /,\s*[XY]/) next
                
                # Check for hex value without #
                if (match(rest, /^\s*\$([0-9A-Fa-f]+)/, hex_match)) {
                    # Skip if followed by an identifier (likely a constant)
                    after = substr(rest, RSTART + RLENGTH)
                    if (after ~ /^\s*[A-Za-z_]/) next
                    
                    # Found a likely error
                    printf("%s:%d: error: likely missing # for immediate hex: %s\n", 
                           FILENAME, FNR, $0)
                    printf("  Suggestion: %s #$%s\n", op, hex_match[1])
                    found_errors = 1
                }
                # Check for decimal value without #
                else if (match(rest, /^\s*([0-9]+)/, dec_match)) {
                    # Skip if followed by an identifier (likely a constant)
                    after = substr(rest, RSTART + RLENGTH)
                    if (after ~ /^\s*[A-Za-z_]/) next
                    
                    # Found a likely error
                    printf("%s:%d: error: likely missing # for immediate decimal: %s\n", 
                           FILENAME, FNR, $0)
                    printf("  Suggestion: %s #$%X\n", op, dec_match[1])
                    found_errors = 1
                }
            }
        }
    }
    END {
        exit (found_errors ? 1 : 0)
    }
    ' "$FILE"
    
    # Track if any errors were found
    if [ $? -ne 0 ]; then
        FOUND_ERRORS=1
    fi
done

exit $FOUND_ERRORS