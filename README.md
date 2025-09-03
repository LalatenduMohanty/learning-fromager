# Fromager Learning Guide

## What is Fromager?

Fromager is a tool for rebuilding Python wheel dependency trees from source, ensuring all binaries, dependencies, and build tools are built in a known environment.

**Official Documentation**: [https://fromager.readthedocs.io/en/latest/](https://fromager.readthedocs.io/en/latest/)
**Source Code**: [https://github.com/python-wheel-build/fromager](https://github.com/python-wheel-build/fromager)

It ensures that:

1. **Every binary package** was built from source in a known environment
2. **All dependencies** were also built from source (no pre-built wheels)
3. **All build tools** used were also built from source
4. **Builds can be customized** with patches, compilation options, and variants

### Introduction to Python Wheels

Python wheels are the modern standard for distributing pre-built Python packages. A wheel (.whl file) is a binary distribution format that allows for fast, reliable installation without requiring users to build packages from source.

If you're new to wheels, you can learn more from the Python Packaging Authority's [wheel documentation](https://packaging.python.org/en/latest/specifications/binary-distribution-format/).

A great source for learning how to build Python wheels is the official Python Packaging Authority (PyPA) guide: [Python Packaging User Guide](https://packaging.python.org/en/latest/tutorials/packaging-projects/)

## Getting Started

### Prerequisites and Installation

Before diving into the examples, you'll need to set up your environment:

#### Quick Setup (Recommended)
```bash
# Run the automated setup script
./setup.sh

# Activate the environment
source fromager-env/bin/activate
```

#### Manual Setup
```bash
# 1. Create a virtual environment (recommended)
python -m venv fromager-env
source fromager-env/bin/activate # On Windows: fromager-env\Scripts\activate

# 2. Install fromager
pip install fromager

# 3. Verify installation
fromager --version
fromager --help

# 4. Optional: Install system dependencies for complex packages
# On Fedora/RHEL:
sudo dnf install rust cargo gcc-c++ python3-devel
# On Ubuntu/Debian:
sudo apt install build-essential rustc cargo python3-dev
# On macOS:
xcode-select --install
```

### System Requirements

- **Python 3.11+** (required by Fromager)
- **Git** (for building from repositories)
- **System compiler** (gcc, clang, or MSVC)
- **Rust toolchain** (for Rust-based Python packages)
- **Network access** (for downloading source packages)
- **uv** (required - installed automatically with fromager for faster build environment management)

## Key Concepts

- **Bootstrap**: Automatically discovers and builds all dependencies recursively
- **Build Order**: The sequence dependencies must be built in (bottom-up)
- **Source Distribution (sdist)**: The source code package that gets compiled
- **Wheel**: The compiled binary package that gets installed
- **Constraints**: Version pinning to resolve conflicts
- **Variants**: Different build configurations (e.g., cpu, gpu)

### Requirements vs Constraints

Understanding the difference between `requirements.txt` and `constraints.txt` is crucial for effective dependency management:

**Requirements (`requirements.txt`)**
- **What you want to build**: Lists only package names (no versions)
- **Example**: `requests`, `flask`, `beautifulsoup4`
- **Purpose**: "I need these packages for my application"

**⚖️ Constraints (`constraints.txt`)**
- **How to resolve versions**: All version specifications go here
- **Example**: `requests>=2.25.0`, `urllib3==2.2.3`, `certifi==2024.8.30`
- **Purpose**: "When installing any package, use these version constraints"

**Why separate them?**
```bash
# requirements.txt - Package names only
requests
beautifulsoup4
flask

# constraints.txt - All version constraints
requests>=2.25.0
beautifulsoup4>=4.9.0
urllib3==2.2.3
certifi==2024.8.30
soupsieve==2.5
```

This keeps your dependency declarations clean while providing precise control over transitive dependencies that might conflict.

## Main CLI Commands

| Command | Purpose | Use Case |
|---------|---------|----------|
| `bootstrap` | Build all dependencies recursively | Initial setup, building entire stacks |
| `bootstrap-parallel` | Bootstrap + parallel builds | Faster builds for large dependency trees |
| `build` | Build a single package | Testing individual packages |
| `build-sequence` | Build from existing build order | Production builds, CI/CD |
| `build-parallel` | Build wheels in parallel from graph | High-performance parallel building |
| `step` | Individual build steps | Debugging, custom workflows |

## Learning Path: Practical Examples

### 1. Beginner: Simple Package Bootstrap

**Goal**: Build a simple package and understand the basic flow

```bash
# Create requirements.txt (package names only)
echo "click" > requirements.txt

# Create constraints.txt (version specifications)
echo "click==8.1.7" > constraints.txt

# Bootstrap (builds click and setuptools from source)
fromager bootstrap -r requirements.txt -c constraints.txt

# Examine results
ls wheels-repo/downloads/ # Built wheels
ls sdists-repo/downloads/ # Downloaded source distributions
cat work-dir/build-order.json # Build order determined
```

**What happens**:
1. Downloads `click-8.1.7.tar.gz` source → `sdists-repo/downloads/`
2. Discovers it needs `setuptools` to build
3. Builds `setuptools` first, then `click`
4. Rebuilds source distributions → `sdists-repo/builds/`
5. Creates wheels in `wheels-repo/`
6. Generates build order for reproducible builds

**Understanding the directories**:
```bash
# Check that downloads and builds look the same for simple packages
ls -la sdists-repo/downloads/
ls -la sdists-repo/builds/
# They appear identical - this is normal for unpatched packages!
```

### 2. Intermediate: Multiple Packages with Constraints

**Goal**: Handle version conflicts and complex dependencies

```bash
# requirements.txt (package names only)
cat > requirements.txt << EOF
requests
urllib3
beautifulsoup4
EOF

# constraints.txt (all version specifications)
cat > constraints.txt << EOF
requests>=2.25.0
urllib3==2.2.3
beautifulsoup4>=4.9.0
certifi==2024.8.30
charset-normalizer==3.3.0
EOF

# Bootstrap with constraints
fromager -c constraints.txt bootstrap -r requirements.txt
```

**Key learnings**:
- Constraints resolve version conflicts
- Dependencies can have complex trees
- Build order becomes more important
- Some packages may fail and need special handling

### 3. Intermediate: Building from Git Repositories

**Goal**: Build packages from source control instead of PyPI

```bash
# requirements.txt (git packages)
cat > requirements.txt << EOF
click @  git+https://github.com/pallets/click.git@8.1.7
requests @ git+https://github.com/psf/requests.git@v2.32.0
EOF

fromager bootstrap -r requirements.txt
```

### 4. Advanced: Single Package Build

**Goal**: Build just one package when you already have its dependencies

**When to use**: After bootstrapping dependencies, or when testing specific package versions

```bash
# First, you need to build the dependencies (setuptools for click)
echo "setuptools" > requirements.txt
echo "setuptools==80.9.0" > constraints.txt
fromager bootstrap -r requirements.txt -c constraints.txt

# Now build a specific package version using the built dependencies
fromager --no-network-isolation build click 8.1.7 https://pypi.org/simple/

# The wheel appears in wheels-repo/downloads/
ls wheels-repo/downloads/click-*
```

**Key difference**: `build` command builds only the specified package, while `bootstrap` discovers and builds all dependencies recursively. The `build` command expects build dependencies to already be available.

### 5. Advanced: Production Build Sequence

**Goal**: Use pre-determined build order for production

```bash
# First, generate build order
fromager bootstrap -r requirements.txt -c constraints.txt --sdist-only

# Then build in sequence (production)
fromager build-sequence work-dir/build-order.json

# Optional: Use external wheel server for production
# fromager build-sequence \
#   --wheel-server-url http://your-wheel-server/ \
#   work-dir/build-order.json
```

### 6. Advanced: Parallel Building for Performance

**Goal**: Speed up builds using parallel processing

```bash
# Option 1: Bootstrap with automatic parallel building
fromager bootstrap-parallel -r requirements.txt -c constraints.txt -m 4

# Option 2: Separate phases for maximum control
# Phase 1: Discover dependencies (serial)
fromager bootstrap -r requirements.txt -c constraints.txt --sdist-only

# Phase 2: Build wheels in parallel
fromager build-parallel work-dir/graph.json -m 4
```

**Key benefits**:
- Much faster for large dependency trees
- Respects dependency order automatically
- Can limit workers to avoid resource exhaustion

### 7. Expert: Custom Settings and Patches

**Goal**: Handle packages that need patches or special build settings

**Real-world example**: [pytest-asyncio v1.1.0](https://github.com/pytest-dev/pytest-asyncio/releases/tag/v1.1.0) fails to build due to obsolete setup.cfg configuration conflicts with modern setuptools_scm.

```bash
# Build the pytest-asyncio 1.1.0 version
# We expect it to fail
echo "pytest-asyncio" > requirements.txt
echo "pytest-asyncio==1.1.0" > constraints.txt

echo "=== This will fail without patches ==="
fromager bootstrap -r requirements.txt -c constraints.txt

# Expected error: setuptools_scm configuration conflicts
# Error related to obsolete setup.cfg and write_to parameter
```

```bash
# Create overrides directory structure
mkdir -p overrides/patches overrides/settings

# Create requirements and constraints for pytest-asyncio
echo "pytest-asyncio" > requirements.txt
echo "pytest-asyncio==1.1.0" > constraints.txt

# This will fail without patches:
# fromager bootstrap -r requirements.txt -c constraints.txt

# Create version-specific patch directory (using override name format)
mkdir -p overrides/patches/pytest_asyncio-1.1.0

# Create the patch to fix build issues
cat > overrides/patches/pytest_asyncio-1.1.0/0001-remove-obsolete-setup-cfg.patch << 'EOF'
diff --git a/pyproject.toml b/pyproject.toml
index 1234567..abcdefg 100644
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -67,7 +67,6 @@ packages = [
 include-package-data = true

 [tool.setuptools_scm]
- write_to = "pytest_asyncio/_version.py"
 local_scheme = "no-local-version"

 [tool.ruff]
@@ -138,9 +137,6 @@ source = [
 ]
 branch = true
 data_file = "coverage/coverage"
- omit = [
- "*/_version.py",
- ]
 parallel = true

 [tool.coverage.report]
diff --git a/setup.cfg b/setup.cfg
deleted file mode 100644
index 1234567..0000000
--- a/setup.cfg
+++ /dev/null
@@ -1,7 +0,0 @@
- [metadata]
- version = attr: pytest_asyncio.__version__
- 
- [egg_info]
- tag_build = 
- tag_date = 0
- 
EOF

# Now it will build successfully with the patch applied
fromager bootstrap -r requirements.txt -c constraints.txt
```

**What the patch fixes**:
- Removes obsolete `setup.cfg` that conflicts with `pyproject.toml`
- Removes deprecated `write_to` parameter from setuptools_scm configuration
- Cleans up version handling conflicts between old and new packaging approaches

## Directory Structure After Running Fromager

```
.
├── requirements.txt # Your input requirements
├── constraints.txt # Version constraints (optional)
├── overrides/ # Customization (advanced)
│   ├── patches/ # Source code patches
│   └── settings/ # Per-package build settings
├── sdists-repo/ # Source distributions
│   ├── downloads/ # Downloaded from PyPI/git
│   └── builds/ # Rebuilt with patches applied
├── wheels-repo/ # Built wheels
│   ├── downloads/ # Final wheels
│   ├── build/ # Intermediate builds
│   └── simple/ # PyPI-compatible index
└── work-dir/ # Temporary build files
    ├── build-order.json # Dependency build order
    ├── constraints.txt # Generated constraints
    └── package-*/ # Build directories
```

### Understanding `sdists-repo/downloads` vs `sdists-repo/builds`

**Key Insight**: These directories may look identical for simple packages, but serve different purposes:

#### `sdists-repo/downloads/`
- Contains **original, unmodified** source distributions from PyPI/git
- Exact `.tar.gz` files as published by package authors
- Example: `click-8.1.7.tar.gz` exactly as it exists on PyPI

#### `sdists-repo/builds/`
- Contains **rebuilt** source distributions created by fromager
- Includes any modifications: patches, vendored dependencies, etc.
- **Always rebuilt** to ensure consistency and reproducibility

#### When They Look the Same
For simple packages like `click==8.1.7`:
- No patches applied ✓
- No Rust dependencies to vendor ✓
- No source modifications ✓
- **Result**: Rebuilt sdist appears identical to original

**This is normal and expected!** Fromager applies the same rigorous rebuilding process to all packages.

#### When They Differ Significantly
The directories will have different content for:

1. **Rust packages** (e.g., `pydantic-core`):
   ```bash
   # Original: ~500KB
   # Rebuilt: ~15MB (with vendored Rust dependencies)
   ```

2. **Patched packages**:
   ```bash
   # downloads/: Original source
   # builds/: Source + your custom patches
   ```

3. **Complex build processes**:
   - Normalized compression and format
   - Consistent metadata
   - Reproducible tarballs

## Common Use Cases

### 1. Enterprise/Secure Environment
- Need to verify all code is built from trusted sources
- Cannot use pre-built wheels from PyPI
- Require reproducible builds

```bash
fromager bootstrap -r requirements.txt --network-isolation
```

### 2. Custom Compilation Options
- Need specific compiler flags for performance
- Building for special hardware (ARM, etc.)
- Different variants (debug vs release)

```bash
# Use build variants
fromager --variant gpu bootstrap -r requirements.txt
```

### 3. Patching Dependencies
- Fix bugs in upstream packages
- Add custom features
- Security patches

```bash
# Patches automatically applied during build
fromager bootstrap -r requirements.txt
```

### 4. CI/CD Pipelines
- Reproducible builds in continuous integration
- Separate discovery from building phases

```bash
# Phase 1: Discover dependencies
fromager bootstrap -r requirements.txt --sdist-only

# Phase 2: Build in production
fromager build-sequence work-dir/build-order.json
```

## Troubleshooting Common Issues

### 1. "Why do downloads and builds look identical?"

**Question**: The `sdists-repo/downloads/` and `sdists-repo/builds/` contain the same files

**Answer**: This is **normal** for simple packages without patches or special build requirements

```bash
# This is expected behavior:
$ ls sdists-repo/downloads/ sdists-repo/builds/
# click-8.1.7.tar.gz appears in both directories

# To see real differences, try a Rust package:
$ echo "pydantic-core" > requirements.txt
$ echo "pydantic-core==2.18.4" > constraints.txt
$ fromager bootstrap -r requirements.txt -c constraints.txt
$ ls -lh sdists-repo/downloads/pydantic_core-*  # ~500KB original
$ ls -lh sdists-repo/builds/pydantic_core-*     # ~15MB with vendored deps
```

### 2. Package Fails to Build

**Problem**: Complex package with system dependencies

**Solution**: Mark as pre-built temporarily

```yaml
# overrides/settings/difficult-package.yaml
pre_built: true
pre_built_url: "https://files.pythonhosted.org/packages/.../package.whl"
```

### 3. Version Conflicts

**Problem**: Multiple packages want different versions of same dependency

**Solution**: Use constraints.txt

```txt
# constraints.txt
conflicting-package==1.2.3
```

### 4. Missing System Dependencies

**Problem**: Package needs system libraries (like Rust, C++ compiler)

**Solution**: Install system deps or use containers

```bash
# Install system dependencies first
sudo dnf install rust cargo gcc-c++
fromager bootstrap -r requirements.txt
```

## Next Steps for Mastery

1. **Study the test suite**: Look at `e2e/test_*.sh` for real examples
2. **Read the docs**: `docs/customization.md` for advanced features
3. **Practice with complex packages**: Try matplotlib, scipy, torch
4. **Contribute**: Fix issues in packages that don't build cleanly
5. **Use in production**: Set up CI/CD pipelines with fromager

## Pro Tips

- Start simple and gradually add complexity
- Use `--sdist-only` for faster dependency discovery
- Always check `work-dir/build-order.json` to understand dependencies
- Use containers for complex system dependencies
- Keep your `overrides/` directory in version control
- Monitor build times and optimize bottlenecks
- Use `fromager stats` to analyze your builds

---

## Acknowledgments

This learning guide was enhanced with assistance from **Cursor AI** and **Claude-4-Sonnet**
