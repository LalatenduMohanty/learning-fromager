#!/bin/bash
# Exercise 4: Performance - Parallel Building

echo "=== Exercise 4: Parallel Building for Speed ==="
echo "Goal: Compare serial vs parallel build performance"

# Check if fromager is available
if ! command -v fromager &> /dev/null; then
    echo "Error: fromager is not installed or not in PATH"
    echo "Please install fromager in your virtual environment first:"
    echo "  python -m pip install fromager"
    exit 1
fi

# Create a larger dependency tree for meaningful comparison
cat > requirements.txt << EOF
django==4.2.0
requests==2.31.0
sqlalchemy==2.0.0
click==8.1.7
jinja2==3.1.0
EOF

echo "=== Method 1: Traditional Bootstrap (Serial) ==="
echo "Building serially..."
time fromager bootstrap -r requirements.txt
serial_wheels=$(find wheels-repo -name "*.whl" | wc -l)
echo "Built $serial_wheels wheels serially"

# Clean up for fair comparison
rm -rf wheels-repo sdists-repo work-dir

echo -e "\n=== Method 2: Parallel Bootstrap ==="
echo "Building with parallel mode..."
time fromager bootstrap-parallel -r requirements.txt -m 4
parallel_wheels=$(find wheels-repo -name "*.whl" | wc -l)
echo "Built $parallel_wheels wheels in parallel"

echo -e "\n=== Method 3: Two-Phase Parallel Build ==="
# Clean up again
rm -rf wheels-repo sdists-repo work-dir

echo "Phase 1: Discovery only (fast)"
time fromager bootstrap -r requirements.txt --sdist-only

echo -e "\nPhase 2: Parallel build from graph"
time fromager build-parallel work-dir/graph.json -m 4

echo -e "\n=== Performance Comparison Complete! ==="
echo "The parallel methods should be significantly faster for large dependency trees"
echo "Check work-dir/logs/ for detailed build timing information"


