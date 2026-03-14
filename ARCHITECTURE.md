# Fromager Architecture

## Table of Contents

- [Purpose](#purpose)
- [Core Components](#core-components)
- [Core Design Principles](#core-design-principles)
- [System Architecture](#system-architecture)
- [Source Code Acquisition](#source-code-acquisition)
- [Command Architecture](#command-architecture)
- [Data Flow](#data-flow)
- [File Organization](#file-organization)
- [Key Algorithms](#key-algorithms)
- [Extension Points](#extension-points)
- [Performance Optimizations](#performance-optimizations)
- [Testing Strategy](#testing-strategy)
- [Security Considerations](#security-considerations)
- [Future Extensibility](#future-extensibility)
- [Design Rationale](#design-rationale)
- [Related Documentation](#related-documentation)

---

## Purpose

Fromager rebuilds complete dependency trees of Python wheels from source, ensuring full reproducibility and transparency.

For terminology definitions, see [GLOSSARY.md](GLOSSARY.md).

---

## Core Components

Fromager's architecture centers around **five core components**:

### 1. WorkContext -- Central Coordination

The `WorkContext` (`context.py`) is the central state object that tracks progress and coordinates all activities:

- **State Management** -- Dependency graph, build progress, configuration
- **Resource Coordination** -- File paths, caches, shared resources
- **Build Orchestration** -- Determines build order and next steps
- **Cross-Component Communication** -- Shared context for all components

### 2. Bootstrapper -- Dependency Resolution Engine

The `Bootstrapper` (`bootstrapper.py`) handles recursive dependency discovery and build orchestration:

- **Dependency Walking** -- Recursively resolves build and install dependencies
- **Cycle Detection** -- Identifies and breaks circular dependencies
- **Build Ordering** -- Maintains topological sort of packages
- **Progress Tracking** -- Manages overall bootstrap workflow
- **Test Mode** -- With `--test-mode`, collects failures as `FailureRecord` TypedDicts instead of failing immediately

### 3. RequirementResolver -- Resolution Logic

The `RequirementResolver` (`requirement_resolver.py`) was extracted from the Bootstrapper for separation of concerns:

- **Resolution Orchestration** -- Coordinates resolution strategies (graph-based first, then PyPI fallback)
- **Session-Level Cache** -- Maintains a resolution cache across the session to avoid redundant lookups
- **Pre-built Wheel Handling** -- Determines whether a package uses a pre-built wheel or needs source building
- **Source Type Classification** -- Classifies requirements as `PREBUILT`, `SDIST`, `OVERRIDE`, or `GIT` via the `SourceType` enum
- **Key Methods** -- `resolve()`, `_resolve()` (internal dispatcher), `_resolve_from_graph()`, `_resolve_from_version_source()`

### 4. Resolver -- Version Selection Intelligence

The `Resolver` (`resolver.py`) determines which specific versions to use:

- **Version Negotiation** -- Selects versions satisfying all constraints
- **Provider Strategy** -- Pluggable providers (PyPI, GitHub, GitLab, etc.)
- **Constraint Satisfaction** -- Handles complex version requirement resolution
- **Caching** -- Optimizes repeated version lookups

### 5. BuildEnvironment -- Isolated Execution Space

The `BuildEnvironment` (`build_environment.py`) provides clean, reproducible build execution:

- **Isolation** -- Creates isolated virtual environments per build
- **Dependency Installation** -- Installs build dependencies using `uv`
- **Environment Management** -- Sets up PATH, environment variables, build tools
- **Cleanup** -- Manages lifecycle of temporary build environments

### Component Interaction Flow

```
WorkContext (orchestrates)
    |
    v
Bootstrapper (discovers dependencies)
    |
    v
RequirementResolver (resolves individual requirements)
    |
    v
Resolver (selects versions)
    |
    v
BuildEnvironment (executes builds)
    |
    v
WorkContext (updates state, determines next steps)
```

This flow ensures consistent state, correct resolution order, isolated builds, and trackable progress.

---

## Core Design Principles

### Source-First Philosophy

Every component in the final build is compiled from source:

- All binary packages are built from source in reproducible environments
- Dependencies are never downloaded as prebuilt binaries by default
- Build tools themselves are built from source for a transparent toolchain

### Pre-built Wheel Support

While fromager defaults to building from source, packages can use **pre-built wheels** when necessary:

- Configured via `variants[variant].pre_built` in the settings YAML
- Per-package `wheel_server_url` for alternative wheel indexes
- Functions `wheels.get_wheel_server_urls()` and `wheels.resolve_prebuilt_wheel()` handle fetching
- The `prebuilt_wheel` hook fires after a pre-built wheel is resolved

### Configurable with Sensible Defaults

The build process works automatically for most PEP-517 compliant packages, but every step can be customized:

- Default behavior handles standard Python packaging conventions
- Override system allows package-specific customization without modifying core code
- Hooks enable extending functionality at key lifecycle points

### Collection-Based Building

Packages are built as cohesive collections rather than in isolation:

- Dependencies are resolved together to ensure version compatibility
- ABI compatibility is maintained across packages built against each other
- Constraints enforce consistent versions across the collection

---

## System Architecture

### Core State Management

**WorkContext** (`context.py`)

Central state object initialized once at startup and passed to all operations. Contains:

- Active package settings and variants
- Repository paths (sdists, wheels, work directory)
- Dependency graph and constraints
- Build configuration and metrics collection

**DependencyGraph** (`dependency_graph.py`)

Directed graph tracking relationships between packages:

- Nodes represent package versions with metadata (download URL, version, prebuilt status)
- `DependencyNodeDict` includes a `pre_built: bool` field for pre-built wheel tracking
- Edges represent typed dependencies (install, build-system, build-backend, build-sdist, toplevel)
- Supports JSON serialization and both forward/reverse traversal

### Version Resolution System

**Resolver** (`resolver.py`)

Determines package versions based on:

- Provider pattern for different strategies (PyPI, GitHub, GitLab, generic)
- Requirement specifications and constraints
- Available sources and platform compatibility
- Caching to avoid redundant lookups

Key providers:

- `PyPIProvider` -- PEP 503 simple repository API
- `GitHubTagProvider` -- GitHub repository tags
- `GitLabTagProvider` -- GitLab repository tags
- `GenericProvider` -- Base for custom strategies

Uses the resolvelib library for complex constraint satisfaction.

### Build Orchestration

**Bootstrapper** (`bootstrapper.py`)

Coordinates the complete build process with **three explicit phases**:

1. **Pre-Resolution Phase** -- Resolves all top-level dependencies first, parses requirements, prepares constraints
2. **Bootstrap Phase** -- Recursive dependency walking, resolution, and building
3. **Finalization Phase** -- Writes dependency graph, build order, and (in test mode) failure report

Supports three modes:

- **Full build** -- Builds all packages from source
- **Sdist-only** -- Skips wheel building for non-build dependencies
- **Test mode** (`--test-mode`) -- Continues after failures, writes JSON failure report

Key data structures:

- `why` stack -- Tracks dependency chain for debugging
- `_seen_requirements` -- Prevents reprocessing and detects cycles
- `_build_stack` -- Maintains build order
- `SourceBuildResult` -- Dataclass capturing build outputs
- `FailureRecord` -- TypedDict recording failure details (test mode)

**RequirementResolver** (`requirement_resolver.py`)

Extracted from Bootstrapper for cleaner separation:

- `RequirementResolver` class coordinates resolution strategies (graph-based, then PyPI fallback)
- Maintains a session-level resolution cache
- Determines whether to use pre-built wheels or build from source
- Works with the `SourceType` enum from `requirements_file.py`

### Build Execution

**BuildEnvironment** (`build_environment.py`)

Isolated virtual environments for building:

- Each build gets a clean virtual environment
- Manages PATH and environment variables
- Uses uv for fast package installation
- Optional network isolation via Linux namespaces (unshare)

**Sources** (`sources.py`)

Source code acquisition:

- Downloads sdists from package indexes
- Clones git repositories with optional submodules
- Unpacks archives with security checks
- Applies patches and vendors Rust dependencies

**Finders** (`finders.py`)

Locates source and wheel files with multiple filename conventions, case-insensitive matching, and version normalization.

**Pyproject** (`pyproject.py`)

Automatic pyproject.toml manipulation -- creates missing files, updates build-system requirements, removes problematic dependencies, validates build backends.

**Wheels** (`wheels.py`)

Builds and processes wheel files:

- Builds wheels via PEP 517 build backends
- Adds extra metadata (ELF dependencies, build settings)
- Copies to local PEP 503 repository
- `get_wheel_server_urls()` -- Retrieves configured wheel server URLs
- `resolve_prebuilt_wheel()` -- Resolves and downloads pre-built wheels

**Server** (`server.py`)

Local HTTP wheel server for build-time dependency resolution. Serves PEP 503 simple repository, supports dynamic updates, thread-safe for parallel builds.

### Dependency Management

**Dependencies** (`dependencies.py`)

Extracts and manages requirement types:

- Build system requirements (from `[build-system] requires`)
- Build backend requirements (from PEP 517 hooks)
- Build sdist requirements
- Install requirements (from wheel metadata)

Extraction is cached to avoid redundant parsing and hook invocations.

### Package Metadata

**pkgmetadata/** package

Handles package metadata extraction and normalization:

- `pep639.py` -- License detection from metadata (PEP 639, SPDX mapping)
- `pep753.py` -- Project URL normalization (PEP 753)

### Customization System

**Overrides** (`overrides.py`)

Plugin system using stevedore (namespace: `fromager.project_overrides`):

- Module naming: package name with `-` replaced by `_`
- Methods override default implementations for any operation
- Flexible argument filtering for cross-version compatibility

Override methods: `get_build_system_dependencies`, `get_build_backend_dependencies`, `get_build_sdist_dependencies`, `get_install_dependencies_of_sdist`, `get_resolver_provider`, `download_source`, `resolve_source`, `prepare_source`, `expected_source_archive_name`, `build_sdist`, `build_wheel`, `add_extra_metadata_to_wheels`, `update_extra_environ`.

**Hooks** (`hooks.py`)

Event-driven extension points (namespace: `fromager.hooks`). Multiple plugins can handle the same hook.

Available hooks:

- `post_build` -- After a wheel is built
- `post_bootstrap` -- After the complete bootstrap process
- `prebuilt_wheel` -- After a pre-built wheel is resolved and downloaded

**PackageSettings** (`packagesettings.py`)

YAML-based per-package configuration:

- Per-package files: `settings-dir/{package_name}.yaml`
- Global settings file for defaults
- Variant-specific overrides (including `pre_built` flag and `wheel_server_url`)
- URL/filename templating, environment variables, patch management
- Validated using Pydantic models

### Constraints and Version Control

**Constraints** (`constraints.py`)

Manages version requirements across the collection -- global constraints, per-package constraints, prerelease control. Ensures ABI compatibility and prevents version conflicts.

### Supporting Modules

| Module | Purpose |
|--------|---------|
| `external_commands.py` | Subprocess execution with logging and network isolation support |
| `http_retry.py` | Exponential backoff for transient network failures |
| `request_session.py` | Centralized HTTP session with retry and auth (netrc) |
| `metrics.py` | Timing decorator and aggregation for performance monitoring |
| `progress.py` | Progress bar for bootstrap (optional) |
| `log.py` | Structured logging with context variables |
| `gitutils.py` | Git clone, submodules, shallow clones, URL sanitization |
| `tarballs.py` | Deterministic tarball creation for reproducibility |
| `vendor_rust.py` | Rust dependency vendoring via cargo vendor |

---

## Source Code Acquisition

Fromager fetches source from multiple origins. The primary components are `sources.py` (core logic), `resolver.py` (version resolution), `packagesettings.py` (configuration), and `overrides.py` (plugins).

Resolution priority: **Git URLs > Override plugins > Package settings > Custom indexes > PyPI** (default).

This supports enterprise environments, air-gapped deployments, and development workflows.

---

## Command Architecture

Commands are Click plugins loaded via stevedore (`fromager.cli` namespace).

**Primary Commands**

- `bootstrap` -- Full dependency resolution and building
  - `--test-mode` -- Continues after failures, writes JSON failure report
  - Includes pre-resolution phase for top-level dependencies
- `bootstrap-parallel` -- Parallelized bootstrap using thread pool
- `build` -- Build single package with dependencies from graph
- `build-sequence` -- Build packages from build-order.json
- `build-parallel` -- Parallelized production builds

**Analysis Commands**

- `build-order` -- Compute/display build order from graph
- `graph` -- Analyze and manipulate dependency graphs
- `stats` -- Display metrics from bootstrap run

**Utility Commands**

- `find-updates` -- Check for newer versions
- `minimize` -- Reduce dependency graph
- `canonicalize` -- Show canonical package name
- `list-overrides` -- Display available overrides
- `list-versions` -- Show available versions
- `lint` -- Validate requirements files
- `lint-requirements` -- Check requirements against graph
- `migrate-config` -- Update settings to new format
- `download-sequence` -- Download sources in build order
- `step` -- Execute single build step (debugging)
- `wheel-server` -- Run local wheel server

---

## Data Flow

### Bootstrap Process

```
User Requirements
    |
    v
Pre-Resolution Phase (resolve top-level deps, prepare constraints)
    |
    v
RequirementResolver (classify source type, check pre-built)
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
Finalization Phase (write graph, build order, failure report)
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
    +-> Source Download
    +-> Apply Patches/Overrides
    +-> Build Environment Setup
    +-> Install Build Dependencies (from cache)
    +-> Build Sdist
    +-> Build Wheel
    +-> Add Extra Metadata
    +-> Update Repository
    +-> Run Hooks
```

---

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
  __main__.py              # CLI entry point and Click setup
  context.py               # Core state management (WorkContext)
  dependency_graph.py      # Dependency tracking (nodes and edges)
  resolver.py              # Version resolution (PyPI, GitHub, GitLab providers)
  bootstrapper.py          # Build orchestration (recursive resolution)
  requirement_resolver.py  # Resolution logic (RequirementResolver class)
  build_environment.py     # Isolated build environments
  sources.py               # Source acquisition (download, unpack, patch)
  wheels.py                # Wheel building (PEP 517, metadata, ELF analysis)
  dependencies.py          # Dependency extraction (build-system, install, etc.)
  overrides.py             # Override plugin system (stevedore)
  hooks.py                 # Hook plugin system (post_build, post_bootstrap, prebuilt_wheel)
  packagesettings.py       # Configuration management (YAML, Pydantic)
  constraints.py           # Version constraints management
  requirements_file.py     # Requirements parsing, marker evaluation, SourceType enum
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
  versionmap.py            # Version mapping utilities
  threading_utils.py       # Thread synchronization helpers
  run_network_isolation.sh # Network isolation using Linux namespaces (unshare)

  pkgmetadata/             # Package metadata utilities
    __init__.py            # Package exports
    pep639.py              # License detection (PEP 639, SPDX mapping)
    pep753.py              # Project URL normalization (PEP 753)

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

---

## Key Algorithms

### Dependency Resolution

Depth-first recursive approach:

1. Start with top-level requirements
2. For each requirement:
   - Check if already processed (cycle detection)
   - Resolve version against constraints
   - Classify source type (`SourceType`: `PREBUILT`, `SDIST`, `OVERRIDE`, `GIT`)
   - Check caches (local, remote)
   - If not cached: download source, recursively resolve build deps, build sdist/wheel, resolve install deps
   - Add to dependency graph

### Build Order Computation

Topological sort of the dependency graph:

1. **Leaf nodes first** -- Packages with no build dependencies (e.g., `setuptools`, `wheel`)
2. **Process ready nodes** -- Packages whose build deps are all satisfied
3. **Break cycles** -- Break at runtime dependency edges (build-time cycles must be resolved)
4. **Respect constraints** -- All build-system, build-backend, build-sdist deps built first

Output preserved in `build-order.json` for reproducible production builds.

### Parallel Building

Correctness maintained via:

- Dependency graph determines parallelizable packages
- Thread-local build directories prevent conflicts
- Synchronization around shared resources
- Per-thread build environments

---

## Extension Points

### Override Methods

Package-specific behavior via stevedore plugins:

```python
# In a package at fromager.project_overrides entry point
def resolve_source(ctx, req, sdist_server_url, req_type):
    return url, version

def build_wheel(ctx, req, sdist_root_dir, version, build_env):
    return wheel_filename
```

### Hook Functions

Cross-cutting concerns that apply across packages. Unlike overrides (one per package), multiple hook plugins can participate in the same event.

Use cases: security scanning, artifact uploading, metrics collection, CI/CD integration, audit/compliance.

```python
# In a package at fromager.hooks entry point
def post_build(ctx, req, dist_name, dist_version, sdist_filename, wheel_filename):
    pass

def prebuilt_wheel(ctx, req, ...):
    pass
```

### Package Settings

Declarative YAML configuration for common customizations -- no Python required:

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
    pre_built: false
```

Benefits: version-control friendly, accessible to non-programmers, rapid iteration, build variant support.

---

## Performance Optimizations

### Caching Strategy

**Persistent Disk Caches:**

- **UV package cache** (`work_dir/uv-cache/`) -- Downloaded packages and metadata
- **Local wheel cache** (`wheels_repo/`) -- Built wheels by package/version
- **Remote wheel server** -- HTTP server for distributed builds
- **Source downloads** (`sdists_repo/downloads/`) -- Downloaded sdists and git repos

**In-Memory Caches:**

- **Resolver cache** (`BaseProvider.resolver_cache`) -- Version lookup results
- **Package build info cache** (`Settings._pbi_cache`) -- Computed settings
- **Dependency resolution cache** (`RequirementResolver._resolved_requirements`) -- Resolved versions

### Parallel Execution

Two strategies: `bootstrap-parallel` (during bootstrap) and `build-parallel` (production builds from build-order.json).

Thread safety via thread-local directories, locks on shared state, and immutable context objects.

### Network Efficiency

HTTP retries with exponential backoff for transient failures. Handles chunked encoding errors and connection issues.

---

## Testing Strategy

### Unit Tests (`tests/`)

Individual component testing: dependency graph, resolver, constraints, requirements parsing, configuration validation.

### End-to-End Tests (`e2e/`)

Complete workflow testing: bootstrap scenarios (constraints, extras, parallel, git URLs), build scenarios (settings, overrides, patches), edge cases (conflicts, prebuilt wheels, network isolation).

Each e2e test is a shell script exercising fromager commands and validating outputs.

---

## Security Considerations

### Build Isolation

Multiple layers:

- Virtual environments per build
- Network isolation via Linux namespaces (`unshare -rn`)
- `run_network_isolation.sh` script provides dedicated entry point for namespace-based isolation
- Loopback interface enabled for localhost communication
- Path validation against archive traversal attacks
- Environment variable sanitization against subshell injection

### Source Validation

- Archive extraction validates paths
- Git operations use explicit refs
- Downloads verify against expected filenames
- PEP 658 metadata reduces need to download packages

---

## Future Extensibility

The architecture supports:

- Additional resolver providers (custom registries, artifact stores)
- Alternative build backends beyond PEP 517
- More hook points for instrumentation
- Custom output formats beyond PEP 503
- Build caching system integration
- Signature verification for sources and wheels

---

## Design Rationale

### Why Plugin-Based Customization?

Allows handling package-specific quirks without forking. Overrides live in separate packages and are maintained independently.

### Why Both Overrides and Hooks?

- **Overrides** -- Package-specific behavior replacement
- **Hooks** -- Cross-cutting concerns across many/all packages

### Why Two Build Modes?

- **Bootstrap** -- Exploring new package sets, developing configurations
- **Production** -- Reproducible CI/CD builds with stable configurations

### Why Multiple Dependency Types?

PEP 517 defines multiple resolution phases (build system, build backend, install). Fromager tracks them separately for correct ordering and to handle circular dependencies between build and runtime requirements.

---

## Related Documentation

- [How to Read the Codebase](HOW_TO_READ_THE_CODE.md) -- Guide to understanding code structure
- [Debugging Guide](DEBUGGING_GUIDE.md) -- Techniques for debugging fromager
- [Contributing Guide](CONTRIBUTING_GUIDE.md) -- Path from user to contributor

---

## Updating This Document

1. Focus on design principles and core concepts, not implementation details
2. Update affected sections when adding major components
3. Keep descriptions concise but complete
4. Maintain separation between "what" (purpose) and "how" (implementation)
5. Cross-reference related sections
6. Update file organization when adding modules
7. Document new extension points
