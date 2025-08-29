#!/bin/bash
# Setup script for fromager learning environment
# Created with assistance from Cursor AI and Claude-4-Sonnet

set -e

echo "=== Fromager Learning Environment Setup ==="

# Check Python version
python_version=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
min_version="3.11"

if [ "$(printf '%s\n' "$min_version" "$python_version" | sort -V | head -n1)" != "$min_version" ]; then
    echo "Error: Python 3.11+ is required for Fromager. Found: $python_version"
    echo "Please install Python 3.11 or later to use Fromager."
    exit 1
fi

echo "✓ Python version check passed: $python_version"

# Create virtual environment
echo "Creating virtual environment..."
python3 -m venv fromager-env

# Activate virtual environment
echo "Activating virtual environment..."
source fromager-env/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install fromager (includes uv automatically)
echo "Installing fromager..."
echo "ℹ️  Note: fromager now uses 'uv' internally for faster build environment management"
echo "   'uv' will be installed automatically as a dependency"
pip install fromager

# Verify installation
echo "Verifying installation..."
if command -v fromager &> /dev/null; then
    echo "✓ Fromager installed successfully!"
    fromager --version
else
    echo "✗ Fromager installation failed"
    exit 1
fi

if command -v uv &> /dev/null; then
    echo "✓ uv installed successfully (required for fromager)"
    uv --version
else
    echo "✗ uv installation failed - this is required for fromager to work"
    exit 1
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "✓ uv is installed - fromager will automatically use it for faster builds"
echo ""
echo "To use fromager:"
echo "  source fromager-env/bin/activate"
echo "  fromager --version"
echo "  fromager --help"
echo ""
echo "To run the exercises:"
echo "  cd examples/exercises"
echo "  ./exercise1_beginner.sh"
echo ""
echo "Happy building! 🎉"
