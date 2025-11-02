# How to Read the Fromager Codebase

This guide helps you understand the fromager codebase structure and navigate it effectively.

## Prerequisites

Before diving into the code, you should have:

- **Completed the [README examples](README.md)** - Understand how to use fromager
- **Read the [Architecture Guide](ARCHITECTURE.md)** - Understand the system design and core concepts

This guide focuses on **how to navigate and read the actual code** with practical examples and techniques.

## Quick Start: Your First Hour

### 1. Start with the Bootstrap Flow (30 minutes)

Open `src/fromager/bootstrapper.py` and read these methods in order:

1. `Bootstrapper.__init__()` (line ~44): See what state the bootstrapper maintains
2. `Bootstrapper.bootstrap()` (line ~131): The main entry point - trace through this carefully
3. `Bootstrapper.resolve_version()` (line ~76): Understand how versions are chosen
4. `Bootstrapper._download_and_unpack_source()` (line ~200): See source acquisition
5. `Bootstrapper._handle_build_requirements()` (line ~378): Understand recursive dependency handling

**Exercise**: Pick a simple package you know (like `click`) and trace mentally how it would flow through these methods.

### 2. Follow a Simple Command (15 minutes)

Open `src/fromager/commands/canonicalize.py` - the simplest command:

```python
# Line ~12
@click.command()
@click.argument("name", nargs=-1)
@click.pass_obj
def canonicalize(wkctx: context.WorkContext, name: tuple[str, ...]) -> None:
    for n in name:
        print(canonicalize_name(n))
```

Notice:
- `@click.pass_obj` passes the WorkContext
- Commands are just Click commands with entry points
- Simple commands don't need complex state management

### 3. Understand State Management (15 minutes)

Open `src/fromager/context.py` and examine:

1. `WorkContext.__init__()` (line ~35): All the state that flows through the system
2. `WorkContext.setup()` (line ~169): How directories are initialized
3. `WorkContext.package_build_info()` (line ~160): How per-package settings are accessed

The WorkContext is passed to almost every function - it's your window into the entire build state.

## Core Classes and Their Relationships

### The Big Picture

```
User Command
    |
    v
Click Command (commands/*.py)
    |
    v
WorkContext (central state)
    |
    +---> Bootstrapper (orchestration)
    |         |
    |         +---> Resolver (version selection)
    |         +---> Sources (source acquisition)
    |         +---> Dependencies (requirement extraction)
    |         +---> BuildEnvironment (isolated builds)
    |         +---> Wheels (wheel building)
    |
    +---> DependencyGraph (relationship tracking)
    +---> Settings (configuration)
    +---> Constraints (version control)
```

### WorkContext: The Central State Object

**File**: `src/fromager/context.py`

**Purpose**: Carries all state through the build process - configuration, paths, graphs, caches.

**Created**: Once at startup in `__main__.py:main()` (line ~233)

**Key Attributes**:
```python
# Line ~35-88
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
        self.settings = active_settings                     # Line ~58
        self.constraints = constraints.Constraints()        # Line ~60
        self.sdists_repo = pathlib.Path(sdists_repo)       # Line ~66
        self.wheels_repo = pathlib.Path(wheels_repo)       # Line ~69
        self.dependency_graph = dependency_graph.DependencyGraph()  # Line ~88
```

**Key Methods**:
- `setup()` (line ~169): Creates all required directories
- `package_build_info()` (line ~160): Gets configuration for a specific package
- `clean_build_dirs()` (line ~189): Cleanup after build
- `pip_wheel_server_args` (property, line ~113): Arguments for pip to use local server

**Used By**: Every major operation - passed as first parameter conventionally named `ctx`

**Example Usage**:
```python
# From sources.py, line ~61
def download_source(
    *,
    ctx: context.WorkContext,  # Always passed
    req: Requirement,
    version: Version,
    download_url: str,
) -> pathlib.Path:
    # Access settings
    pbi = ctx.package_build_info(req)  # Line ~49
    
    # Access repositories
    source_path = ctx.sdists_downloads / filename  # Line ~186
    
    return source_path
```

### Bootstrapper: The Orchestrator

**File**: `src/fromager/bootstrapper.py`

**Purpose**: Coordinates the complete recursive build process from requirements to wheels.

**Created**: In `commands/bootstrap.py:bootstrap()` (line ~167)

**Key State**:
```python
# Line ~44-74
class Bootstrapper:
    def __init__(
        self,
        ctx: context.WorkContext,
        progressbar: progress.Progressbar | None = None,
        prev_graph: DependencyGraph | None = None,
        cache_wheel_server_url: str | None = None,
        sdist_only: bool = False,
    ):
        self.ctx = ctx
        self.why: list[tuple[RequirementType, Requirement, Version]] = []  # Line ~57
        self._build_stack: list[typing.Any] = []                           # Line ~61
        self._seen_requirements: set[SeenKey] = set()                      # Line ~69
        self._resolved_requirements: dict[str, tuple[str, Version]] = {}   # Line ~72
```

**Key Methods**:

1. **`bootstrap(req, req_type)`** (line ~131): Main entry point
   ```python
   def bootstrap(self, req: Requirement, req_type: RequirementType) -> Version:
       # Resolve version
       source_url, resolved_version = self.resolve_version(req=req, req_type=req_type)
       
       # Add to graph
       self._add_to_graph(req, req_type, resolved_version, source_url)
       
       # Check if already seen
       if self._mark_as_seen(...):
           return resolved_version
       
       # Download and build
       sdist_root_dir = self._download_and_unpack_source(...)
       
       # Recursively handle dependencies
       self._handle_build_requirements(...)
       self._handle_install_requirements(...)
       
       return resolved_version
   ```

2. **`resolve_version(req, req_type)`** (line ~76): Version selection
   - Checks cache first (line ~86)
   - Handles prebuilt wheels vs source builds (line ~91)
   - Delegates to resolver or finder

3. **`_download_and_unpack_source()`** (line ~200): Source acquisition
   - Resolves source location
   - Downloads or clones
   - Unpacks and applies patches
   - Returns path to source root

4. **`_handle_build_requirements()`** (line ~378): Recursive build dependency processing
   - Gets build-system dependencies
   - Gets build-backend dependencies  
   - Gets build-sdist dependencies
   - Recursively bootstraps each one

5. **`_handle_install_requirements()`** (line ~538): Runtime dependency processing
   - Extracts from wheel or sdist metadata
   - Filters by markers
   - Recursively bootstraps each one

**State Tracking**:
- `why` stack: Tracks "why are we building this" for debugging
- `_seen_requirements`: Prevents infinite recursion and duplicate work
- `_resolved_requirements`: Caches version resolution results
- `_build_stack`: Maintains build order

**Example Flow**:
```
bootstrap(requests)
  |
  +-> resolve_version(requests) -> requests==2.31.0
  |
  +-> _download_and_unpack_source(requests, 2.31.0)
  |     +-> sources.resolve_source() -> URL
  |     +-> sources.download_source() -> tar.gz file
  |     +-> unpack and patch
  |
  +-> _handle_build_requirements(requests)
  |     +-> dependencies.get_build_system_dependencies()
  |     +-> bootstrap(setuptools) [recursive!]
  |     +-> bootstrap(wheel) [recursive!]
  |
  +-> build sdist and wheel
  |
  +-> _handle_install_requirements(requests)
        +-> dependencies.get_install_dependencies()
        +-> bootstrap(urllib3) [recursive!]
        +-> bootstrap(charset-normalizer) [recursive!]
        +-> ...
```

### DependencyGraph: Relationship Tracker

**File**: `src/fromager/dependency_graph.py`

**Purpose**: Maintains a directed graph of package dependencies with typed edges.

**Created**: In `WorkContext.__init__()` (line ~88 of context.py)

**Key Components**:

1. **`DependencyNode`** (line ~37): Represents a package version
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

2. **`DependencyEdge`** (line ~119): Represents a dependency relationship
   ```python
   @dataclasses.dataclass(frozen=True, order=True, slots=True)
   class DependencyEdge:
       destination_node: DependencyNode
       req: Requirement            # The requirement that created this edge
       req_type: RequirementType   # install, build-system, build-backend, etc.
   ```

3. **`DependencyGraph`** (line ~137): The graph itself
   ```python
   class DependencyGraph:
       def __init__(self):
           self.nodes: dict[str, DependencyNode] = {}  # key -> node
           self.clear()  # Creates ROOT node
   ```

**Key Methods**:

- `add_dependency()` (line ~234): Add a package and its relationship to parent
- `get_install_dependencies()` (line ~283): Get all runtime dependencies
- `get_dependency_edges()` (line ~270): Traverse with filtering
- `serialize()` (line ~209): Save to JSON
- `from_file()` (line ~143): Load from JSON

**Example Usage**:
```python
# From bootstrapper.py, line ~145
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

1. **`resolve()`** (line ~77): Main entry point
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

2. **`resolve_from_provider()`** (line ~158): Uses resolvelib
   ```python
   def resolve_from_provider(provider: BaseProvider, req: Requirement):
       reporter = LogReporter(req)
       rslvr = resolvelib.Resolver(provider, reporter)
       result = rslvr.resolve([req])
       # Returns (url, version) tuple
   ```

**Provider Classes**:

1. **`PyPIProvider`** (line ~471): Resolves from package indexes
   - Fetches package index HTML (PEP 503)
   - Parses available versions
   - Filters by Python version, platform, yanked status
   - Respects constraints
   - Caches results

2. **`GitHubTagProvider`** (line ~665): Resolves from GitHub tags
   - Fetches tags via GitHub API
   - Matches version patterns
   - Returns tarball URLs

3. **`GitLabTagProvider`** (line ~735): Resolves from GitLab tags
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

1. **`__init__()`** (line ~79): Creates virtualenv
   ```python
   class BuildEnvironment:
       def __init__(self, ctx: context.WorkContext, parent_dir: pathlib.Path):
           self.path = parent_dir / f"build-{platform.python_version()}"
           self._createenv()  # Line ~86
   ```

2. **`install()`** (line ~196): Install dependencies using uv
   ```python
   def install(
       self,
       requirements: typing.Iterable[Requirement],
       req_type: RequirementType,
   ) -> None:
       # Build uv pip install command
       cmd = ["uv", "pip", "install"]
       cmd.extend(self._ctx.pip_wheel_server_args)  # Use local server
       cmd.extend(self._ctx.pip_constraint_args)    # Apply constraints
       cmd.extend(str(r) for r in requirements)
       
       # Run in virtualenv
       self.run(cmd, ...)
   ```

3. **`run()`** (line ~136): Execute command in environment
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

4. **`get_venv_environ()`** (line ~93): Prepare environment
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

1. **`get_build_system_dependencies()`** (line ~40): PEP 517 build-system requirements
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

2. **`get_build_backend_dependencies()`** (line ~106): From PEP 517 hooks
   - Calls `get_requires_for_build_wheel()` hook
   - Caches to `build-backend-requirements.txt`

3. **`get_build_sdist_dependencies()`** (line ~151): For building sdist
   - Calls `get_requires_for_build_sdist()` hook
   - Caches to `build-sdist-requirements.txt`

4. **`get_install_dependencies_of_wheel()`** (line ~319): Runtime deps from wheel
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

1. **`resolve_source()`** (line ~106): Find source location
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

2. **`download_source()`** (line ~60): Download the source
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

3. **`unpack_source()`** (line ~253): Extract archive
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

4. **`prepare_source()`** (line ~389): Apply patches and prepare
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

**Purpose**: Builds wheels from source and adds metadata.

**Key Functions**:

1. **`build_wheel()`** (line ~280): Main wheel building
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

2. **`default_build_wheel()`** (line ~428): Standard PEP 517 build
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

3. **`add_extra_metadata_to_wheels()`** (line ~148): Add fromager metadata
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

## Real Code Examples with Line Numbers

### Example 1: How a Command Executes (bootstrap)

**Entry Point**: `src/fromager/commands/bootstrap.py` line ~100

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
    # Parse input requirements (line ~34)
    to_build = _get_requirements_from_args(toplevel, requirements_files)
    
    # Create bootstrapper (line ~167)
    bs = bootstrapper.Bootstrapper(
        ctx=wkctx,
        progressbar=pbar,
        prev_graph=prev_graph,
        cache_wheel_server_url=cache_wheel_server_url,
        sdist_only=sdist_only,
    )
    
    # Start server (line ~174)
    server.start_wheel_server(wkctx)
    
    # Bootstrap each requirement (line ~177)
    for req in to_build:
        bs.bootstrap(
            req,
            RequirementType.TOP_LEVEL,
        )
```

**What Happens Next**: Flows into `Bootstrapper.bootstrap()` at line ~131 of `bootstrapper.py`

### Example 2: Version Resolution with Constraints

**Start**: `src/fromager/bootstrapper.py` line ~76

```python
def resolve_version(
    self,
    req: Requirement,
    req_type: RequirementType,
) -> tuple[str, Version]:
    # Check cache first (line ~85)
    req_str = str(req)
    if req_str in self._resolved_requirements:
        return self._resolved_requirements[req_str]
    
    # Check if prebuilt (line ~90)
    pbi = self.ctx.package_build_info(req)
    if pbi.pre_built:
        source_url, resolved_version = self._resolve_prebuilt_with_history(...)
    else:
        source_url, resolved_version = self._resolve_source_with_history(...)
    
    # Cache result (line ~102)
    self._resolved_requirements[req_str] = (source_url, resolved_version)
    return source_url, resolved_version
```

**Flows to**: `src/fromager/bootstrapper.py` line ~807 `_resolve_source_with_history()`

```python
def _resolve_source_with_history(
    self, req: Requirement, req_type: RequirementType
) -> tuple[str, Version]:
    # Check previous graph for version (line ~810)
    if self.prev_graph:
        nodes = self.prev_graph.get_nodes_by_name(req.name)
        if nodes:
            # Reuse version from previous run
            return nodes[0].download_url, nodes[0].version
    
    # Resolve fresh (line ~824)
    resolved_url, resolved_version = sources.resolve_source(
        ctx=self.ctx,
        req=req,
        sdist_server_url=resolver.PYPI_SERVER_URL,
        req_type=req_type,
    )
    return resolved_url, resolved_version
```

**Flows to**: `src/fromager/sources.py` line ~106 `resolve_source()`

```python
def resolve_source(
    *,
    ctx: context.WorkContext,
    req: Requirement,
    sdist_server_url: str,
    req_type: RequirementType | None = None,
) -> tuple[str, Version]:
    # Get constraint (line ~116)
    constraint = ctx.constraints.get_constraint(req.name)
    
    # Allow override (line ~122)
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

**Flows to**: `src/fromager/sources.py` line ~152 `default_resolve_source()`

```python
def default_resolve_source(
    ctx: context.WorkContext,
    req: Requirement,
    sdist_server_url: str,
    req_type: RequirementType | None = None,
) -> tuple[str, Version]:
    pbi = ctx.package_build_info(req)
    
    # Get resolver settings (line ~161)
    override_sdist_server_url = pbi.resolver_sdist_server_url(sdist_server_url)
    
    # Call resolver (line ~163)
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

**Flows to**: `src/fromager/resolver.py` line ~77 `resolve()`

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
    # Get provider (line ~88)
    provider = overrides.find_and_invoke(
        req.name,
        "get_resolver_provider",
        default_resolver_provider,  # Usually PyPIProvider
        ctx=ctx,
        req=req,
        ...
    )
    
    # Resolve (line ~100)
    return resolve_from_provider(provider, req)
```

**Flows to**: `src/fromager/resolver.py` line ~158 `resolve_from_provider()`

```python
def resolve_from_provider(provider: BaseProvider, req: Requirement):
    reporter = LogReporter(req)
    rslvr = resolvelib.Resolver(provider, reporter)  # External library
    
    # This calls provider.find_matches() to get candidates
    result = rslvr.resolve([req])
    
    # Extract result (line ~171)
    for candidate in result.mapping.values():
        return candidate.url, candidate.version
```

**Provider's find_matches**: `src/fromager/resolver.py` line ~524 `PyPIProvider.find_matches()`

```python
def find_matches(
    self,
    identifier: str,
    requirements: RequirementsMap,
    incompatibilities: CandidatesMap,
) -> typing.Iterable[Candidate]:
    # Try cache first (line ~530)
    candidates = self.get_from_cache(identifier, requirements, incompatibilities)
    
    if not candidates:
        # Get from PyPI (line ~535)
        for candidate in get_project_from_pypi(
            identifier,
            set(),
            self.sdist_server_url,
            self.ignore_platform,
        ):
            # Validate against requirements and constraints (line ~541)
            if self.validate_candidate(identifier, requirements, incompatibilities, candidate):
                candidates.append(candidate)
        
        # Cache it (line ~545)
        self.add_to_cache(identifier, candidates)
    
    # Return sorted by version descending (line ~571)
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

**How It's Called**: `src/fromager/sources.py` line ~122

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

**Override Lookup**: `src/fromager/overrides.py` line ~40

```python
def find_and_invoke(
    distname: str,
    method: str,
    default_fn: typing.Callable,
    **kwargs: typing.Any,
) -> typing.Any:
    # Look for override (line ~46)
    fn = find_override_method(distname, method)
    if not fn:
        fn = default_fn  # Use default if no override
    
    # Invoke it (line ~50)
    result = invoke(fn, **kwargs)
    
    # Log (line ~51)
    if fn is default_fn:
        logger.debug(f"{distname}: override method {fn.__name__} returned {result}")
    else:
        logger.info(f"{distname}: override method {fn.__name__} returned {result}")
    
    return result
```

**Finding Override**: `src/fromager/overrides.py` line ~115

```python
def find_override_method(distname: str, method: str) -> typing.Callable | None:
    # Convert name (line ~122)
    distname = pkgname_to_override_module(distname)  # torch -> torch
    
    # Load module via stevedore (line ~124)
    try:
        mod = _get_extensions()[distname].plugin
    except KeyError:
        return None  # No override module
    
    # Check if method exists (line ~132)
    if not hasattr(mod, method):
        return None  # Module exists but not this method
    
    # Return the function (line ~136)
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

**Loading**: `src/fromager/packagesettings.py` line ~886 `Settings.from_files()`

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
    # Load global settings (line ~902)
    settings = SettingsFile.from_file(settings_file) if settings_file.exists() else SettingsFile()
    
    # Load per-package settings (line ~910)
    package_settings: list[PackageSettings] = []
    if settings_dir.exists():
        for yaml_file in sorted(settings_dir.glob("*.yaml")):
            pkg_settings = PackageSettings.from_yaml(yaml_file)
            package_settings.append(pkg_settings)
    
    # Create Settings object (line ~920)
    return cls(
        settings=settings,
        package_settings=package_settings,
        patches_dir=patches_dir,
        variant=variant,
        max_jobs=max_jobs,
    )
```

**Accessing**: `src/fromager/context.py` line ~160

```python
def package_build_info(
    self, package: str | packagesettings.Package | Requirement
) -> packagesettings.PackageBuildInfo:
    if isinstance(package, Requirement):
        name = package.name
    else:
        name = package
    
    # Delegates to settings (line ~167)
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
extra_env = pbi.extra_environ
```

**PackageBuildInfo**: `src/fromager/packagesettings.py` line ~960

```python
class PackageBuildInfo:
    def __init__(
        self,
        name: Package,
        variant: Variant,
        per_package: PerPackage,      # From torch.yaml
        global_cfg: SettingsFile,      # From settings.yaml
    ):
        self._name = name
        self._variant = variant
        self._per_package = per_package
        self._global_cfg = global_cfg
    
    # Computed properties with fallbacks
    @property
    def pre_built(self) -> bool:
        # Check variant first, then package, then global
        if self._per_package.variants and self._variant in self._per_package.variants:
            if self._per_package.variants[self._variant].pre_built is not None:
                return self._per_package.variants[self._variant].pre_built
        if self._per_package.pre_built is not None:
            return self._per_package.pre_built
        return self._global_cfg.pre_built
    
    @property
    def extra_environ(self) -> dict[str, str]:
        # Merge global + package + variant
        result = {}
        result.update(self._global_cfg.env)
        result.update(self._per_package.env)
        if self._per_package.variants and self._variant in self._per_package.variants:
            result.update(self._per_package.variants[self._variant].env)
        return result
```

## Command to Code Mapping

| User Command | Entry Point | Key Functions Called | Output |
|-------------|-------------|---------------------|---------|
| `fromager bootstrap requests` | `commands/bootstrap.py:bootstrap()` (line ~100) | `Bootstrapper.bootstrap()` -> recursive dependency resolution | `wheels-repo/simple/`, `work-dir/graph.json`, `work-dir/build-order.json` |
| `fromager build requests 2.31.0` | `commands/build.py:build()` (line ~81) | `build_one()` -> `build_sdist()` + `build_wheel()` | Single sdist + wheel |
| `fromager build-sequence` | `commands/build.py:build_sequence()` (line ~163) | Reads `build-order.json`, calls `build_one()` for each | All wheels in order |
| `fromager graph why requests` | `commands/graph.py:graph()` (line ~52) -> `find_why()` (line ~158) | `DependencyGraph.get_nodes_by_name()` | Dependency chain explanation |
| `fromager list-overrides` | `commands/list_overrides.py:list_overrides()` (line ~8) | `overrides._get_extensions()` | List of available override modules |
| `fromager canonicalize My-Package` | `commands/canonicalize.py:canonicalize()` (line ~12) | `canonicalize_name()` | `my-package` |
| `fromager stats` | `commands/stats.py:stats()` (line ~9) | `metrics.format_time_stats()` | Timing breakdown per package |

## Module Dependency Map

Understanding which modules depend on which helps navigate the code:

```
High Level (Commands)
  commands/*.py
    |
    v
Mid Level (Orchestration)
  bootstrapper.py
  context.py
    |
    v
Core Operations
  resolver.py
  sources.py
  wheels.py
  dependencies.py
  build_environment.py
    |
    v
Customization
  overrides.py
  hooks.py
  packagesettings.py
    |
    v
Data Structures
  dependency_graph.py
  constraints.py
  requirements_file.py
    |
    v
Utilities
  external_commands.py
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

1. **Create new provider class** in `resolver.py` (after line ~805)
   - Inherit from `GenericProvider`
   - Implement `_find_tags()` method
   - Add caching

2. **Create override** in external package
   - Implement `resolver_provider()` returning your provider
   - Register in `pyproject.toml`

3. **Test** with `fromager bootstrap mypackage`

**Example**: See `GitLabTagProvider` (line ~735) as template

### Adding a New Build Step

1. **Add method** to `Bootstrapper` class in `bootstrapper.py`
2. **Call it** from `bootstrap()` method at appropriate point
3. **Add to step command** in `commands/step.py` (line ~61)

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

