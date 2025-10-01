#!/bin/bash
# Exercise 2: Intermediate - Handle complex dependencies with constraints

echo "=== Exercise 2: Data Science Stack with Constraints ==="
echo "Goal: Build pandas stack while managing version conflicts"

# Check if fromager is available
if ! command -v fromager &> /dev/null; then
    echo "Error: fromager is not installed or not in PATH"
    echo "Please install fromager in your virtual environment first:"
    echo "  python -m pip install fromager"
    exit 1
fi

# Create requirements (package names only)
cat > requirements.txt << EOF
pandas
numpy
matplotlib
scipy
EOF

# Create constraints (all version specifications)
cat > constraints.txt << EOF
# Pin specific versions to avoid conflicts
pandas>=1.5.0
numpy==1.24.0
matplotlib==3.6.0
scipy>=1.9.0
pyparsing==3.0.9
EOF

echo "1. Building data science stack with constraints..."
fromager -c constraints.txt bootstrap -r requirements.txt

echo "2. Analyzing the build..."
echo "Number of packages built:"
find wheels-repo -name "*.whl" | wc -l

echo -e "\nLargest packages by build time:"
grep "took" work-dir/logs/*.log 2>/dev/null | head -5

echo -e "\n=== Exercise Complete! ==="
echo "Challenge: Try removing constraints.txt and see what conflicts arise"
