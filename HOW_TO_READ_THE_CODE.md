# How to Read the Fromager Codebase

This guide helps you understand the fromager codebase structure and navigate it effectively.

## Prerequisites

Before diving into the code, you should have:

- **Completed the [README examples](README.md)** - Understand how to use fromager
- **Read the [Architecture Guide](ARCHITECTURE.md)** - Understand the system design and core concepts, especially the [Core Components](ARCHITECTURE.md#core-components) section

This guide focuses on **how to navigate and read the actual code** with practical examples and techniques. For hands-on contribution guidance, see the [Contributing Guide](CONTRIBUTING_GUIDE.md).

## Quick Start: Your First Hour

### 1. Start with the Bootstrap Flow (30 minutes)

Open `src/fromager/bootstrapper.py` and read these methods in order:

1. `Bootstrapper.__init__()`: See what state the bootstrapper maintains - note the `self._resolver` (a `RequirementResolver` instance) that handles version resolution
2. `Bootstrapper.bootstrap()`: The main entry point - trace through this carefully
3. `RequirementResolver.resolve()` in `requirement_resolver.py`: Understand how versions are chosen (extracted from Bootstrapper) - it coordinates graph-based resolution, then falls back to PyPI
4. `Bootstrapper._download_source()`: See source acquisition
5. `Bootstrapper._build_from_source()`: See how source is built
6. `Bootstrapper._handle_build_requirements()`: Understand recursive dependency handling

**Exercise**: Pick a simple package you know (like `click`) and trace mentally how it would flow through these methods.

### 2. Follow a Simple Command (15 minutes)

Open `src/fromager/commands/canonicalize.py` - the simplest command:

```python
@click.command()
@click.argument("dist_name", nargs=-1)
def canonicalize(dist_name: list[str]) -> None:
    """convert a package name to its canonical form for use in override paths"""
    for name in dist_name:
        print(overrides.pkgname_to_override_module(name))
```

Notice:
- This command is so simple it doesn't even need a `WorkContext`
- Commands are just Click commands with entry points
- More complex commands use `@click.pass_obj` to receive the `WorkContext` (see `bootstrap` or `build`)

### 3. Understand State Management (15 minutes)

Open `src/fromager/context.py` and examine:

1. `WorkContext.__init__()`: All the state that flows through the system
2. `WorkContext.setup()`: How directories are initialized
3. `WorkContext.package_build_info()`: How per-package settings are accessed

The WorkContext is passed to almost every function - it's your window into the entire build state.

## The Five Core Components

Fromager's architecture centers around **five core components** that work in harmony to orchestrate the build process. Understanding these components and their interactions is key to navigating the codebase effectively.

### Component Overview

```
User Command
    |
    v
Click Command (commands/*.py)
    |
    v
┌─────────────────────────────────────────────────────────────┐
│                    WorkContext                              │
│                 (Central Coordination)                      │
│  • Tracks all state and configuration                      │
│  • Coordinates between other components                     │
│  • Manages file paths, caches, and resources              │
└─────────────────┬───────────────────────────────────────────┘
                  │
    ┌─────────────┼──────────────────────────┐
    │             │             │             │
    v             v             v             v
┌──────────────┐ ┌───────────────────┐ ┌─────────┐ ┌─────────────┐
│Bootstrapper  │ │RequirementResolver│ │Resolver │ │BuildEnvironment│
│(Orchestration)│ │(Resolution Logic) │ │(Version │ │(Isolation)     │
│• Dependency  │ │• Graph-based      │ │Selection)│ │• Virtual envs  │
│  discovery   │ │  resolution       │ │• Constraint│ │• Dependency    │
│• Build order │ │• PyPI fallback    │ │  satisfaction│ │  installation  │
│• Recursion   │ │• Session cache    │ │• Provider  │ │• Command       │
│  management  │ │• Source type      │ │  strategies│ │  execution     │
└──────────────┘ │  classification   │ └─────────┘ └─────────────┘
                 └───────────────────┘
```

### 1. WorkContext - Central Coordination

**File**: `src/fromager/context.py`

**Purpose**: Acts as the "central nervous system" that tracks all state and coordinates activities between components.

**Key Responsibilities**:
- **State Management**: Maintains dependency graph, build progress, and configuration
- **Resource Coordination**: Manages file paths, caches, and shared resources
- **Build Orchestration**: Determines what needs to be built next and in what order
- **Cross-Component Communication**: Provides shared context for all other components

**Created**: Once at startup in `__main__.py:main()`

**Key Attributes**:
```python
class WorkContext:
    def __init__(self, ...):
        self.settings = active_settings                     # Configuration system
        self.constraints = constraints.Constraints()        # Version constraints
        self.dependency_graph = dependency_graph.DependencyGraph()  # Relationship tracking
        self.sdists_repo = pathlib.Path(sdists_repo)       # Source repository
        self.wheels_repo = pathlib.Path(wheels_repo)       # Wheel repository
        self.work_dir = pathlib.Path(work_dir)             # Working directory
```

**Key Methods**:
- `setup()`: Creates all required directories
- `package_build_info()`: Gets configuration for a specific package
- `clean_build_dirs()`: Cleanup after build
- `pip_wheel_server_args` (property): Arguments for pip to use local server

### 2. Bootstrapper - Dependency Resolution Engine

**File**: `src/fromager/bootstrapper.py`

**Purpose**: Handles recursive dependency discovery and build orchestration - the "brain" that figures out what to build and in what order. Version resolution is delegated to `RequirementResolver` (see `src/fromager/requirement_resolver.py`).

**Key Responsibilities**:
- **Dependency Walking**: Recursively resolves build and install dependencies
- **Cycle Detection**: Identifies and breaks circular dependencies
- **Build Ordering**: Maintains topological sort of packages to build
- **Progress Tracking**: Manages the overall bootstrap workflow
- **Test Mode**: Optional `test_mode` parameter enables dry-run reporting via `finalize()`

**Created**: In `commands/bootstrap.py:bootstrap()`

**Key State**:
```python
class Bootstrapper:
    def __init__(self, ctx: context.WorkContext, ..., test_mode: bool = False):
        self.ctx = ctx
        self._resolver = RequirementResolver(...)                          # Delegates resolution
        self.why: list[tuple[RequirementType, Requirement, Version]] = []  # Dependency chain
        self._build_stack: list[typing.Any] = []                           # Build order
        self._seen_requirements: set[SeenKey] = set()                      # Cycle prevention
```

**Key Methods**:
- `bootstrap(req, req_type)`: Main entry point for recursive building
- `resolve_and_add_top_level()`: Pre-resolution phase for top-level requirements
- `_bootstrap_impl()`: Core implementation method called by `bootstrap()`
- `_download_source()`: Acquires source code
- `_build_from_source()`: Builds source into sdist/wheel
- `_handle_build_requirements()`: Processes build dependencies recursively
- `finalize()`: Test mode reporting (when `test_mode=True`)

**Related Data Structures**: `SourceBuildResult` (dataclass) and `FailureRecord` (TypedDict) support build result tracking and test mode failure reporting.

### 3. RequirementResolver - Resolution Logic

**File**: `src/fromager/requirement_resolver.py`

**Purpose**: Extracted from the Bootstrapper for separation of concerns, this component coordinates resolution strategies -- trying graph-based resolution first, then falling back to PyPI.

**Key Responsibilities**:
- **Resolution Orchestration**: Coordinates resolution strategies (graph-based first, then PyPI fallback)
- **Session-Level Cache**: Maintains a `_resolved_requirements` cache to avoid redundant lookups
- **Pre-built Wheel Handling**: Determines whether a package uses a pre-built wheel or needs source building
- **Source Type Classification**: Classifies requirements as `PREBUILT`, `SDIST`, `OVERRIDE`, or `GIT` via the `SourceType` enum (from `requirements_file.py`)

**Created**: In `Bootstrapper.__init__()`

**Key Methods**:
- `resolve()`: Main entry point -- checks cache, then delegates to `_resolve()`
- `_resolve()`: Internal dispatcher -- tries graph-based resolution, then version source fallback
- `_resolve_from_graph()`: Checks the previous dependency graph for a cached version
- `_resolve_from_version_source()`: Falls through to standard resolution via `sources.resolve_source()`
- `get_cached_resolution()`: Retrieves a previously resolved version from session cache
- `cache_resolution()`: Stores a resolved version in the session cache

### 4. Resolver - Version Selection Intelligence

**File**: `src/fromager/resolver.py`

**Purpose**: Determines which specific versions to use for each package based on requirements, constraints, and availability.

**Key Responsibilities**:
- **Version Negotiation**: Selects versions that satisfy all constraints
- **Provider Strategy**: Uses pluggable providers (PyPI, GitHub, GitLab, etc.)
- **Constraint Satisfaction**: Handles complex version requirement resolution
- **Caching**: Optimizes repeated version lookups

**Key Functions**:
- `resolve()`: Main entry point for version resolution
- `resolve_from_provider()`: Uses resolvelib for constraint solving

**Provider Classes**:
- `PyPIProvider`: Resolves from package indexes using PEP 503
- `GitHubTagProvider`: Resolves from GitHub repository tags
- `GitLabTagProvider`: Resolves from GitLab repository tags

### 5. BuildEnvironment - Isolated Execution Space

**File**: `src/fromager/build_environment.py`

**Purpose**: Provides clean, reproducible build execution environments - the "sandbox" where packages are actually built.

**Key Responsibilities**:
- **Isolation**: Creates isolated Python virtual environments for each build
- **Dependency Installation**: Installs build dependencies using `uv`
- **Environment Management**: Sets up PATH, environment variables, and build tools
- **Cleanup**: Manages lifecycle of temporary build environments

**Key Methods**:
```python
class BuildEnvironment:
    def __init__(self, ctx: context.WorkContext, parent_dir: pathlib.Path):
        # Creates isolated venv at parent_dir/build-{python_version}

    def install(self, reqs: typing.Iterable[Requirement]) -> None:
        # Installs dependencies using uv pip install

    def run(self, cmd: typing.Sequence[str], ...) -> str:
        # Executes commands in the isolated environment

    def get_venv_environ(self, ...) -> dict[str, str]:
        # Sets up environment variables for isolation
```

### Component Interaction Flow

The five components work together in a coordinated cycle:

```
1. WorkContext orchestrates the overall process
   ↓
2. Bootstrapper discovers what needs to be built
   ↓
3. RequirementResolver coordinates version resolution
   (graph-based first, then PyPI fallback)
   ↓
4. Resolver selects the best version from providers (PyPI, GitHub, GitLab)
   ↓
5. BuildEnvironment executes the actual builds
   ↓
6. WorkContext updates state and determines next steps
   ↓
   (cycle repeats for dependencies)
```

This **harmonious interaction** ensures that:
- **State is consistent** across all build operations
- **Dependencies are resolved** in the correct order
- **Builds are isolated** and reproducible
- **Progress is tracked** and recoverable

## Core Classes and Their Relationships

### WorkContext: The Central State Object

**File**: `src/fromager/context.py`

**Purpose**: Carries all state through the build process - configuration, paths, graphs, caches.

**Created**: Once at startup in `__main__.py:main()`

**Key Attributes**:
```python
class WorkContext:
    def __init__(
        self,
        active_settings: packagesettings.Settings | None,  # Configuration
        constraints_file: str | None,                       # Version constraints
        patches_dir: pathlib.Path,                          # Patch location
        sdists_repo: pathlib.Path,                          # Source distributions
        wheels_repo: pathlib.Path,                          # Wheel repository
        work_dir: pathlib.Path,                             # Working files
        # ... more parameters
    ):
        self.settings = active_settings
        self.constraints = constraints.Constraints()
        self.sdists_repo = pathlib.Path(sdists_repo)
        self.wheels_repo = pathlib.Path(wheels_repo)
        self.dependency_graph = dependency_graph.DependencyGraph()
```

**Key Methods**:
- `setup()`: Creates all required directories
- `package_build_info()`: Gets configuration for a specific package
- `clean_build_dirs()`: Cleanup after build
- `pip_wheel_server_args` (property): Arguments for pip to use local server

**Used By**: Every major operation - passed as first parameter conventionally named `ctx`

**Example Usage**:
```python
# From sources.py
def download_source(
    *,
    ctx: context.WorkContext,  # Always passed
    req: Requirement,
    version: Version,
    download_url: str,
) -> pathlib.Path:
    # The ctx parameter provides access to all shared state:
    #   ctx.package_build_info(req)  -- per-package settings
    #   ctx.sdists_downloads         -- download directory
    #   ctx.work_dir                 -- working directory
    ...
```

### Bootstrapper: The Orchestrator

**File**: `src/fromager/bootstrapper.py`

**Purpose**: Coordinates the complete recursive build process from requirements to wheels. Version resolution has been extracted into `RequirementResolver` (see below).

**Created**: In `commands/bootstrap.py:bootstrap()`

**Key State**:
```python
class Bootstrapper:
    def __init__(
        self,
        ctx: context.WorkContext,
        progressbar: progress.Progressbar | None = None,
        prev_graph: DependencyGraph | None = None,
        cache_wheel_server_url: str | None = None,
        sdist_only: bool = False,
        test_mode: bool = False,
    ):
        self.ctx = ctx
        self._resolver = RequirementResolver(...)                          # Delegates resolution
        self.why: list[tuple[RequirementType, Requirement, Version]] = []
        self._build_stack: list[typing.Any] = []
        self._seen_requirements: set[SeenKey] = set()
```

**Key Methods**:

1. **`bootstrap(req, req_type)`**: Main entry point
   ```python
   def bootstrap(self, req: Requirement, req_type: RequirementType) -> None:
       # Resolve version (delegated to RequirementResolver)
       source_url, resolved_version = self.resolve_version(req=req, req_type=req_type)

       # Add to graph
       self._add_to_graph(req, req_type, resolved_version, source_url)

       # Check if already seen
       if self._mark_as_seen(...):
           return

       # Delegate to core implementation
       self._bootstrap_impl(req, req_type, resolved_version, source_url)
   ```

2. **`resolve_and_add_top_level()`**: Pre-resolution phase for top-level requirements before the main bootstrap loop.

3. **`_bootstrap_impl()`**: Core implementation method
   - Called by `bootstrap()` after resolution and cycle-checking
   - Downloads source, handles build and install dependencies, builds sdist/wheel
   - Contains the main build orchestration logic

4. **`finalize()`**: When `test_mode=True`, produces a report of test mode results and failures.

5. **`_download_source()`**: Source acquisition
   - Resolves source location
   - Downloads or clones source code
   - Returns path to downloaded source

6. **`_build_from_source()`**: Source building
   - Unpacks and applies patches
   - Builds sdist and wheel
   - Returns build result

7. **`_handle_build_requirements()`**: Recursive build dependency processing
   - Gets build-system dependencies
   - Gets build-backend dependencies
   - Gets build-sdist dependencies
   - Recursively bootstraps each one

**State Tracking**:
- `why` stack: Tracks "why are we building this" for debugging
- `_seen_requirements`: Prevents infinite recursion and duplicate work
- `_build_stack`: Maintains build order

**Example Flow**:
```
bootstrap(requests)
  |
  +-> resolve_version(requests) -> requests==2.31.0
  |
  +-> _bootstrap_impl(requests, 2.31.0)
  |     |
  |     +-> _download_source(requests, 2.31.0)
  |     |     +-> sources.resolve_source() -> URL
  |     |     +-> sources.download_source() -> tar.gz file
  |     |
  |     +-> _handle_build_requirements(requests)
  |     |     +-> dependencies.get_build_system_dependencies()
  |     |     +-> bootstrap(setuptools) [recursive!]
  |     |     +-> bootstrap(wheel) [recursive!]
  |     |
  |     +-> _build_from_source(requests, 2.31.0)
  |     |     +-> build sdist and wheel
  |     |
  |     +-> handle install dependencies (inline in _bootstrap_impl)
  |           +-> self._get_install_dependencies()
        +-> bootstrap(urllib3) [recursive!]
        +-> bootstrap(charset-normalizer) [recursive!]
        +-> ...
```

### DependencyGraph: Relationship Tracker

**File**: `src/fromager/dependency_graph.py`

**Purpose**: Maintains a directed graph of package dependencies with typed edges.

**Created**: In `WorkContext.__init__()`

**Key Components**:

1. **`DependencyNode`**: Represents a package version
   ```python
   @dataclasses.dataclass(frozen=True, order=True, slots=True)
   class DependencyNode:
       canonicalized_name: NormalizedName
       version: Version
       download_url: str = ""
       pre_built: bool = False
       constraint: Requirement | None = None

       # Computed fields
       key: str                        # "package==version"
       parents: list[DependencyEdge]   # Who depends on this
       children: list[DependencyEdge]  # What this depends on
   ```

2. **`DependencyEdge`**: Represents a dependency relationship
   ```python
   @dataclasses.dataclass(frozen=True, order=True, slots=True)
   class DependencyEdge:
       destination_node: DependencyNode
       req: Requirement            # The requirement that created this edge
       req_type: RequirementType   # install, build-system, build-backend, etc.
   ```

3. **`DependencyGraph`**: The graph itself
   ```python
   class DependencyGraph:
       def __init__(self):
           self.nodes: dict[str, DependencyNode] = {}  # key -> node
           self.clear()  # Creates ROOT node
   ```

**Key Methods**:

- `add_dependency()`: Add a package and its relationship to parent
- `get_install_dependencies()`: Get all runtime dependencies
- `get_dependency_edges()`: Traverse with filtering
- `serialize()`: Save to JSON
- `from_file()`: Load from JSON

**Example Usage**:
```python
# From bootstrapper.py
def _add_to_graph(self, req, req_type, resolved_version, source_url):
    # Get parent info
    parent_name, parent_version = self._get_parent_info()

    # Add to graph
    self.ctx.dependency_graph.add_dependency(
        parent_name=parent_name,
        parent_version=parent_version,
        req_type=req_type,
        req=req,
        req_version=resolved_version,
        download_url=source_url,
        pre_built=is_prebuilt,
        constraint=constraint,
    )
```

**Graph Structure**:
```
ROOT
  |
  +--[toplevel]--> requests==2.31.0
                      |
                      +--[build-system]--> setuptools==68.0.0
                      +--[build-system]--> wheel==0.41.0
                      +--[install]-------> urllib3==2.0.4
                      +--[install]-------> charset-normalizer==3.2.0
```

### Resolver: Version Selection

**File**: `src/fromager/resolver.py`

**Purpose**: Determines which version of a package to use based on requirements and constraints.

**Key Functions**:

1. **`resolve()`**: Main entry point
   ```python
   def resolve(
       *,
       ctx: context.WorkContext,
       req: Requirement,
       sdist_server_url: str,
       include_sdists: bool = True,
       include_wheels: bool = True,
       req_type: RequirementType | None = None,
       ignore_platform: bool = False,
   ) -> tuple[str, Version]:
       # Get appropriate provider
       provider = overrides.find_and_invoke(
           req.name,
           "get_resolver_provider",
           default_resolver_provider,
           ...
       )
       return resolve_from_provider(provider, req)
   ```

2. **`resolve_from_provider()`**: Uses resolvelib
   ```python
   def resolve_from_provider(provider: BaseProvider, req: Requirement):
       reporter = LogReporter(req)
       rslvr = resolvelib.Resolver(provider, reporter)
       result = rslvr.resolve([req])
       # Returns (url, version) tuple
   ```

**Provider Classes**:

1. **`PyPIProvider`**: Resolves from package indexes
   - Fetches package index HTML (PEP 503)
   - Parses available versions
   - Filters by Python version, platform, yanked status
   - Respects constraints
   - Caches results

2. **`GitHubTagProvider`**: Resolves from GitHub tags
   - Fetches tags via GitHub API
   - Matches version patterns
   - Returns tarball URLs

3. **`GitLabTagProvider`**: Resolves from GitLab tags
   - Similar to GitHub but uses GitLab API

**Example Flow**:
```python
# User has: requests>=2.28.0
# Constraints: requests<2.32

resolve(req=Requirement("requests>=2.28.0"))
  |
  +-> PyPIProvider.find_matches("requests")
  |     +-> Fetch https://pypi.org/simple/requests/
  |     +-> Parse available versions: 2.28.0, 2.28.1, 2.29.0, 2.31.0, 2.32.0, ...
  |     +-> Filter by req.specifier: >=2.28.0 -> keeps 2.28.0+
  |     +-> Filter by constraints: <2.32 -> removes 2.32.0+
  |     +-> Sort descending: [2.31.0, 2.29.0, 2.28.1, 2.28.0]
  |     +-> Return candidates
  |
  +-> resolvelib picks highest: 2.31.0
  |
  +-> Return (url_to_2.31.0, Version("2.31.0"))
```

### BuildEnvironment: Isolated Builds

**File**: `src/fromager/build_environment.py`

**Purpose**: Manages isolated Python virtual environments for building packages.

**Created**: Fresh for each package build

**Key Methods**:

1. **`__init__()`**: Creates virtualenv
   ```python
   class BuildEnvironment:
       def __init__(self, ctx: context.WorkContext, parent_dir: pathlib.Path):
           self.path = parent_dir / f"build-{platform.python_version()}"
           self._createenv()
   ```

2. **`install()`**: Install dependencies using uv
   ```python
   def install(
       self,
       reqs: typing.Iterable[Requirement],
   ) -> None:
       # Build uv pip install command
       cmd = ["uv", "pip", "install"]
       cmd.extend(self._ctx.pip_constraint_args)    # Apply constraints
       cmd.extend(self._ctx.pip_wheel_server_args)  # Use local server
       cmd.extend(str(req) for req in reqs)

       # Run in virtualenv
       self.run(cmd, ...)
   ```

3. **`run()`**: Execute command in environment
   ```python
   def run(
       self,
       cmd: typing.Sequence[str],
       *,
       cwd: str | None = None,
       extra_environ: dict[str, str] | None = None,
       network_isolation: bool | None = None,
       log_filename: str | None = None,
   ) -> str:
       # Merge venv environ with extra
       extra_environ = self.get_venv_environ(extra_environ)

       # Run with isolation
       return external_commands.run(
           cmd,
           cwd=cwd,
           extra_environ=extra_environ,
           network_isolation=network_isolation,
           ...
       )
   ```

4. **`get_venv_environ()`**: Prepare environment
   ```python
   def get_venv_environ(self, template_env: dict | None) -> dict[str, str]:
       venv_environ = {
           "VIRTUAL_ENV": str(self.path),
           "PATH": f"{self.path / 'bin'}:{existing_path}",
           "UV_CACHE_DIR": str(self._ctx.uv_cache),
           # ... more uv configuration
       }
       return venv_environ
   ```

**Lifecycle**:
```
Build Package X
  |
  +-> BuildEnvironment(work-dir/X/build-3.12)
  |     +-> Create virtualenv
  |
  +-> Install build-system deps
  |     +-> build_env.install([setuptools, wheel])
  |     |     +-> uv pip install --index-url http://localhost:8000/simple/
  |
  +-> Install build-backend deps
  |     +-> build_env.install([additional deps])
  |
  +-> Build sdist
  |     +-> build_env.run([python, -m, build, --sdist])
  |
  +-> Build wheel
  |     +-> build_env.run([python, -m, build, --wheel])
  |
  +-> Cleanup (if configured)
        +-> Delete virtualenv
```

### Dependencies: Requirement Extraction

**File**: `src/fromager/dependencies.py`

**Purpose**: Extracts different types of dependencies from packages.

**Key Functions**:

1. **`get_build_system_dependencies()`**: PEP 517 build-system requirements
   ```python
   def get_build_system_dependencies(
       *,
       ctx: context.WorkContext,
       req: Requirement,
       sdist_root_dir: pathlib.Path,
   ) -> set[Requirement]:
       # Check cache
       build_system_req_file = sdist_root_dir.parent / "build-system-requirements.txt"
       if build_system_req_file.exists():
           return _read_requirements_file(build_system_req_file)

       # Get from pyproject.toml or override
       orig_deps = overrides.find_and_invoke(
           req.name,
           "get_build_system_dependencies",
           default_get_build_system_dependencies,
           ...
       )

       # Filter by markers and cache
       deps = _filter_requirements(req, orig_deps)
       _write_requirements_file(deps, build_system_req_file)
       return deps
   ```

2. **`get_build_backend_dependencies()`**: From PEP 517 hooks
   - Calls `get_requires_for_build_wheel()` hook
   - Caches to `build-backend-requirements.txt`

3. **`get_build_sdist_dependencies()`**: For building sdist
   - Calls `get_requires_for_build_sdist()` hook
   - Caches to `build-sdist-requirements.txt`

4. **`get_install_dependencies_of_wheel()`**: Runtime deps from wheel
   ```python
   def get_install_dependencies_of_wheel(
       req: Requirement,
       wheel_filename: pathlib.Path,
   ) -> set[Requirement]:
       # Extract METADATA from wheel
       with zipfile.ZipFile(wheel_filename) as zf:
           metadata_content = zf.read(metadata_path)

       # Parse with packaging.metadata
       metadata = Metadata.from_email(metadata_content)

       # Return Requires-Dist
       return set(Requirement(r) for r in metadata.requires_dist or [])
   ```

**Caching Strategy**:
- First call: Invoke hooks/parse metadata, write to cache file
- Subsequent calls: Read from cache file
- Cache files live next to sdist_root_dir

### Sources: Source Acquisition

**File**: `src/fromager/sources.py`

**Purpose**: Downloads, unpacks, and prepares source code for building.

**Key Functions**:

1. **`resolve_source()`**: Find source location
   ```python
   def resolve_source(
       *,
       ctx: context.WorkContext,
       req: Requirement,
       sdist_server_url: str,
       req_type: RequirementType | None = None,
   ) -> tuple[str, Version]:
       # Allow overrides
       resolver_results = overrides.find_and_invoke(
           req.name,
           "resolve_source",
           default_resolve_source,
           ...
       )
       url, version = resolver_results
       return str(url), version
   ```

2. **`download_source()`**: Download the source
   ```python
   def download_source(
       *,
       ctx: context.WorkContext,
       req: Requirement,
       version: Version,
       download_url: str,
   ) -> pathlib.Path:
       # Handle git URLs specially
       if req.url:
           return download_git_source(...)

       # Allow overrides
       source_path = overrides.find_and_invoke(
           req.name,
           "download_source",
           default_download_source,
           ...
       )
       return source_path
   ```

3. **`unpack_source()`**: Extract archive
   ```python
   def unpack_source(
       req: Requirement,
       source_filename: pathlib.Path,
       sdist_root_dir: pathlib.Path,
   ) -> pathlib.Path:
       # Handle .tar.gz, .zip, etc.
       if tarfile.is_tarfile(source_filename):
           with tarfile.open(source_filename) as tf:
               tf.extractall(sdist_root_dir, filter='data')
       elif zipfile.is_zipfile(source_filename):
           with zipfile.ZipFile(source_filename) as zf:
               zf.extractall(sdist_root_dir)

       # Find the actual source directory inside
       return _find_source_dir_in_unpacked_sdist(...)
   ```

4. **`prepare_source()`**: Apply patches and prepare
   ```python
   def prepare_source(
       ctx: context.WorkContext,
       req: Requirement,
       source_root_dir: pathlib.Path,
   ) -> pathlib.Path:
       # Apply patches from overrides/patches/
       _apply_patches(ctx, req, source_root_dir)

       # Vendor Rust dependencies if needed
       if needs_vendoring:
           vendor_rust.vendor(...)

       return source_root_dir
   ```

### Wheels: Wheel Building

**File**: `src/fromager/wheels.py`

**Purpose**: Builds wheels from source, adds metadata, and supports pre-built wheel resolution.

**Key Functions** (in addition to `get_wheel_server_urls()` and `resolve_prebuilt_wheel()` for pre-built wheel support):

1. **`build_wheel()`**: Main wheel building
   ```python
   def build_wheel(
       ctx: context.WorkContext,
       req: Requirement,
       sdist_root_dir: pathlib.Path,
       version: Version,
       build_env: build_environment.BuildEnvironment,
   ) -> pathlib.Path:
       # Allow overrides
       wheel_filename = overrides.find_and_invoke(
           req.name,
           "build_wheel",
           default_build_wheel,
           ...
       )

       # Add extra metadata
       wheel_filename = add_extra_metadata_to_wheels(...)

       return wheel_filename
   ```

2. **`default_build_wheel()`**: Standard PEP 517 build
   ```python
   def default_build_wheel(...) -> pathlib.Path:
       # Prepare environment
       extra_environ = packagesettings.get_extra_environ(...)

       # Build using python -m build
       cmd = [
           build_env.python,
           "-m", "build",
           "--wheel",
           "--outdir", str(ctx.wheels_build),
           str(build_dir),
       ]

       # Run with isolation
       build_env.run(
           cmd,
           extra_environ=extra_environ,
           network_isolation=ctx.network_isolation,
           ...
       )

       # Find built wheel
       return finders.find_wheel(ctx.wheels_build, req, version)
   ```

3. **`add_extra_metadata_to_wheels()`**: Add fromager metadata
   ```python
   def add_extra_metadata_to_wheels(...) -> pathlib.Path:
       # Unzip wheel
       with zipfile.ZipFile(wheel_file) as zf:
           zf.extractall(wheel_root_dir)

       # Analyze ELF dependencies
       elfinfos = _extra_metadata_elfdeps(...)

       # Add fromager-build-settings
       build_settings = {...}
       with open(dist_info_dir / "fromager-build-settings", "w") as f:
           json.dump(build_settings, f)

       # Rezip wheel
       with zipfile.ZipFile(new_wheel, "w") as zf:
           add_files_to_wheel(...)

       return new_wheel
   ```

## Real Code Examples

### Example 1: How a Command Executes (bootstrap)

**Entry Point**: `src/fromager/commands/bootstrap.py`

```python
@click.command()
@click.option("-r", "--requirements-file", "requirements_files", multiple=True, ...)
@click.argument("toplevel", nargs=-1)
@click.pass_obj
def bootstrap(
    wkctx: context.WorkContext,  # Injected by Click
    requirements_files: typing.Iterable[str],
    toplevel: typing.Iterable[str],
    # ... many more options
) -> None:
    # Parse input requirements
    to_build = _get_requirements_from_args(toplevel, requirements_files)

    # Create bootstrapper
    bs = bootstrapper.Bootstrapper(
        ctx=wkctx,
        progressbar=pbar,
        prev_graph=prev_graph,
        cache_wheel_server_url=cache_wheel_server_url,
        sdist_only=sdist_only,
        test_mode=test_mode,  # Optional: enables dry-run reporting
    )

    # Start server
    server.start_wheel_server(wkctx)

    # Bootstrap each requirement
    for req in to_build:
        bs.bootstrap(
            req,
            RequirementType.TOP_LEVEL,
        )
```

**What Happens Next**: Flows into `Bootstrapper.bootstrap()` in `bootstrapper.py`

### Example 2: Version Resolution with Constraints

Version resolution has been extracted from `Bootstrapper` into `RequirementResolver` (in `src/fromager/requirement_resolver.py`). The Bootstrapper delegates to `self._resolver.resolve()`.

**Start**: `src/fromager/requirement_resolver.py`

```python
class RequirementResolver:
    def resolve(
        self,
        req: Requirement,
        req_type: RequirementType,
    ) -> tuple[str, Version]:
        # Try graph-based resolution first
        result = self._resolve_from_graph(req, req_type)
        if result:
            return result

        # Fall back to version source (PyPI, etc.)
        return self._resolve_from_version_source(req, req_type)
```

The `_resolve_from_graph()` method checks the previous dependency graph for a cached version. The `_resolve_from_version_source()` method falls through to the standard resolution path.

**Flows to**: `src/fromager/sources.py` `resolve_source()`

```python
def resolve_source(
    *,
    ctx: context.WorkContext,
    req: Requirement,
    sdist_server_url: str,
    req_type: RequirementType | None = None,
) -> tuple[str, Version]:
    # Get constraint
    constraint = ctx.constraints.get_constraint(req.name)

    # Allow override
    resolver_results = overrides.find_and_invoke(
        req.name,
        "resolve_source",
        default_resolve_source,  # Usually this one
        ctx=ctx,
        req=req,
        sdist_server_url=sdist_server_url,
        req_type=req_type,
    )

    url, version = resolver_results
    return str(url), version
```

**Flows to**: `src/fromager/sources.py` `default_resolve_source()`

```python
def default_resolve_source(
    ctx: context.WorkContext,
    req: Requirement,
    sdist_server_url: str,
    req_type: RequirementType | None = None,
) -> tuple[str, Version]:
    pbi = ctx.package_build_info(req)

    # Get resolver settings
    override_sdist_server_url = pbi.resolver_sdist_server_url(sdist_server_url)

    # Call resolver
    url, version = resolver.resolve(
        ctx=ctx,
        req=req,
        sdist_server_url=override_sdist_server_url,
        include_sdists=pbi.resolver_include_sdists,
        include_wheels=pbi.resolver_include_wheels,
        req_type=req_type,
        ignore_platform=pbi.resolver_ignore_platform,
    )
    return url, version
```

**Flows to**: `src/fromager/resolver.py` `resolve()`

```python
def resolve(
    *,
    ctx: context.WorkContext,
    req: Requirement,
    sdist_server_url: str,
    include_sdists: bool = True,
    include_wheels: bool = True,
    req_type: RequirementType | None = None,
    ignore_platform: bool = False,
) -> tuple[str, Version]:
    # Get provider
    provider = overrides.find_and_invoke(
        req.name,
        "get_resolver_provider",
        default_resolver_provider,  # Usually PyPIProvider
        ctx=ctx,
        req=req,
        ...
    )

    # Resolve
    return resolve_from_provider(provider, req)
```

**Flows to**: `src/fromager/resolver.py` `resolve_from_provider()`

```python
def resolve_from_provider(provider: BaseProvider, req: Requirement):
    reporter = LogReporter(req)
    rslvr = resolvelib.Resolver(provider, reporter)  # External library

    # This calls provider.find_matches() to get candidates
    result = rslvr.resolve([req])

    # Extract result
    for candidate in result.mapping.values():
        return candidate.url, candidate.version
```

**Provider's find_matches**: `src/fromager/resolver.py` `BaseProvider.find_matches()`

`PyPIProvider` inherits `find_matches()` from `BaseProvider`, which handles caching, filtering, and sorting:

```python
def find_matches(
    self,
    identifier: str,
    requirements: RequirementsMap,
    incompatibilities: CandidatesMap,
) -> Candidates:
    # Get candidates (cached internally via _find_cached_candidates)
    unfiltered_candidates = self._find_cached_candidates(identifier)

    # Filter by requirements and constraints
    candidates = [
        candidate
        for candidate in unfiltered_candidates
        if self.validate_candidate(
            identifier, requirements, incompatibilities, candidate
        )
    ]

    # Return sorted by version descending
    return sorted(candidates, key=attrgetter("version", "build_tag"), reverse=True)
```

### Example 3: Override System in Action

**Setup**: Package has override plugin registered in `pyproject.toml`:

```toml
[project.entry-points."fromager.project_overrides"]
torch = "package_plugins.torch"
```

**Override Module**: `package_plugins/torch.py`

```python
def resolve_source(ctx, req, sdist_server_url, req_type):
    # Custom logic for torch - use GitHub releases
    return "https://github.com/pytorch/pytorch/releases/...", Version("2.0.0")
```

**How It's Called**: `src/fromager/sources.py`

```python
# In resolve_source()
resolver_results = overrides.find_and_invoke(
    req.name,  # "torch"
    "resolve_source",  # method name
    default_resolve_source,  # fallback
    ctx=ctx,
    req=req,
    sdist_server_url=sdist_server_url,
    req_type=req_type,
)
```

**Override Lookup**: `src/fromager/overrides.py`

```python
def find_and_invoke(
    distname: str,
    method: str,
    default_fn: typing.Callable,
    **kwargs: typing.Any,
) -> typing.Any:
    # Look for override
    fn = find_override_method(distname, method)
    if not fn:
        fn = default_fn  # Use default if no override

    # Invoke it
    result = invoke(fn, **kwargs)

    # Log
    if fn is default_fn:
        logger.debug(f"{distname}: override method {fn.__name__} returned {result}")
    else:
        logger.info(f"{distname}: override method {fn.__name__} returned {result}")

    return result
```

**Finding Override**: `src/fromager/overrides.py`

```python
def find_override_method(distname: str, method: str) -> typing.Callable | None:
    # Convert name
    distname = pkgname_to_override_module(distname)  # torch -> torch

    # Load module via stevedore
    try:
        mod = _get_extensions()[distname].plugin
    except KeyError:
        return None  # No override module

    # Check if method exists
    if not hasattr(mod, method):
        return None  # Module exists but not this method

    # Return the function
    return getattr(mod, method)
```

### Example 4: Package Settings Loading

**Settings File**: `overrides/settings/torch.yaml`

```yaml
download_source:
  url: "https://github.com/pytorch/pytorch/releases/download/v${version}/pytorch-v${version}.tar.gz"
env:
  USE_CUDA: "0"
  BUILD_TEST: "0"
variants:
  gpu:
    env:
      USE_CUDA: "1"
```

**Loading**: `src/fromager/packagesettings.py` `Settings.from_files()`

```python
@classmethod
def from_files(
    cls,
    settings_file: pathlib.Path,
    settings_dir: pathlib.Path,
    patches_dir: pathlib.Path,
    variant: str,
    max_jobs: int | None,
) -> Settings:
    # Load global settings
    settings = SettingsFile.from_file(settings_file) if settings_file.exists() else SettingsFile()

    # Load per-package settings
    package_settings: list[PackageSettings] = []
    if settings_dir.exists():
        for yaml_file in sorted(settings_dir.glob("*.yaml")):
            pkg_settings = PackageSettings.from_yaml(yaml_file)
            package_settings.append(pkg_settings)

    # Create Settings object
    return cls(
        settings=settings,
        package_settings=package_settings,
        patches_dir=patches_dir,
        variant=variant,
        max_jobs=max_jobs,
    )
```

**Accessing**: `src/fromager/context.py`

```python
def package_build_info(
    self, package: str | packagesettings.Package | Requirement
) -> packagesettings.PackageBuildInfo:
    if isinstance(package, Requirement):
        name = package.name
    else:
        name = package

    # Delegates to settings
    return self.settings.package_build_info(name)
```

**Using in Code**: Anywhere in codebase

```python
# Get settings for current package
pbi = ctx.package_build_info(req)

# Access specific settings
if pbi.pre_built:
    # Use prebuilt wheel
    ...

download_url = pbi.download_source_url(version=version)
extra_env = pbi.get_extra_environ(build_env=build_env, version=version)
```

**PackageBuildInfo**: `src/fromager/packagesettings.py`

```python
class PackageBuildInfo:
    def __init__(self, settings: Settings, ps: PackageSettings) -> None:
        self._variant = settings.variant
        self._patches_dir = settings.patches_dir
        self._max_jobs = settings.max_jobs
        self._ps = ps                            # Per-package settings (from YAML)

    @property
    def pre_built(self) -> bool:
        """Does the variant use pre-built wheels?"""
        vi = self._ps.variants.get(self.variant)
        if vi is not None:
            return vi.pre_built
        return False

    def get_extra_environ(self, ...) -> dict[str, str]:
        # Sets MAKEFLAGS, CMAKE_BUILD_PARALLEL_LEVEL, MAX_JOBS
        # Merges package env + variant env with template variable resolution
        # Handles VIRTUAL_ENV and PATH from build environment
        ...
```

## Command to Code Mapping

| User Command | Entry Point | Key Functions Called | Output |
|-------------|-------------|---------------------|---------|
| `fromager bootstrap requests` | `commands/bootstrap.py:bootstrap()` | `Bootstrapper.bootstrap()` -> recursive dependency resolution | `wheels-repo/simple/`, `work-dir/graph.json`, `work-dir/build-order.json` |
| `fromager build requests 2.31.0` | `commands/build.py:build()` | `build_one()` -> `build_sdist()` + `build_wheel()` | Single sdist + wheel |
| `fromager build-sequence` | `commands/build.py:build_sequence()` | Reads `build-order.json`, calls `build_one()` for each | All wheels in order |
| `fromager graph why requests` | `commands/graph.py:graph()` -> `find_why()` | `DependencyGraph.get_nodes_by_name()` | Dependency chain explanation |
| `fromager list-overrides` | `commands/list_overrides.py:list_overrides()` | `overrides._get_extensions()` | List of available override modules |
| `fromager canonicalize My-Package` | `commands/canonicalize.py:canonicalize()` | `overrides.pkgname_to_override_module()` | `my_package` |
| `fromager stats` | `commands/stats.py:stats()` | `metrics.format_time_stats()` | Timing breakdown per package |

## Module Dependency Map

Understanding which modules depend on which helps navigate the code:

```
High Level (Commands)
  commands/*.py
    |
    v
Mid Level (Orchestration)
  bootstrapper.py
  requirement_resolver.py
  context.py
    |
    v
Core Operations
  resolver.py
  sources.py
  wheels.py
  dependencies.py
  build_environment.py
  pkgmetadata/           (PEP 639 license detection, PEP 753 URL normalization)
    |
    v
Customization
  overrides.py
  hooks.py               (post_build, post_bootstrap, prebuilt_wheel)
  packagesettings.py
    |
    v
Data Structures
  dependency_graph.py
  constraints.py
  requirements_file.py   (includes SourceType enum: PREBUILT, SDIST, OVERRIDE, GIT)
    |
    v
Utilities
  external_commands.py
  run_network_isolation.sh
  finders.py
  http_retry.py
  gitutils.py
  etc.
```

**Import Rules**:
- Commands can import anything
- Orchestration imports operations and customization
- Operations import utilities and customization
- Utilities should not import operations or orchestration

## Where to Start for Common Tasks

### Adding Support for a New Package Source

1. **Create new provider class** in `resolver.py`
   - Inherit from `GenericProvider`
   - Implement `_find_tags()` method
   - Add caching

2. **Create override** in external package
   - Implement `get_resolver_provider()` returning your provider
   - Register in `pyproject.toml`

3. **Test** with `fromager bootstrap mypackage`

**Example**: See `GitLabTagProvider` in `resolver.py` as template

### Adding a New Build Step

1. **Add method** to `Bootstrapper` class in `bootstrapper.py`
2. **Call it** from `bootstrap()` method at appropriate point
3. **Add to step command** in `commands/step.py`

### Adding a New Package Setting

1. **Define Pydantic model** in `packagesettings.py`
   - Add to `PerPackage` or `PerVariant` class
   - Add validation if needed

2. **Expose in PackageBuildInfo**
   - Add property with fallback logic

3. **Use in code**
   ```python
   pbi = ctx.package_build_info(req)
   if pbi.your_new_setting:
       # Do something
   ```

4. **Document** in `docs/config-reference.rst`

### Adding a New Hook Point

Existing hooks include `post_build`, `post_bootstrap`, and `prebuilt_wheel` (see `hooks.py`).

1. **Define hook signature** in appropriate module
2. **Add hook invocation** using `hooks.py`
   ```python
   hook_mgr = hooks._get_hooks("your_hook_name")
   for ext in hook_mgr:
       ext.plugin(ctx=ctx, ...)
   ```

3. **Document** in `docs/hooks.rst`

### Adding a New Command

1. **Create file** `src/fromager/commands/mycommand.py`
   ```python
   import click
   from .. import context

   @click.command()
   @click.pass_obj
   def mycommand(wkctx: context.WorkContext) -> None:
       # Your logic
       pass
   ```

2. **Register** in `pyproject.toml`
   ```toml
   [project.entry-points."fromager.cli"]
   mycommand = "fromager.commands.mycommand:mycommand"
   ```

3. **Import** in `commands/__init__.py`
   ```python
   from .mycommand import mycommand
   commands.append(mycommand)
   ```

4. **Test** with `fromager mycommand`

## Testing Your Changes

Testing is crucial for contributing to fromager. The project has multiple test layers to ensure changes work correctly.

### Running the Test Suite

**Run all unit tests**:
```bash
hatch run test:test
```

**Run specific test file**:
```bash
hatch run test:test tests/test_resolver.py
```

**Run specific test function**:
```bash
hatch run test:test tests/test_resolver.py::test_resolve_from_pypi
```

**Run with verbose output**:
```bash
hatch run test:test -vv tests/test_resolver.py
```

**Run with coverage report**:
```bash
hatch run test:test tests/
hatch run test:coverage-report
```

### Writing Unit Tests

Unit tests live in the `tests/` directory and test individual components in isolation.

**Basic test structure**:
```python
# tests/test_mymodule.py
import pytest
from fromager import mymodule

def test_my_function():
    """Test that my_function returns expected value."""
    result = mymodule.my_function(input_value)
    assert result == expected_value

def test_my_function_with_error():
    """Test that my_function raises error on invalid input."""
    with pytest.raises(ValueError, match="expected error message"):
        mymodule.my_function(invalid_input)
```

**Testing with fixtures**:
```python
import pytest
from fromager import context, packagesettings

@pytest.fixture
def work_context(tmp_path):
    """Create a WorkContext for testing."""
    return context.WorkContext(
        active_settings=None,
        constraints_file=None,
        patches_dir=tmp_path / "patches",
        sdists_repo=tmp_path / "sdists",
        wheels_repo=tmp_path / "wheels",
        work_dir=tmp_path / "work",
        cleanup=True,
        variant="cpu",
    )

def test_with_context(work_context):
    """Test using the work_context fixture."""
    assert work_context.variant == "cpu"
    assert work_context.work_dir.name == "work"
```

**Example: Testing a new resolver provider**:
```python
# tests/test_resolver.py
from packaging.requirements import Requirement
from packaging.version import Version
from fromager import resolver
from fromager.constraints import Constraints

def test_custom_provider():
    """Test custom provider resolves correct version."""
    # Create provider
    provider = resolver.MyCustomProvider(
        constraints=Constraints(),
        req_type=None,
    )

    # Create requirement
    req = Requirement("mypackage>=1.0")

    # Resolve
    url, version = resolver.resolve_from_provider(provider, req)

    # Assert
    assert isinstance(version, Version)
    assert version >= Version("1.0")
    assert "mypackage" in url
```

**Example: Testing with mocks**:
```python
from unittest.mock import Mock, patch
from fromager import sources

def test_download_source_with_override(tmp_path):
    """Test that download_source calls override when available."""
    # Create mock context
    mock_ctx = Mock()
    mock_ctx.sdists_downloads = tmp_path

    # Mock the override system
    with patch('fromager.overrides.find_and_invoke') as mock_override:
        mock_override.return_value = tmp_path / "mypackage-1.0.tar.gz"

        # Call function
        result = sources.download_source(
            ctx=mock_ctx,
            req=Requirement("mypackage"),
            version=Version("1.0"),
            download_url="https://example.com/mypackage-1.0.tar.gz",
        )

        # Verify override was called
        mock_override.assert_called_once()
        assert result == tmp_path / "mypackage-1.0.tar.gz"
```

### Integration Testing

Integration tests verify that components work together correctly.

**Create a minimal integration test**:
```bash
#!/bin/bash
# Create test script
cat > test_integration.sh << 'EOF'
#!/bin/bash
set -e

# Setup
rm -rf test-work-dir wheels-repo sdists-repo
mkdir -p overrides/settings

# Test: Bootstrap a simple package
fromager \
  --work-dir=test-work-dir \
  --wheels-repo=wheels-repo \
  --sdists-repo=sdists-repo \
  bootstrap click

# Verify wheel was created
test -f wheels-repo/simple/click/click-*.whl
echo "✓ Integration test passed"

# Cleanup
rm -rf test-work-dir wheels-repo sdists-repo
EOF

chmod +x test_integration.sh
./test_integration.sh
```

**Test with custom settings**:
```bash
# Create settings file
mkdir -p overrides/settings
cat > overrides/settings/mypackage.yaml << 'EOF'
env:
  CUSTOM_VAR: "test_value"
EOF

# Run test
fromager \
  --settings-dir=overrides/settings \
  bootstrap mypackage

# Verify setting was applied (check build log)
grep "CUSTOM_VAR=test_value" work-dir/logs/build-mypackage-*.log
```

### End-to-End (E2E) Testing

E2E tests live in the `e2e/` directory and test complete workflows.

**Run single e2e test**:
```bash
cd e2e
./test_bootstrap.sh
```

**Run all e2e tests** (takes time):
```bash
cd e2e
./run_all.sh
```

**Create your own e2e test**:
```bash
# Create test file
cat > e2e/test_my_feature.sh << 'EOF'
#!/bin/bash
set -e
set -x

# Source common utilities
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${SCRIPT_DIR}/common.sh"

# Setup test environment
WORK_DIR=$(mktemp -d)
trap "rm -rf ${WORK_DIR}" EXIT

cd ${WORK_DIR}

# Create test requirements
cat > requirements.txt << REQS
click
requests
REQS

# Run fromager
fromager \
  --work-dir=work \
  --wheels-repo=wheels \
  --sdists-repo=sdists \
  bootstrap -r requirements.txt

# Verify results
test -f wheels/simple/click/click-*.whl || exit 1
test -f wheels/simple/requests/requests-*.whl || exit 1
test -f work/graph.json || exit 1

echo "PASS"
EOF

chmod +x e2e/test_my_feature.sh
./e2e/test_my_feature.sh
```

**Example: Testing an override**:
```bash
# e2e/test_custom_override.sh
#!/bin/bash
set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${SCRIPT_DIR}/common.sh"

# Create override module
mkdir -p overrides/package_plugins
cat > overrides/package_plugins/__init__.py << 'EOF'
EOF

cat > overrides/package_plugins/mypackage.py << 'EOF'
def resolve_source(ctx, req, sdist_server_url, req_type):
    from packaging.version import Version
    return "https://custom.example.com/mypackage-2.0.tar.gz", Version("2.0")
EOF

# Create setup.py to install override
cat > overrides/setup.py << 'EOF'
from setuptools import setup, find_packages
setup(
    name="test-overrides",
    packages=find_packages(),
    entry_points={
        "fromager.project_overrides": [
            "mypackage = package_plugins.mypackage"
        ]
    }
)
EOF

# Install override
pip install -e overrides/

# Test that override is used
fromager bootstrap mypackage 2>&1 | grep "custom.example.com"

echo "PASS"
```

### Testing Your Specific Changes

**You added a new function**:
```python
# 1. Write test for the function
def test_my_new_function():
    result = mymodule.my_new_function(test_input)
    assert result == expected_output

# 2. Run the test
hatch run test:test tests/test_mymodule.py::test_my_new_function

# 3. Check coverage
hatch run test:test tests/test_mymodule.py
hatch run test:coverage-report
```

**You modified existing behavior**:
```python
# 1. Run existing tests to ensure nothing broke
hatch run test:test tests/test_affected_module.py

# 2. Add test for new behavior
def test_modified_behavior():
    # Test new code path
    result = mymodule.existing_function(new_input)
    assert result == new_expected_output

# 3. Update any tests that expected old behavior
```

**You added a new command**:
```bash
# 1. Test command manually
fromager mycommand --help
fromager mycommand test-arg

# 2. Add unit test in tests/test_commands.py
def test_mycommand():
    from click.testing import CliRunner
    from fromager.commands.mycommand import mycommand

    runner = CliRunner()
    result = runner.invoke(mycommand, ['test-arg'])

    assert result.exit_code == 0
    assert "expected output" in result.output

# 3. Create e2e test
./e2e/test_mycommand.sh
```

**You fixed a bug**:
```python
# 1. Write test that reproduces the bug
def test_bug_reproduction():
    """Reproduce bug #123: function fails with empty input."""
    # This should fail before your fix
    with pytest.raises(ValueError):
        mymodule.buggy_function("")

# 2. Verify test fails
hatch run test:test tests/test_mymodule.py::test_bug_reproduction

# 3. Fix the bug in code

# 4. Verify test now passes
hatch run test:test tests/test_mymodule.py::test_bug_reproduction

# 5. Update test to verify correct behavior
def test_bug_fix():
    """Bug #123 fixed: function handles empty input."""
    result = mymodule.buggy_function("")
    assert result == expected_empty_result
```

### Debugging Failed Tests

**Test fails with assertion error**:
```bash
# Run with verbose output
hatch run test:test -vv tests/test_mymodule.py::test_failing

# Use pytest's debug mode
hatch run test:test --pdb tests/test_mymodule.py::test_failing
# This drops into debugger at failure point
```

**Test fails with import error**:
```bash
# Check if module is installed
python -c "import fromager.mymodule"

# Install in development mode
pip install -e .

# Run tests again
hatch run test:test tests/test_mymodule.py
```

**Test passes locally but fails in CI**:
```bash
# Check for environment-specific issues
# - File paths (use tmp_path fixture, not hardcoded paths)
# - Network access (mock external calls)
# - System dependencies (document in requirements)

# Run in clean environment
hatch run test:test
```

### Best Practices for Testing

1. **Test behavior, not implementation**: Test what the function does, not how it does it
2. **Use fixtures for common setup**: Avoid repeating setup code
3. **Make tests independent**: Each test should work in isolation
4. **Use descriptive names**: Test name should describe what it tests
5. **Test edge cases**: Empty inputs, None values, boundary conditions
6. **Mock external dependencies**: Don't depend on network, filesystem, etc.
7. **Keep tests fast**: Slow tests discourage running them
8. **Add tests for bugs**: When fixing a bug, add test that would catch it
9. **Test error conditions**: Don't just test happy path
10. **Update tests when behavior changes**: Keep tests in sync with code

### Test Organization

```
tests/
  conftest.py              # Shared fixtures
  test_bootstrapper.py     # Tests for bootstrapper.py
  test_resolver.py         # Tests for resolver.py
  test_dependencies.py     # Tests for dependencies.py
  test_commands.py         # Tests for command modules
  testdata/                # Test data files
    sample.yaml
    test.patch

e2e/
  common.sh                # Shared utilities
  test_bootstrap.sh        # Bootstrap scenarios
  test_build.sh            # Build scenarios
  test_overrides.sh        # Override functionality
```

### When to Write Each Type of Test

| Change Type | Unit Test | Integration Test | E2E Test |
|-------------|-----------|------------------|----------|
| New function | ✓ Required | If interacts with other modules | If user-facing |
| Bug fix | ✓ Required | If multi-component | If user-reported |
| New command | ✓ Required | ✓ Required | ✓ Required |
| Performance improvement | Optional | ✓ Recommended | ✓ Benchmark |
| Refactoring | ✓ Verify existing pass | ✓ Verify existing pass | Optional |
| Documentation | N/A | N/A | Optional (if examples) |

### Getting Help with Testing

If you're unsure how to test your changes:

1. **Look at similar tests**: Find tests for similar functionality
2. **Ask in PR**: Maintainers can suggest test approach
3. **Start simple**: Better to have basic test than none
4. **Iterate**: Tests can be improved in code review

## Tips for Reading the Code

1. **Start with a real scenario**: Pick a package you know (like `requests`) and trace through the bootstrap process mentally or with a debugger.

2. **Follow the ctx**: The `WorkContext` is passed everywhere. When you see `ctx.something`, understand it's accessing central state.

3. **Look for overrides**: Many functions have a pattern of `overrides.find_and_invoke()` followed by a default implementation. This is the customization system.

4. **Check line comments**: The code has good comments explaining "why" decisions were made.

5. **Use the tests**: `tests/` has unit tests that show how individual components work. `e2e/` has full scenarios.

6. **Read error messages**: The code has informative error messages that explain what went wrong. Reading these helps understand expectations.

7. **Follow the types**: Type hints are comprehensive. If confused about what a function does, look at its parameters and return type.

8. **Watch for recursion**: The bootstrapper is inherently recursive. Use the `why` stack mentally to track depth.

9. **Understand immutability**: `DependencyNode` and `DependencyEdge` are frozen dataclasses - they never change after creation.

10. **Check the docs**: `docs/` has user documentation that explains behavior from outside, which helps understand code from inside.

## What's Next?

Now that you can navigate the codebase effectively, continue your journey:

- **[DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)** - Learn to troubleshoot issues and debug problems
- **[CONTRIBUTING_GUIDE.md](CONTRIBUTING_GUIDE.md)** - Transition from code reader to contributor

