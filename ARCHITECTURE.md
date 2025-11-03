# Fromager Architecture

## Purpose

Fromager is a tool for rebuilding complete dependency trees of Python wheels from source, ensuring full reproducibility and transparency in the build process.

## Glossary

Key terms used throughout fromager and this documentation:

**Package Distribution Formats**
- **sdist** (Source Distribution): Archive containing Python source code, typically `.tar.gz` or `.zip` format. Must be built to be installed.
- **[wheel](https://peps.python.org/pep-0427/)**: Pre-built binary distribution format (`.whl` file). Can be installed directly without compilation.
- **Built Distribution**: General term for packages ready to install (wheels are the standard built distribution format).

**Python Packaging Standards**
- **[PEP 517](https://peps.python.org/pep-0517/)**: Defines the interface for build backends and the `pyproject.toml` structure for specifying build requirements.
- **[PEP 518](https://peps.python.org/pep-0518/)**: Specifies the `pyproject.toml` file format for declaring build system requirements.
- **[PEP 503](https://peps.python.org/pep-0503/)**: Simple Repository API - defines the directory structure for package indexes (the `/simple/` layout).
- **[PEP 658](https://peps.python.org/pep-0658/)**: Metadata files for packages - allows package metadata to be available without downloading the full package.
- **[PEP 714](https://peps.python.org/pep-0714/)**: Rename of PEP 658 core metadata attribute.

**Package Naming**
- **Canonical name**: Normalized package name following Python packaging standards (`My-Package` → `my-package`). Lowercase with hyphens.
- **Override name**: Module-safe version of canonical name used for override plugins (`my-package` → `my_package`). When fromager creates override plugins using stevedore, these plugins are Python modules that need to be imported. Since Python cannot import a module named `scikit-learn.py` (hyphens are invalid in identifiers), fromager converts the distribution package name to a valid module name by replacing hyphens with underscores.
- **Distribution name**: The actual name as it appears in package files, may have different casing.

**Dependency Types**
- **Build-system dependencies**: Minimal tools required to understand how to build a package, specified in `[build-system] requires` in `pyproject.toml`. These are installed before any build backend hooks are called. Examples: `setuptools`, `hatchling`, `flit-core`.
- **Build-backend dependencies**: Additional dependencies discovered dynamically by calling the build backend's `get_requires_for_build_wheel()` hook. These are package-specific build requirements not known until the build system inspects the source. Examples: `cython` for packages with Cython extensions, `numpy` for packages that compile against NumPy headers.
- **Build-sdist dependencies**: Dependencies required specifically for creating source distributions, returned by the `get_requires_for_build_sdist()` hook. These may differ from wheel build dependencies and are needed before sdist creation.
- **Install dependencies** (Runtime dependencies): Packages needed when using the built package (from `Requires-Dist` in wheel metadata).
- **Top-level dependencies**: Requirements specified directly by the user, not discovered through dependency resolution.

**Build Process Terms**
- **Bootstrap**: The complete recursive process of building a package and all its dependencies from scratch.
- **Resolver**: Component that determines which version of a package to use based on requirements and constraints.
- **Provider**: Strategy class for version resolution (PyPI, GitHub, GitLab, custom registries).
- **Build environment**: Isolated Python virtual environment used for building a specific package.
- **Build order**: Topological sort of dependencies determining the sequence packages must be built in.
- **Build variant**: Different build configurations for the same package (e.g., `cpu` vs `gpu` for ML packages).

**Graph and Relationships**

Example dependency graph for building Flask:
```
flask==2.3.0 (toplevel)
├── build-system: setuptools, wheel
├── build-backend: (none)
├── install: werkzeug>=2.3.0, jinja2>=3.1.0, click>=8.0
│
werkzeug==2.3.7
├── build-system: setuptools, wheel
├── install: markupsafe>=2.1.1
│
jinja2==3.1.2
├── build-system: setuptools, wheel
├── install: markupsafe>=2.1.1
│
click==8.1.7
├── build-system: setuptools, wheel
├── install: (none)
│
markupsafe==2.1.3
├── build-system: setuptools, wheel
├── install: (none)
```

- **Dependency graph**: Directed graph tracking relationships between all packages in the build.
- **Dependency node**: Represents a specific version of a package in the graph.
- **Dependency edge**: Represents a typed dependency relationship between two packages.
- **Cycle**: Circular dependency where package A depends on B, B depends on C, and C depends on A.
- **Build-time cycle**: Problematic cycle where packages depend on each other during the build process.
- **Install-time cycle**: Acceptable cycle where packages depend on each other at runtime only.

**Customization System**
- **Override**: Package-specific custom implementation of a standard function (e.g., custom version resolution).
- **Hook**: Extension point that multiple plugins can handle for cross-cutting concerns (e.g., post-build actions).
- **Plugin**: External package providing overrides or hooks, registered via entry points.
- **Settings**: YAML-based configuration controlling package build behavior.
- **Patch**: File containing source code modifications applied before building.

**Package Repositories**
- **Package repository**: Directory structure serving packages following PEP 503 simple repository API.
- **Package index**: Server providing package metadata and downloads (e.g., PyPI).
- **Wheel server**: Local HTTP server providing built wheels during the build process.
- **Simple API**: The PEP 503 `/simple/` directory layout for package indexes.

**Version Control**
- **Constraint**: Version limitation applied to packages (e.g., `package<2.0`).
- **Requirement**: Package dependency specification with optional version constraints (e.g., `package>=1.0,<2.0`).
- **Specifier**: Version range specification in a requirement (the `>=1.0,<2.0` part).
- **Version resolution**: Process of selecting a specific version that satisfies all requirements and constraints.
- **Pre-release**: Development version (e.g., `1.0.0a1`, `1.0.0rc1`) not selected by default.

**Build Isolation**
- **Network isolation**: Running builds in a Linux namespace with no network access (using `unshare -rn`).
- **Build isolation**: Running each build in its own virtual environment to prevent interference.
- **Vendoring**: Including dependencies within a package's source code for offline builds.

**Caching**
- **Local cache**: Built wheels stored locally for reuse within a bootstrap run.
- **Remote cache**: Wheel server with previously built packages for distributed builds.
- **Resolver cache**: Cached results of version lookups to avoid redundant network requests.
- **UV cache**: Package cache used by the `uv` installer for fast dependency installation.

**Common Acronyms**
- **ABI**: Application Binary Interface - defines binary compatibility between compiled code.
- **ELF**: Executable and Linkable Format - binary format used on Linux, analyzed for shared library dependencies.
- **URL**: Uniform Resource Locator - web address for downloading packages or sources.
- **VCS**: Version Control System (git, mercurial, etc.).

## Core Design Principles

### Source-First Philosophy

Every component in the final build is compiled from source code:
- All binary packages are built from source in reproducible environments
- Dependencies are never downloaded as prebuilt binaries
- Build tools themselves are built from source to ensure a transparent toolchain

### Configurable with Sensible Defaults

The build process works automatically for most PEP-517 compliant packages, but every step can be customized:
- Default behavior handles standard Python packaging conventions
- Override system allows package-specific customization without modifying core code
- Hooks enable extending functionality at key lifecycle points

### Collection-Based Building

Packages are built as cohesive collections rather than in isolation:
- Dependencies are resolved together to ensure version compatibility
- ABI compatibility is maintained across packages built against each other
- Constraints can enforce consistent versions across the collection

## System Architecture

### Core State Management

**WorkContext** (`context.py`)

Central state object that flows through all operations, containing:
- Active package settings and variants
- Repository paths (sdists, wheels, work directory)
- Dependency graph
- Constraints and build configuration
- Metrics collection

The context is initialized once at startup and passed to all major operations.

**DependencyGraph** (`dependency_graph.py`)

Directed graph tracking relationships between packages:
- Nodes represent package versions with metadata (download URL, version, prebuilt status)
- Edges represent typed dependencies (install, build-system, build-backend, build-sdist, toplevel)
- Supports serialization to JSON for persistence and analysis
- Enables both forward traversal (dependencies) and reverse traversal (dependents)

### Version Resolution System

**Resolver** (`resolver.py`)

Determines which version of a package to use based on:
- Provider pattern for different resolution strategies (PyPI, GitHub, GitLab, generic)
- Requirement specifications and constraints
- Available sources (sdists vs wheels, platform compatibility)
- Caching to avoid redundant lookups

Key providers:
- `PyPIProvider`: Resolves from standard Python package indexes using PEP 503 simple repository API
- `GitHubTagProvider`: Resolves versions from GitHub repository tags
- `GitLabTagProvider`: Resolves versions from GitLab repository tags
- `GenericProvider`: Base for custom resolution strategies

The resolver uses resolvelib library to handle complex version constraint satisfaction.

### Build Orchestration

**Bootstrapper** (`bootstrapper.py`)

Coordinates the complete build process:
- Recursively resolves all dependencies
- Determines build order (topological sort of dependency graph)
- Manages caching strategies (local and remote)
- Tracks what has been seen to break dependency cycles
- Supports two modes:
  - Full build: Builds all packages from source
  - Sdist-only: Faster mode that skips wheel building for non-build dependencies

The bootstrapper maintains several key data structures:
- `why` stack: Tracks dependency chain for debugging and logging
- `_seen_requirements`: Prevents reprocessing and detects cycles
- `_resolved_requirements`: Caches version resolution results
- `_build_stack`: Maintains build order

### Build Execution

**BuildEnvironment** (`build_environment.py`)

Isolated Python virtual environments for building:
- Each build gets a clean virtual environment
- Manages PATH and environment variables for isolation
- Uses uv for fast package installation
- Optional network isolation using Linux namespaces (unshare)
- Cleans up after successful builds (configurable)

**Sources** (`sources.py`)

Handles acquiring source code:
- Downloads sdists from package indexes
- Clones git repositories with optional submodules
- Unpacks archives (tar.gz, zip) with security checks
- Applies patches from override directories
- Vendors Rust dependencies when needed

**Finders** (`finders.py`)

Locates source and wheel files:
- Handles multiple filename conventions for sdists
- Case-insensitive filename matching
- Version string normalization
- Supports non-standard naming patterns

**Pyproject** (`pyproject.py`)

Automatic pyproject.toml manipulation:
- Creates missing pyproject.toml files
- Updates build-system requirements
- Removes problematic requirements
- Validates build backend configuration
- Enables building legacy packages without pyproject.toml

**Wheels** (`wheels.py`)

Builds and processes wheel files:
- Builds wheels from prepared source using PEP 517 build backends
- Adds extra metadata (ELF dependencies, build settings)
- Analyzes ELF binaries for shared library dependencies
- Validates wheel structure
- Copies to local package repository in PEP 503 format

**Server** (`server.py`)

Local HTTP wheel server for build-time dependency resolution:
- Runs threaded HTTP server serving wheels repository
- Updates PEP 503 simple repository structure dynamically
- Symlinks wheels into per-package directories
- Auto-discovers available port if not specified
- Thread-safe updates to mirror during parallel builds
- Supports external wheel server for distributed builds

### Dependency Management

**Dependencies** (`dependencies.py`)

Extracts and manages different types of requirements:
- Build system requirements (from `pyproject.toml` `[build-system] requires`)
- Build backend requirements (from PEP 517 hooks)
- Build sdist requirements (for creating source distributions)
- Install requirements (from wheel metadata)

Requirement extraction is cached to avoid redundant pyproject.toml parsing and hook invocations.

### Customization System

**Overrides** (`overrides.py`)

Plugin system for package-specific behavior using stevedore:
- Namespace: `fromager.project_overrides`
- Module naming: Package name converted to override module name (`-` becomes `_`)
- Methods can override default implementations for any operation
- Flexible argument filtering ensures compatibility across versions

Override methods available:
- `get_build_system_dependencies`
- `get_build_backend_dependencies`
- `get_build_sdist_dependencies`
- `resolver_provider`
- `download_source`
- `resolve_source`
- `build_sdist`
- `build_wheel`
- `add_extra_metadata_to_wheels`

**Hooks** (`hooks.py`)

Event-driven extension points for cross-cutting concerns:
- Namespace: `fromager.hooks`
- Multiple plugins can handle the same hook
- Available hooks:
  - `post_build`: After wheel is built
  - `post_bootstrap`: After complete bootstrap process

**PackageSettings** (`packagesettings.py`)

YAML-based configuration per package and variant:
- Per-package settings files: `settings-dir/{package_name}.yaml`
- Global settings file for defaults
- Variant-specific overrides
- Supports templating in URLs and filenames
- Environment variables for builds
- Patch management
- Pre-built wheel configuration

Settings are validated using Pydantic models with comprehensive validation rules.

### Constraints and Version Control

**Constraints** (`constraints.py`)

Manages version requirements across the collection:
- Global constraints from constraints file
- Per-package constraints from settings
- Validates that requested versions satisfy constraints
- Supports prerelease control

Constraints ensure ABI compatibility and prevent version conflicts in the final collection.

### Supporting Modules

**External Commands** (`external_commands.py`)

Subprocess execution wrapper:
- Captures and logs command output
- Supports network isolation wrapper
- Custom environment variable handling
- Detailed logging of executed commands
- Error handling with full output preservation

**HTTP Retry** (`http_retry.py`)

Resilient network operations:
- Exponential backoff for transient failures
- Configurable retry attempts and delays
- Handles chunked encoding errors, incomplete reads, protocol errors
- Decorator-based retry logic

**Request Session** (`request_session.py`)

Centralized HTTP session management:
- Configures retry strategy for all HTTP requests
- Custom adapter for connection pooling
- Authentication support via netrc
- Used by resolver and source downloaders

**Metrics** (`metrics.py`)

Performance monitoring:
- Timing decorator for operations
- Aggregates timing data per package
- Helps identify bottlenecks
- Used for reporting in stats command

**Progress** (`progress.py`)

User feedback during long operations:
- Progress bar for bootstrap process
- Tracks completed vs remaining packages
- Shows current operation
- Optional - can be disabled

**Logging** (`log.py`)

Structured logging support:
- Custom log record factory
- Context variables for per-requirement logging
- Multiple log levels and formats
- File and console handlers

**Git Utilities** (`gitutils.py`)

Git repository operations:
- Clone repositories with specific tags or refs
- Support for git submodules (all or selective)
- Shallow clones for efficiency
- URL sanitization for logging (removes credentials)

**Tarballs** (`tarballs.py`)

Reproducible tarball creation:
- Deterministic tar file creation (fixed timestamps, ownership, permissions)
- VCS directory exclusion
- Used for creating sdists with vendored dependencies

**Vendor Rust** (`vendor_rust.py`)

Rust dependency vendoring for network-isolated builds:
- Detects maturin and setuptools-rust projects
- Runs cargo vendor to download dependencies
- Shrinks vendor bundle by removing unused platform-specific files
- Configures cargo to use vendored sources
- Enables fully offline Rust builds

## Command Architecture

Commands are organized as Click command plugins using stevedore entry points (`fromager.cli` namespace). Each command is self-contained with its own options and help text.

**Primary Commands**

- `bootstrap`: Full dependency resolution and building from requirements
- `bootstrap-parallel`: Parallelized bootstrap using thread pool
- `build`: Build single package with dependencies from graph
- `build-sequence`: Build packages in order from build-order.json
- `build-parallel`: Parallelized production builds

**Analysis Commands**

- `build-order`: Compute and display build order from graph
- `graph`: Analyze and manipulate dependency graphs
- `stats`: Display metrics from bootstrap run

**Utility Commands**

- `find-updates`: Check for newer versions of packages
- `minimize`: Reduce dependency graph to essential packages
- `canonicalize`: Show canonical form of package name
- `list-overrides`: Display available package overrides
- `list-versions`: Show available versions of a package
- `lint`: Validate requirements files
- `lint-requirements`: Check requirements against graph
- `migrate-config`: Update settings files to new format
- `download-sequence`: Download sources in build order
- `step`: Execute single build step for debugging
- `wheel-server`: Run local wheel server for testing

## Data Flow

### Bootstrap Process

```
User Requirements
    |
    v
Resolver (version selection)
    |
    v
Source Download/Clone
    |
    v
Build System Dependencies ----> Recursive Bootstrap
    |
    v
Build Backend Dependencies ---> Recursive Bootstrap
    |
    v
Build Sdist Dependencies -----> Recursive Bootstrap
    |
    v
Build Sdist + Wheel
    |
    v
Install Dependencies ---------> Recursive Bootstrap
    |
    v
Update Dependency Graph
    |
    v
Update Build Order
```

### Build Process (from graph)

```
Dependency Graph
    |
    v
Build Order Computation
    |
    v
For each package in order:
    |
    +-> Source Download
    |
    +-> Apply Patches/Overrides
    |
    +-> Build Environment Setup
    |
    +-> Install Build Dependencies (from cache)
    |
    +-> Build Sdist
    |
    +-> Build Wheel
    |
    +-> Add Extra Metadata
    |
    +-> Update Repository
    |
    +-> Run Hooks
```

## File Organization

### Repository Structure

```
sdists-repo/
  downloads/       # Downloaded source distributions
  builds/          # Built source distributions (with patches)

wheels-repo/
  downloads/       # Downloaded prebuilt wheels
  prebuilt/        # Configured prebuilt wheels
  build/           # Temporary build output
  simple/          # PEP 503 package repository

work-dir/
  logs/            # Build and error logs
  graph.json       # Dependency graph
  build-order.json # Sequential build order
  constraints.txt  # Generated constraints (optional)
  uv-cache/        # uv package cache

overrides/
  patches/         # Package-specific patches
  settings/        # Package-specific YAML settings
  settings.yaml    # Global settings
```

### Source Code Structure

```
src/fromager/
  __main__.py              # CLI entry point and Click command setup
  context.py               # Core state management (WorkContext)
  dependency_graph.py      # Dependency tracking (nodes and edges)
  resolver.py              # Version resolution (PyPI, GitHub, GitLab providers)
  bootstrapper.py          # Build orchestration (recursive dependency resolution)
  build_environment.py     # Isolated build environments (virtualenv management)
  sources.py               # Source acquisition (download, unpack, patch)
  wheels.py                # Wheel building (PEP 517, metadata, ELF analysis)
  dependencies.py          # Dependency extraction (build-system, build-backend, install)
  overrides.py             # Override plugin system (stevedore integration)
  hooks.py                 # Hook plugin system (post_build, post_bootstrap)
  packagesettings.py       # Configuration management (YAML, Pydantic models)
  constraints.py           # Version constraints management
  requirements_file.py     # Requirements parsing and marker evaluation
  external_commands.py     # System command execution with logging
  server.py                # Local HTTP wheel server (PEP 503)
  finders.py               # File discovery (sdists and wheels)
  pyproject.py             # pyproject.toml manipulation
  gitutils.py              # Git operations (clone, submodules)
  tarballs.py              # Reproducible tarball creation
  vendor_rust.py           # Rust dependency vendoring (cargo vendor)
  http_retry.py            # HTTP retry logic with backoff
  request_session.py       # Centralized HTTP session
  metrics.py               # Performance monitoring
  progress.py              # Progress bar display
  log.py                   # Structured logging
  candidate.py             # Package candidate representation
  clickext.py              # Click extensions and utilities
  extras_provider.py       # Package extras handling for resolver
  read.py                  # File and URL reading utilities
  version.py               # Version information (generated)
  versionmap.py            # Version mapping utilities
  threading_utils.py       # Thread synchronization helpers
  
  commands/                # CLI command implementations
    __init__.py            # Command registration
    bootstrap.py           # Bootstrap command
    build.py               # Build commands (build, build-sequence, build-parallel)
    build_order.py         # Build order computation
    canonicalize.py        # Name canonicalization
    download_sequence.py   # Download in build order
    find_updates.py        # Check for package updates
    graph.py               # Graph analysis and manipulation
    lint.py                # Linting commands
    lint_requirements.py   # Requirements validation
    list_overrides.py      # List available overrides
    list_versions.py       # List package versions
    migrate_config.py      # Configuration migration
    minimize.py            # Graph minimization
    server.py              # Wheel server command
    stats.py               # Statistics display
    step.py                # Single step execution
```

## Key Algorithms

### Dependency Resolution

Fromager uses a depth-first recursive approach:

1. Start with top-level requirements
2. For each requirement:
   - Check if already processed (cycle detection)
   - Resolve version against constraints
   - Check caches (local, remote)
   - If not cached:
     - Download and prepare source
     - Recursively resolve build dependencies
     - Build sdist and wheel
     - Recursively resolve install dependencies
   - Add to dependency graph

This ensures all packages are built in correct order with their dependencies available.

### Build Order Computation

Build order is a topological sort of the dependency graph:

1. Start from nodes with no dependencies
2. Process nodes whose dependencies are all built
3. Handle cycles by breaking them at runtime dependency edges
4. Build requirements must be built before packages that need them

The order is preserved in `build-order.json` for reproducible production builds.

### Parallel Building

Parallel execution maintains correctness by:

1. Using dependency graph to determine which packages can be built in parallel
2. Thread-local build directories to prevent conflicts
3. Synchronization around shared resources (repository updates)
4. Build environment per thread

## Extension Points

### Override Methods

Package-specific behavior can be customized by implementing override methods:

```python
# In a package at fromager.project_overrides entry point
def resolve_source(ctx, req, sdist_server_url, req_type):
    # Custom version resolution logic
    return url, version

def build_wheel(ctx, req, sdist_root_dir, version, build_env):
    # Custom wheel building logic
    return wheel_filename
```

### Hook Functions

Cross-cutting concerns handled via hooks:

```python
# In a package at fromager.hooks entry point
def post_build(ctx, req, dist_name, dist_version, sdist_filename, wheel_filename):
    # Executed after every wheel is built
    pass
```

### Package Settings

YAML configuration provides declarative customization:

```yaml
# settings/torch.yaml
download_source:
  url: "https://example.com/${canonicalized_name}-${version}.tar.gz"
env:
  USE_CUDA: "0"
variants:
  gpu:
    env:
      USE_CUDA: "1"
```

## Performance Optimizations

### Caching Strategy

Multi-level caching reduces redundant work:
- UV package cache for fast dependency installation
- Local wheel cache for built packages
- Remote wheel server for distributed builds
- Resolver cache for version lookups
- Dependency extraction cache

### Parallel Execution

Two parallelization strategies:
- `bootstrap-parallel`: Multiple packages in parallel during bootstrap
- `build-parallel`: Parallel production builds from build-order.json

Thread safety maintained through:
- Thread-local build directories
- Locks on shared state updates
- Immutable context objects where possible

### Network Efficiency

HTTP retries with exponential backoff for transient failures:
- Configurable retry attempts and delays
- Handles chunked encoding errors, connection errors
- Smart retry only on retryable exceptions

## Testing Strategy

### Unit Tests (`tests/`)

Test individual components in isolation:
- Dependency graph operations
- Resolver logic
- Constraints handling
- Requirements file parsing
- Configuration validation

### End-to-End Tests (`e2e/`)

Test complete workflows:
- Bootstrap scenarios (with constraints, extras, parallel, git URLs)
- Build scenarios (settings, overrides, patches)
- Edge cases (conflicts, prebuilt wheels, network isolation)

Each e2e test is a shell script that exercises fromager commands and validates outputs.

## Security Considerations

### Build Isolation

Multiple layers of isolation:
- Virtual environments for each build
- Network isolation using Linux namespaces (unshare -rn) to prevent unauthorized network access during builds
- Loopback interface enabled for localhost communication
- Path validation to prevent archive traversal attacks
- Environment variable sanitization to prevent subshell injection

### Source Validation

Safety checks during source handling:
- Archive extraction validates paths
- Git operations use explicit refs
- Downloads verify against expected filenames
- PEP 658 metadata support reduces need to download packages

## Future Extensibility

The architecture supports future enhancements:

- Additional resolver providers (custom registries, artifact stores)
- Alternative build backends beyond PEP 517
- More hook points for instrumentation
- Custom output formats beyond PEP 503 repositories
- Integration with build caching systems
- Signature verification for sources and wheels

## Design Rationale

### Why Plugin-Based Customization?

Allows users to handle package-specific quirks without forking fromager or submitting patches upstream. Overrides live in separate packages and can be maintained independently.

### Why Both Overrides and Hooks?

- Overrides: Package-specific behavior replacement
- Hooks: Cross-cutting concerns that apply to many/all packages

This separation keeps concerns organized and makes the system more maintainable.

### Why Two Build Modes?

- Bootstrap: For exploring new package sets, developing build configurations
- Production: For reproducible builds in CI/CD with stable configurations

The separation allows optimization of each use case.

### Why Multiple Dependency Types?

PEP 517 defines multiple phases of dependency resolution:
- Build system: Minimal dependencies to introspect build
- Build backend: Additional dependencies from build backend hooks
- Install: Runtime dependencies

Fromager tracks these separately to build in the correct order and handle circular dependencies between build and runtime requirements.

## Related Documentation

For contributors who want to dive deeper:
- [How to Read the Codebase](HOW_TO_READ_THE_CODE.md) - Guide to understanding the code structure with examples
- [Debugging Guide](DEBUGGING_GUIDE.md) - Techniques and tools for debugging fromager issues
- [Contributing Guide](CONTRIBUTING_GUIDE.md) - Path from user to contributor

## Updating This Document

When updating this architecture document:

1. Focus on design principles and core concepts, not implementation details
2. Update affected sections when adding new major components
3. Keep descriptions concise but complete
4. Maintain the separation between "what" (purpose) and "how" (implementation)
5. Cross-reference between related sections where helpful for understanding
6. Update the file organization section when adding new modules
7. Document new extension points when adding plugin capabilities

