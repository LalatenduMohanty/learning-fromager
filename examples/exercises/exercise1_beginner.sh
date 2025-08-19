#!/bin/bash
# Exercise 1: Beginner - Build a simple web framework stack

echo "=== Exercise 1: Building Flask from Source ==="
echo "Goal: Build Flask and understand dependency resolution"

# Check if fromager is available
if ! command -v fromager &> /dev/null; then
    echo "Error: fromager is not installed or not in PATH"
    echo "Please install fromager in your virtual environment first:"
    echo "  python -m pip install fromager"
    exit 1
fi

# Create requirements (package names only)
cat > requirements.txt << EOF
Flask
EOF

# Create constraints (version specifications)
cat > constraints.txt << EOF
Flask==3.0.0
EOF

echo "1. Building Flask and all dependencies from source..."
fromager bootstrap -r requirements.txt -c constraints.txt

echo "2. Examining results..."
echo "Built wheels:"
find wheels-repo -name "*.whl" | sort

echo -e "\nDependency build order:"
cat work-dir/build-order.json | python -m json.tool

echo -e "\nGenerated constraints:"
cat work-dir/constraints.txt

echo -e "\n=== Exercise Complete! ==="
echo "Next: Try building with different Flask versions to see how dependencies change"
