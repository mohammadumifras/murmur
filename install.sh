#!/bin/bash
set -e

echo "Building Murmur..."
swift build

echo "Installing..."
cp .build/debug/Murmur ~/Desktop/Murmur

echo "Done! Run with: ~/Desktop/Murmur"
echo "Or double-click Murmur on your Desktop."
