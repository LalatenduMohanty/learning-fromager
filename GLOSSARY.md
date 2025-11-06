# Fromager Glossary

Key terms used throughout fromager and this documentation:

## Package Distribution Formats
- **sdist** (Source Distribution): Archive containing Python source code, typically `.tar.gz` or `.zip` format. Must be built to be installed.
- **[wheel](https://peps.python.org/pep-0427/)**: Pre-built binary distribution format (`.whl` file). Can be installed directly without compilation.
- **Built Distribution**: General term for packages ready to install (wheels are the standard built distribution format).

## Python Packaging Standards
- **[PEP 517](https://peps.python.org/pep-0517/)**: Defines the interface for build backends and the `pyproject.toml` structure for specifying build requirements.
- **[PEP 518](https://peps.python.org/pep-0518/)**: Specifies the `pyproject.toml` file format for declaring build system requirements.
- **[PEP 503](https://peps.python.org/pep-0503/)**: Simple Repository API - defines the directory structure for package indexes (the `/simple/` layout).
- **[PEP 658](https://peps.python.org/pep-0658/)**: Metadata files for packages - allows package metadata to be available without downloading the full package.
- **[PEP 714](https://peps.python.org/pep-0714/)**: Rename of PEP 658 core metadata attribute.

## Package Naming
- **Canonical name**: Normalized package name following Python packaging standards (`My-Package` → `my-package`). Lowercase with hyphens.
- **Override name**: Module-safe version of canonical name used for override plugins (`my-package` → `my_package`). When fromager creates override plugins using stevedore, these plugins are Python modules that need to be imported. Since Python cannot import a module named `scikit-learn.py` (hyphens are invalid in identifiers), fromager converts the distribution package name to a valid module name by replacing hyphens with underscores.
- **Distribution name**: The actual name as it appears in package files, may have different casing.

## Dependency Types
- **Build-system dependencies**: Minimal tools required to understand how to build a package, specified in `[build-system] requires` in `pyproject.toml`. These are installed before any build backend hooks are called. Examples: `setuptools`, `hatchling`, `flit-core`.
- **Build-backend dependencies**: Additional dependencies discovered dynamically by calling the build backend's `get_requires_for_build_wheel()` hook. These are package-specific build requirements not known until the build system inspects the source. Examples: `cython` for packages with Cython extensions, `numpy` for packages that compile against NumPy headers.
- **Build-sdist dependencies**: Dependencies required specifically for creating source distributions, returned by the `get_requires_for_build_sdist()` hook. These may differ from wheel build dependencies and are needed before sdist creation.
- **Install dependencies** (Runtime dependencies): Packages needed when using the built package (from `Requires-Dist` in wheel metadata).
- **Top-level dependencies**: Requirements specified directly by the user, not discovered through dependency resolution.

## Build Process Terms
- **Bootstrap**: The complete recursive process of building a package and all its dependencies from scratch.
- **Resolver**: Component that determines which version of a package to use based on requirements and constraints.
- **Provider**: Strategy class for version resolution (PyPI, GitHub, GitLab, custom registries).
- **Build environment**: Isolated Python virtual environment used for building a specific package.
- **Build order**: Topological sort of dependencies determining the sequence packages must be built in.
- **Build variant**: Different build configurations for the same package (e.g., `cpu` vs `gpu` for ML packages).

## Graph and Relationships

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

## Customization System
- **Override**: Package-specific custom implementation of a standard function (e.g., custom version resolution).
- **Hook**: Extension point that multiple plugins can handle for cross-cutting concerns (e.g., post-build actions).
- **Plugin**: External package providing overrides or hooks, registered via entry points.
- **Settings**: YAML-based configuration controlling package build behavior.
- **Patch**: File containing source code modifications applied before building.

## Package Repositories
- **Package repository**: Directory structure serving packages following PEP 503 simple repository API.
- **Package index**: Server providing package metadata and downloads (e.g., PyPI).
- **Wheel server**: Local HTTP server providing built wheels during the build process.
- **Simple API**: The PEP 503 `/simple/` directory layout for package indexes.

## Source Code Origins
- **Source origin**: The location where fromager obtains source code for building packages.
- **PyPI**: Python Package Index - the default source for most Python packages (`https://pypi.org/simple`).
- **Git repository**: Version control system containing source code, accessible via git+ URLs.
- **GitHub/GitLab provider**: API-based resolution using GitHub or GitLab REST APIs to fetch release tarballs.
- **Custom package index**: Private or alternative PyPI-compatible servers (devpi, Artifactory, Nexus).
- **Direct URL**: Explicit download URL for source distributions, configured in package settings.
- **Local file system**: Source code from local files or directories using file:// URLs.
- **Override provider**: Custom source resolution logic implemented via plugin system.
- **Source resolution**: Process of determining which source origin to use and obtaining the download URL.
- **Source priority**: Order in which fromager checks different source origins (Git URL → Override → Settings → Custom index → PyPI).

## Version Control
- **Constraint**: Version limitation applied to packages (e.g., `package<2.0`).
- **Requirement**: Package dependency specification with optional version constraints (e.g., `package>=1.0,<2.0`).
- **Specifier**: Version range specification in a requirement (the `>=1.0,<2.0` part).
- **Version resolution**: Process of selecting a specific version that satisfies all requirements and constraints.
- **Pre-release**: Development version (e.g., `1.0.0a1`, `1.0.0rc1`) not selected by default.

## Build Isolation
- **Network isolation**: Running builds in a Linux namespace with no network access (using `unshare -rn`).
- **Build isolation**: Running each build in its own virtual environment to prevent interference.
- **Vendoring**: Including dependencies within a package's source code for offline builds.

## Caching
- **Local cache**: Built wheels stored locally for reuse within a bootstrap run.
- **Remote cache**: Wheel server with previously built packages for distributed builds.
- **Resolver cache**: Cached results of version lookups to avoid redundant network requests.
- **UV cache**: Package cache used by the `uv` installer for fast dependency installation.

## Common Acronyms
- **ABI**: Application Binary Interface - defines binary compatibility between compiled code.
- **ELF**: Executable and Linkable Format - binary format used on Linux, analyzed for shared library dependencies.
- **URL**: Uniform Resource Locator - web address for downloading packages or sources.
- **VCS**: Version Control System (git, mercurial, etc.).
