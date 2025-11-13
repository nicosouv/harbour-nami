#!/bin/bash
# Install Python dependencies locally for harbour-nami
# This script is run during RPM build to bundle dependencies

set -e

APP_DIR="/usr/share/harbour-nami"
PYTHON_LIB_DIR="$APP_DIR/python-lib"

echo "Installing Python dependencies to $PYTHON_LIB_DIR"

# Create lib directory
mkdir -p "$PYTHON_LIB_DIR"

# Install dependencies via pip to local directory
pip3 install --target="$PYTHON_LIB_DIR" --no-deps \
    numpy \
    opencv-python-headless \
    Pillow \
    onnxruntime

echo "Python dependencies installed successfully"
