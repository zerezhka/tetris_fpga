#!/usr/bin/env python3
"""
Convert a raw .bin ROM image to a $readmemh-compatible hex file
(one uppercase hex byte per line).

Usage: python3 bin2hex.py <in.bin> <out.hex>
"""
import sys

def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    with open(sys.argv[2], 'w') as f:
        for b in data:
            f.write(f"{b:02X}\n")

if __name__ == '__main__':
    main()
