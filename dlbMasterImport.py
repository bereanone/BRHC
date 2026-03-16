#!/usr/bin/env python3

import subprocess
import sys
import os

def run(cmd):
    print(f"Running command: {cmd}")
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        print(f"Command failed with exit code {result.returncode}: {cmd}")
        sys.exit(result.returncode)

def main():
    print("="*40)
    print("Starting full BRHC rebuild")
    print("="*40)

    # Check if running inside .venv virtual environment
    if ".venv" not in sys.prefix:
        print("Warning: You do not appear to be running inside the .venv virtual environment.")

    run("python dlbImportImages.py")
    run("python dlbDocxImport.py --import")
    run("python dlbDocxInsertBlocks.py")

if __name__ == "__main__":
    main()
