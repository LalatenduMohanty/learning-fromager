#!/bin/bash
# Exercise 2: Intermediate - Handle complex dependencies with constraints

echo "=== Exercise 2: Data Science Stack with Constraints ==="
echo "Goal: Build pandas stack while managing version conflicts"

# Create requirements with potential conflicts
cat > requirements.txt << EOF
pandas>=1.5.0
numpy>=1.21.0
matplotlib>=3.5.0
scipy>=1.9.0
EOF

# Create constraints to resolve conflicts
cat > constraints.txt << EOF
# Pin specific versions to avoid conflicts
numpy==1.24.0
matplotlib==3.6.0
pyparsing==3.0.9
EOF

echo "1. Building data science stack with constraints..."
fromager bootstrap -r requirements.txt -c constraints.txt

echo "2. Analyzing the build..."
echo "Number of packages built:"
find wheels-repo -name "*.whl" | wc -l

echo -e "\nLargest packages by build time:"
grep "took" work-dir/logs/*.log 2>/dev/null | head -5

echo -e "\n=== Exercise Complete! ==="
echo "Challenge: Try removing constraints.txt and see what conflicts arise"
