#!/bin/bash
# Exercise 3: Advanced - Production build workflow

echo "=== Exercise 3: Production Build Pipeline ==="
echo "Goal: Separate discovery and building phases like in CI/CD"

# Check if fromager is available
if ! command -v fromager &> /dev/null; then
    echo "Error: fromager is not installed or not in PATH"
    echo "Please install fromager in your virtual environment first:"
    echo "  python -m pip install fromager"
    exit 1
fi

# Create a realistic web app stack
cat > requirements.txt << EOF
fastapi==0.104.0
uvicorn==0.24.0
sqlalchemy==2.0.23
pydantic==2.5.0
EOF

echo "Phase 1: Discovery (fast, --sdist-only mode)"
fromager bootstrap -r requirements.txt --sdist-only

echo -e "\nPhase 2: Production build sequence"
fromager build-sequence work-dir/build-order.json

echo -e "\nPhase 3: Build statistics"
fromager stats work-dir/build-order.json requirements.txt

echo -e "\n=== Advanced Workflow Complete! ==="
echo "This simulates how you'd use fromager in CI/CD pipelines"
