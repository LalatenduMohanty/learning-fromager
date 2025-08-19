# Fromager Learning Guide

## What is Fromager?

Fromager is a tool for completely rebuilding Python package dependency trees from source. 

**Official Documentation**: [https://fromager.readthedocs.io/en/latest/](https://fromager.readthedocs.io/en/latest/)  
**Source Code**: [https://github.com/python-wheel-build/fromager](https://github.com/python-wheel-build/fromager)

It ensures that:

1. **Every binary package** was built from source in a known environment
2. **All dependencies** were also built from source (no pre-built wheels)  
3. **All build tools** used were also built from source
4. **Builds can be customized** with patches, compilation options, and variants

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
source fromager-env/bin/activate  # On Windows: fromager-env\Scripts\activate

# 2. Install fromager
pip install fromager

# 3. Verify installation
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

## Key Concepts

- **Bootstrap**: Automatically discovers and builds all dependencies recursively
- **Build Order**: The sequence dependencies must be built in (bottom-up)
- **Source Distribution (sdist)**: The source code package that gets compiled
- **Wheel**: The compiled binary package that gets installed
- **Constraints**: Version pinning to resolve conflicts
- **Variants**: Different build configurations (e.g., cpu, gpu)

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
# Create requirements.txt
echo "click==8.1.7" > requirements.txt

# Bootstrap (builds click and setuptools from source)
fromager bootstrap -r requirements.txt

# Examine results
ls wheels-repo/downloads/  # Built wheels
ls sdists-repo/downloads/  # Downloaded source distributions
cat work-dir/build-order.json  # Build order determined
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
# requirements.txt
cat > requirements.txt << EOF
requests>=2.25.0
urllib3>=1.26.0
beautifulsoup4>=4.9.0
EOF

# constraints.txt - Pin versions to avoid conflicts
cat > constraints.txt << EOF
urllib3==2.2.3
certifi==2024.8.30
charset-normalizer==3.3.0
EOF

# Bootstrap with constraints
fromager bootstrap -r requirements.txt -c constraints.txt
```

**Key learnings**:
- Constraints resolve version conflicts
- Dependencies can have complex trees
- Build order becomes more important
- Some packages may fail and need special handling

### 3. Intermediate: Building from Git Repositories

**Goal**: Build packages from source control instead of PyPI

```bash
# requirements.txt with git URLs
cat > requirements.txt << EOF
git+https://github.com/pallets/click.git@8.1.7
git+https://github.com/psf/requests.git@v2.32.0
EOF

fromager bootstrap -r requirements.txt
```

### 4. Advanced: Single Package Build

**Goal**: Build just one package with full control

```bash
# Build a specific package version
fromager build click 8.1.7 https://pypi.org/simple/

# The wheel appears in wheels-repo/build/
ls wheels-repo/build/click-*
```

### 5. Advanced: Production Build Sequence

**Goal**: Use pre-determined build order for production

```bash
# First, generate build order
fromager bootstrap -r requirements.txt --sdist-only

# Then build in sequence (production)
fromager build-sequence \
  --wheel-server-url http://your-wheel-server/ \
  work-dir/build-order.json
```

### 6. Advanced: Parallel Building for Performance

**Goal**: Speed up builds using parallel processing

```bash
# Option 1: Bootstrap with automatic parallel building
fromager bootstrap-parallel -r requirements.txt -m 4

# Option 2: Separate phases for maximum control
# Phase 1: Discover dependencies (serial)
fromager bootstrap -r requirements.txt --sdist-only

# Phase 2: Build wheels in parallel
fromager build-parallel work-dir/graph.json -m 4
```

**Key benefits**:
- Much faster for large dependency trees
- Respects dependency order automatically
- Can limit workers to avoid resource exhaustion

### 7. Expert: Custom Settings and Patches

**Goal**: Handle packages that need patches or special build settings

```bash
# Create overrides directory structure
mkdir -p overrides/patches overrides/settings

# Example: Patch a package
cat > overrides/patches/problematic-package.patch << EOF
--- a/setup.py
+++ b/setup.py
@@ -10,7 +10,7 @@
     install_requires=[
-        'old-dependency',
+        'new-dependency',
     ],
EOF

# Package-specific settings
cat > overrides/settings/problematic-package.yaml << EOF
pre_built: false
patches:
  - problematic-package.patch
environment:
  CFLAGS: "-O2"
EOF

fromager bootstrap -r requirements.txt
```

## Directory Structure After Running Fromager

```
.
├── requirements.txt          # Your input requirements
├── constraints.txt          # Version constraints (optional)
├── overrides/              # Customization (advanced)
│   ├── patches/           # Source code patches
│   └── settings/          # Per-package build settings
├── sdists-repo/           # Source distributions
│   ├── downloads/         # Downloaded from PyPI/git
│   └── builds/           # Rebuilt with patches applied
├── wheels-repo/          # Built wheels
│   ├── downloads/        # Final wheels
│   ├── build/           # Intermediate builds
│   └── simple/          # PyPI-compatible index
└── work-dir/            # Temporary build files
    ├── build-order.json # Dependency build order
    ├── constraints.txt  # Generated constraints
    └── package-*/       # Build directories
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
$ echo "pydantic-core==2.18.4" > requirements.txt
$ fromager bootstrap -r requirements.txt
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
