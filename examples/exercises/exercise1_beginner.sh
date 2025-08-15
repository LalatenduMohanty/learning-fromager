#!/bin/bash
# Exercise 1: Beginner - Build a simple web framework stack

echo "=== Exercise 1: Building Flask from Source ==="
echo "Goal: Build Flask and understand dependency resolution"

# Create requirements
cat > requirements.txt << EOF
Flask==3.0.0
EOF

echo "1. Building Flask and all dependencies from source..."
fromager bootstrap -r requirements.txt

echo "2. Examining results..."
echo "Built wheels:"
find wheels-repo -name "*.whl" | sort

echo -e "\nDependency build order:"
cat work-dir/build-order.json | python -m json.tool

echo -e "\nGenerated constraints:"
cat work-dir/constraints.txt

echo -e "\n=== Exercise Complete! ==="
echo "Next: Try building with different Flask versions to see how dependencies change"
