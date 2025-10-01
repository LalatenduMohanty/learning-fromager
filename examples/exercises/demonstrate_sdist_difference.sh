#!/bin/bash
# Demonstrate the difference between downloads and builds

echo "=== Demonstrating sdists-repo/downloads vs builds difference ==="

# Let's build a Rust package that vendors dependencies
cat > requirements.txt << EOF
pydantic-core
EOF

cat > constraints.txt << EOF
pydantic-core==2.18.4
EOF

echo "Building pydantic-core (Rust package that vendors dependencies)..."

# Check if fromager is available
if ! command -v fromager &> /dev/null; then
    echo "Error: fromager is not installed or not in PATH"
    echo "Please install fromager in your virtual environment first:"
    echo "  python -m pip install fromager"
    echo "Or activate your virtual environment where fromager is installed."
    exit 1
fi

fromager -c constraints.txt bootstrap -r requirements.txt

echo -e "\n=== Comparing sdist sizes ==="
echo "Original download:"
ls -lh sdists-repo/downloads/pydantic_core-*
echo -e "\nRebuilt with vendored dependencies:"
ls -lh sdists-repo/builds/pydantic_core-*

echo -e "\n=== Examining content differences ==="
echo "Let's extract and compare (this will show vendored Rust deps):"

# Create temp directories
mkdir -p temp/original temp/rebuilt

# Extract both
cd temp/original
tar -tf ../../sdists-repo/downloads/pydantic_core-*.tar.gz | head -20
echo "..."

cd ../rebuilt  
tar -tf ../../sdists-repo/builds/pydantic_core-*.tar.gz | head -20
echo "..."

cd ../..
rm -rf temp

echo -e "\n=== Key Insight ==="
echo "The 'builds' version contains vendored Rust dependencies that weren't in the original!"
echo "This is why fromager rebuilds even 'unchanged' packages - to ensure consistency."
