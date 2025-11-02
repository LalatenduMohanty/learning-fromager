# Debugging Guide for Fromager Contributors

This guide helps you diagnose and fix issues in fromager, whether you're debugging your own changes or investigating user-reported problems.

## Quick Diagnosis Checklist

When something goes wrong, check these in order:

1. **Enable verbose logging**: `fromager -v --log-file=debug.log ...`
2. **Check the error message**: Fromager has detailed error messages
3. **Look at build logs**: `work-dir/logs/build-{package}-{version}.log`
4. **Inspect the graph**: `work-dir/graph.json` shows what was resolved
5. **Check constraints**: `work-dir/constraints.txt` shows version limits
6. **Verify network**: Some builds need network despite isolation flags

## Debugging Tools and Techniques

### 1. Verbose Logging

**Enable verbose output to console**:
```bash
fromager -v bootstrap mypackage
```

**Enable debug logging to file**:
```bash
fromager --log-file=debug.log bootstrap mypackage
```

**Enable both**:
```bash
fromager -v --log-file=debug.log bootstrap mypackage
```

**Enable error-only log**:
```bash
fromager --error-log-file=errors.log bootstrap mypackage
```

**Custom log format**:
```bash
fromager --log-format='%(asctime)s - %(name)s - %(levelname)s - %(message)s' bootstrap mypackage
```

### 2. Understanding Log Output

**Key log patterns to look for**:

```
# Dependency chain - shows why something is being built
[INFO] bootstrapping requests>=2.28.0 as install dependency of [('install', Requirement('httpx>=0.24.0'), Version('0.27.0'))]

# Version resolution - shows what version was chosen
[INFO] looking for candidates for Requirement('requests>=2.28.0')
[INFO] selecting requests==2.31.0

# Constraint application
[INFO] incoming requirement requests>=2.28.0 matches constraint requests<2.32.0. Will apply both.

# Source download
[INFO] downloading source for requests
[DEBUG] have source for requests version 2.31.0 in /path/to/requests-2.31.0.tar.gz

# Build dependencies
[INFO] getting build system dependencies for requests in /path/to/requests-2.31.0
[INFO] getting build backend dependencies for requests in /path/to/requests-2.31.0

# Building
[INFO] building sdist for requests 2.31.0
[INFO] building wheel for requests 2.31.0

# Override/hook invocations
[INFO] requests: found resolve_source override
[INFO] requests: override method custom_resolve_source returned ('https://...', Version('2.31.0'))
```

**Error patterns**:

```
# Missing dependency
ERROR: Unable to resolve requirement specifier requests>=3.0.0 with constraint requests<2.32.0

# Build failure
ERROR: Failed to build wheel for requests

# Network issue
ERROR: Failed to fetch package index from https://pypi.org/simple/requests/: Connection timeout

# Missing file
ERROR: Could not find sdist for requests version 2.31.0
```

### 3. Using the Step Command

The `step` command lets you execute individual build steps for debugging:

```bash
# Just download source
fromager step --step download mypackage==1.0.0

# Just resolve version (no download)
fromager step --step resolve mypackage

# Build system dependencies only
fromager step --step build-system-dependencies mypackage==1.0.0

# Build backend dependencies
fromager step --step build-backend-dependencies mypackage==1.0.0

# Build sdist only
fromager step --step build-sdist mypackage==1.0.0

# Build wheel only (requires sdist exists)
fromager step --step build-wheel mypackage==1.0.0

# Get install dependencies
fromager step --step install-dependencies mypackage==1.0.0
```

**Available steps** (see `commands/step.py`):
- `resolve`: Determine version to use
- `download`: Download source
- `unpack`: Unpack downloaded source
- `build-system-dependencies`: Get build-system requirements
- `build-backend-dependencies`: Get build-backend requirements  
- `build-sdist-dependencies`: Get build-sdist requirements
- `build-sdist`: Build source distribution
- `build-wheel`: Build wheel
- `install-dependencies`: Get install requirements

**Example debugging session**:
```bash
# Start with resolve to see what version is chosen
fromager step --step resolve mypackage
# Output: Resolved mypackage to 2.0.0

# Download it
fromager step --step download mypackage==2.0.0
# Check if download succeeds

# Try to get build system deps
fromager step --step build-system-dependencies mypackage==2.0.0
# See if pyproject.toml parsing works

# Try building sdist
fromager step --step build-sdist mypackage==2.0.0
# Check build output
```

### 4. Python Debugger (pdb)

**Insert breakpoint in code**:
```python
# In any fromager module
def my_function(ctx, req):
    import pdb; pdb.set_trace()
    # Execution will stop here
    result = do_something(req)
    return result
```

**Run fromager**:
```bash
python -m fromager bootstrap mypackage
```

**Common pdb commands**:
- `n` (next): Execute next line
- `s` (step): Step into function
- `c` (continue): Continue execution
- `p variable`: Print variable value
- `pp variable`: Pretty-print variable
- `l` (list): Show code around current line
- `w` (where): Show call stack
- `u` (up): Move up call stack
- `d` (down): Move down call stack
- `q` (quit): Exit debugger

**Better alternative - ipdb**:
```bash
pip install ipdb
```

```python
import ipdb; ipdb.set_trace()
```

Benefits: Tab completion, syntax highlighting, better history

### 5. Inspecting Generated Files

**Dependency graph** (`work-dir/graph.json`):
```bash
# Pretty print the graph
python -m json.tool work-dir/graph.json | less

# Find a specific package
jq '.[] | select(.canonicalized_name == "requests")' work-dir/graph.json

# Show all packages
jq 'keys' work-dir/graph.json

# Show dependencies of a package
jq '."requests==2.31.0".edges' work-dir/graph.json
```

**Build order** (`work-dir/build-order.json`):
```bash
# View build order
cat work-dir/build-order.json | python -m json.tool

# Find position of package
jq '.[] | select(.name == "requests")' work-dir/build-order.json
```

**Constraints** (`work-dir/constraints.txt`):
```bash
# View all constraints
cat work-dir/constraints.txt

# Find specific constraint
grep requests work-dir/constraints.txt
```

**Cached dependencies**:
```bash
# Each unpacked source has cached dependency files
ls work-dir/mypackage-1.0.0/

# build-system-requirements.txt
# build-backend-requirements.txt
# build-sdist-requirements.txt
# requirements.txt
```

**Build logs** (`work-dir/logs/`):
```bash
# View latest build log
ls -t work-dir/logs/build-*.log | head -1 | xargs cat

# Find failed builds
grep -l "ERROR" work-dir/logs/build-*.log

# Search for specific error
grep -r "ModuleNotFoundError" work-dir/logs/
```

## Common Problems and Solutions

### Problem: "Unable to resolve requirement"

**Symptoms**:
```
ERROR: Unable to resolve requirement specifier mypackage>=1.0.0 with constraint mypackage<2.0.0
```

**Causes**:
1. No version satisfies both requirement and constraint
2. Package doesn't exist on index
3. All versions are yanked
4. Python version incompatibility
5. Platform incompatibility

**Debugging**:
```bash
# Check what versions are available
fromager list-versions mypackage

# Check what constraints are applied
cat work-dir/constraints.txt | grep mypackage

# Try with verbose logging to see filtering
fromager -v step --step resolve mypackage

# Check if package exists on PyPI
curl -s https://pypi.org/pypi/mypackage/json | jq '.releases | keys'
```

**Solutions**:
- Relax constraint: Edit constraints file or use `--skip-constraints`
- Check package name spelling
- Verify package is available on your index
- Check if pre-release versions are needed: Use settings to enable prereleases

### Problem: "Failed to build wheel"

**Symptoms**:
```
ERROR: Failed to build wheel for mypackage
```

**Debugging**:
```bash
# Check build log
cat work-dir/logs/build-mypackage-1.0.0.log

# Try building manually
cd work-dir/mypackage-1.0.0/mypackage-1.0.0
python -m build --wheel

# Check if build dependencies are installed
fromager step --step build-backend-dependencies mypackage==1.0.0
cat work-dir/mypackage-1.0.0/build-backend-requirements.txt

# Try with network isolation disabled
fromager --no-network-isolation bootstrap mypackage
```

**Common causes**:
1. Missing system dependencies (C libraries, compilers)
2. Incorrect build-system requirements
3. Network access needed during build
4. Environment variables not set

**Solutions**:
- Install system dependencies: `sudo apt-get install python3-dev gcc ...`
- Add missing build dependencies in settings:
  ```yaml
  # overrides/settings/mypackage.yaml
  pyproject_fix:
    update_build_requires:
      - setuptools>=60.0
  ```
- Set environment variables:
  ```yaml
  env:
    SOME_VAR: "value"
  ```
- Disable network isolation if legitimately needed

### Problem: Dependency cycle detected

**Symptoms**:
```
WARNING: Circular dependency detected: A -> B -> C -> A
```

**Debugging**:
```bash
# Use graph command to investigate
fromager graph why A
fromager graph why B
fromager graph why C

# Visualize the graph
fromager graph export work-dir/graph.json --format dot > graph.dot
dot -Tpng graph.dot -o graph.png
```

**Understanding**:
- Install-time cycles are OK (both packages can be built first, then installed together)
- Build-time cycles are problematic (can't build A without B, can't build B without A)

**Solutions**:
- Check if one dependency should be marked as prebuilt
- Check if dependency is actually needed (sometimes test deps leak into install deps)
- Use override to remove circular dependency:
  ```python
  def get_install_dependencies_of_wheel(req, wheel_filename):
      deps = default_get_install_dependencies_of_wheel(req, wheel_filename)
      # Remove problematic dependency
      return {d for d in deps if d.name != "circular-dep"}
  ```

### Problem: Package not found in local repository

**Symptoms**:
```
ERROR: Could not find a version that satisfies the requirement mypackage (from versions: none)
```

**Debugging**:
```bash
# Check if package was built
ls wheels-repo/simple/mypackage/

# Check if server is running
curl http://localhost:8000/simple/mypackage/

# Check dependency graph
jq '.[] | select(.canonicalized_name == "mypackage")' work-dir/graph.json

# Verify wheel exists
ls wheels-repo/downloads/*.whl | grep mypackage
```

**Causes**:
1. Package hasn't been built yet
2. Build failed silently
3. Server hasn't been updated
4. Name canonicalization mismatch

**Solutions**:
- Build manually: `fromager build mypackage 1.0.0`
- Check build logs: `ls work-dir/logs/build-mypackage-*.log`
- Restart bootstrap from clean state

### Problem: Wrong version selected

**Symptoms**:
```
Expected mypackage==2.0.0 but got 1.5.0
```

**Debugging**:
```bash
# Check what constraints are applied
grep mypackage work-dir/constraints.txt

# Check previous graph
jq '.[] | select(.canonicalized_name == "mypackage")' work-dir/graph.json

# Check with verbose logging
fromager -v step --step resolve mypackage
```

**Causes**:
1. Constraint limits version
2. Previous bootstrap cached different version
3. Override changes resolution
4. Requirement specifier is wrong

**Solutions**:
- Clear work-dir and rebuild: `rm -rf work-dir && fromager bootstrap ...`
- Don't use previous graph: Remove `--previous-bootstrap-file` option
- Check for overrides: `fromager list-overrides`
- Adjust constraints or requirements

### Problem: Patch fails to apply

**Symptoms**:
```
ERROR: Failed to apply patch 0001-fix.patch to mypackage
```

**Debugging**:
```bash
# Check patch file
cat overrides/patches/mypackage-1.0.0/0001-fix.patch

# Try applying manually
cd work-dir/mypackage-1.0.0/mypackage-1.0.0
patch -p1 < /path/to/0001-fix.patch

# Check if source structure changed
ls -la work-dir/mypackage-1.0.0/mypackage-1.0.0/
```

**Causes**:
1. Patch is for different version
2. Source structure changed
3. Patch already applied upstream
4. Wrong patch format

**Solutions**:
- Update patch for new version:
  ```bash
  # Extract source
  cd work-dir/mypackage-1.0.0/mypackage-1.0.0
  
  # Make changes
  # ...
  
  # Generate new patch
  git diff > /path/to/0001-fix.patch
  ```
- Use versioned patches: Create `overrides/patches/mypackage-1.0.0/` directory
- Remove patch if no longer needed

### Problem: Build environment issues

**Symptoms**:
```
ERROR: Command '['uv', 'pip', 'install', ...]' returned non-zero exit status 1
```

**Debugging**:
```bash
# Check virtualenv was created
ls work-dir/mypackage-1.0.0/build-3.*/

# Try installing dependencies manually
work-dir/mypackage-1.0.0/build-3.*/bin/pip list

# Check uv cache
ls work-dir/uv-cache/

# Test uv directly
uv pip install --index-url http://localhost:8000/simple/ mypackage
```

**Causes**:
1. uv not installed or wrong version
2. Network issues reaching local server
3. Dependency not available in local repo
4. System library missing

**Solutions**:
- Install/upgrade uv: `pip install -U uv`
- Check server is running: `curl http://localhost:8000/simple/`
- Build missing dependency first
- Install system dependencies

### Problem: Network isolation failures

**Symptoms**:
```
ERROR: network isolation is not available: ...
```

**Debugging**:
```bash
# Check if unshare is available
which unshare

# Test unshare manually
unshare -rn /bin/true

# Check kernel capabilities
capsh --print
```

**Causes**:
1. Running in Docker without proper capabilities
2. Platform doesn't support unshare (macOS, Windows)
3. Missing user namespaces

**Solutions**:
- Disable network isolation: `fromager --no-network-isolation bootstrap ...`
- Use Podman instead of Docker
- Enable user namespaces: `sysctl -w kernel.unprivileged_userns_clone=1`

## Debugging Your Changes

### Adding Debug Logging

**Use the logger with context**:
```python
import logging
from .log import req_ctxvar_context

logger = logging.getLogger(__name__)

def my_function(ctx, req):
    # Context manager adds req name to all logs
    with req_ctxvar_context(req):
        logger.debug(f"Processing {req.name}")
        logger.info(f"Important information: {some_value}")
        logger.error(f"Something went wrong: {error}")
```

**Log levels**:
- `DEBUG`: Detailed information for diagnosis
- `INFO`: Confirmation that things are working
- `WARNING`: Something unexpected but handled
- `ERROR`: Serious problem, operation failed

**When to log**:
- Entry to major functions (DEBUG)
- Decision points (DEBUG or INFO)
- External calls (DEBUG)
- Errors with context (ERROR)
- User-visible operations (INFO)

### Using Assertions

**Add assertions for invariants**:
```python
def add_dependency(self, parent_key, child_node):
    assert parent_key in self.nodes, f"Parent {parent_key} must exist before adding child"
    assert child_node is not None, "Child node cannot be None"
    # ... rest of function
```

**Run with assertions enabled**:
```bash
python -O -m fromager bootstrap mypackage  # Assertions disabled
python -m fromager bootstrap mypackage     # Assertions enabled (default)
```

### Unit Testing Your Changes

**Run specific test**:
```bash
hatch run test:test tests/test_mymodule.py::test_my_function
```

**Run with coverage**:
```bash
hatch run test:test tests/test_mymodule.py
hatch run test:coverage-report
```

**Run with verbose output**:
```bash
hatch run test:test -vv tests/test_mymodule.py
```

**Run with debugging**:
```bash
hatch run test:test --pdb tests/test_mymodule.py
```

**Add test output**:
```python
def test_my_function(capsys):
    result = my_function()
    captured = capsys.readouterr()
    print(f"Output: {captured.out}")
    assert result == expected
```

### Integration Testing with E2E Tests

**Run single e2e test**:
```bash
cd e2e
./test_bootstrap.sh
```

**Run with debugging**:
```bash
cd e2e
set -x  # Enable bash debugging
./test_bootstrap.sh
```

**Create minimal test case**:
```bash
# Create new e2e test
cat > e2e/test_my_feature.sh << 'EOF'
#!/bin/bash
set -e
set -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${SCRIPT_DIR}/common.sh"

# Your test here
fromager bootstrap simple-package
# Check result
test -f wheels-repo/simple/simple-package/simple_package-1.0.0-py3-none-any.whl
echo "PASS"
EOF

chmod +x e2e/test_my_feature.sh
./e2e/test_my_feature.sh
```

### Profiling Performance

**Time specific operations**:
```bash
time fromager bootstrap mypackage
```

**Profile with cProfile**:
```bash
python -m cProfile -o profile.stats -m fromager bootstrap mypackage

# Analyze profile
python -m pstats profile.stats
>>> sort cumulative
>>> stats 20
```

**Use fromager's built-in metrics**:
```bash
fromager bootstrap mypackage
fromager stats

# Shows timing breakdown per package and operation
```

**Add custom timing**:
```python
from . import metrics

@metrics.timeit(description="my custom operation")
def my_function(ctx, req):
    # Function body
    pass
```

## Debugging Production Issues

### Reproducing User Issues

**Get full environment details**:
```bash
# Ask user to run
fromager --version
python --version
pip list
uname -a

# And provide their command
echo "fromager bootstrap ..."
```

**Reproduce with same inputs**:
```bash
# Use their requirements file
fromager bootstrap -r their-requirements.txt

# Use their constraints
fromager -c their-constraints.txt bootstrap ...

# Use their settings
cp -r their-overrides/ overrides/
fromager --settings-dir=overrides/settings bootstrap ...
```

**Create minimal reproducible example**:
```bash
# Start with their command
fromager bootstrap packageA packageB packageC

# Remove packages one by one until issue disappears
fromager bootstrap packageA packageB  # Still fails?
fromager bootstrap packageA           # Still fails?

# Now you know packageA triggers the issue
```

### Reading Crash Traces

**Python traceback**:
```
Traceback (most recent call last):
  File "fromager/__main__.py", line 281, in invoke_main
    main(auto_envvar_prefix="FROMAGER")
  File "click/core.py", line 1157, in __call__
    return self.main(*args, **kwargs)
  ...
  File "fromager/bootstrapper.py", line 145, in _add_to_graph
    self.ctx.dependency_graph.add_dependency(
  File "fromager/dependency_graph.py", line 264, in add_dependency
    raise ValueError(
ValueError: Trying to add requests==2.31.0 to parent setuptools==68.0.0 but setuptools==68.0.0 does not exist
```

**Reading from bottom to top**:
1. **Error message**: "setuptools==68.0.0 does not exist"
2. **Error location**: `dependency_graph.py` line 264
3. **Call context**: Called from `bootstrapper.py` line 145 in `_add_to_graph`
4. **Root cause**: Trying to add dependency before parent exists

**Debugging strategy**:
```python
# Add logging in bootstrapper.py around line 145
logger.debug(f"Available nodes: {list(self.ctx.dependency_graph.nodes.keys())}")
logger.debug(f"Trying to add child to parent: {parent_key}")
```

### Remote Debugging

**Enable remote debugging** with `debugpy`:
```python
# Add to __main__.py
import debugpy
debugpy.listen(5678)
print("Waiting for debugger...")
debugpy.wait_for_client()
```

**Connect from VS Code**:
```json
{
    "name": "Attach to Fromager",
    "type": "python",
    "request": "attach",
    "connect": {
        "host": "localhost",
        "port": 5678
    }
}
```

## Advanced Debugging Techniques

### Using strace to Debug System Calls

**Trace file access**:
```bash
strace -e openat,stat fromager bootstrap mypackage 2>&1 | grep pyproject.toml
```

**Trace network calls**:
```bash
strace -e socket,connect,sendto,recvfrom fromager bootstrap mypackage
```

**Trace subprocess execution**:
```bash
strace -e execve -f fromager bootstrap mypackage 2>&1 | grep python
```

### Using lsof to Debug File Locks

**Check what files are open**:
```bash
# In another terminal while fromager is running
lsof | grep fromager
lsof | grep work-dir
```

### Memory Profiling

**Use memory_profiler**:
```bash
pip install memory_profiler

# Add decorator to function
@profile
def my_function():
    pass

# Run with profiler
python -m memory_profiler -m fromager bootstrap mypackage
```

**Track memory over time**:
```bash
# Run in background
fromager bootstrap mypackage &
PID=$!

# Monitor memory
while kill -0 $PID 2>/dev/null; do
    ps aux | grep $PID | grep -v grep
    sleep 5
done
```

### Debugging Parallel Builds

**Issues with parallel builds**:
- Race conditions
- Shared resource conflicts
- Deadlocks

**Debugging approach**:
```bash
# First, reproduce with serial builds
fromager -j 1 bootstrap mypackage

# If that works, it's a concurrency issue
# Enable thread debugging
import threading
threading.current_thread().name  # Add to logs

# Use thread-safe logging
logger.debug(f"[{threading.current_thread().name}] Processing {req.name}")
```

**Check for race conditions**:
```python
# Add threading.Lock to shared resources
import threading

class MyClass:
    def __init__(self):
        self._lock = threading.Lock()
        self._shared_state = {}
    
    def update_state(self, key, value):
        with self._lock:
            self._shared_state[key] = value
```

## Getting Help

### Providing Debug Information

When asking for help, provide:

1. **Fromager version**: `fromager --version`
2. **Python version**: `python --version`
3. **Command run**: Full fromager command with options
4. **Error output**: Complete error message with traceback
5. **Debug log**: Attach debug.log from `--log-file=debug.log`
6. **Environment**: OS, container/VM, relevant env vars
7. **Reproducibility**: Minimal example that reproduces issue

### Creating a Bug Report

```markdown
## Description
Brief description of the problem

## Steps to Reproduce
1. Create requirements.txt with X
2. Run `fromager bootstrap -r requirements.txt`
3. Error occurs

## Expected Behavior
Should successfully build all packages

## Actual Behavior
Fails with "ERROR: ..."

## Environment
- Fromager version: 0.100.0
- Python version: 3.12
- OS: Ubuntu 22.04
- Install method: pip install fromager

## Logs
Attached:
- debug.log
- build-mypackage-1.0.0.log

## Additional Context
Works fine with fromager 0.99.0
```

## Tools and Configuration

### VS Code Configuration

**`.vscode/launch.json`**:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug Bootstrap",
            "type": "python",
            "request": "launch",
            "module": "fromager",
            "args": [
                "bootstrap",
                "requests"
            ],
            "console": "integratedTerminal",
            "justMyCode": false
        },
        {
            "name": "Debug Step",
            "type": "python",
            "request": "launch",
            "module": "fromager",
            "args": [
                "step",
                "--step",
                "resolve",
                "requests"
            ],
            "console": "integratedTerminal"
        }
    ]
}
```

### Git Bisect for Regressions

**Find when bug was introduced**:
```bash
# Start bisect
git bisect start

# Mark current as bad
git bisect bad

# Mark known good version
git bisect good v0.99.0

# Git will checkout middle commit
# Test it
hatch run test:test tests/test_mymodule.py

# Mark as good or bad
git bisect good  # or git bisect bad

# Repeat until found
# When done
git bisect reset
```

## Summary: Debugging Workflow

When debugging an issue:

1. **Reproduce**: Get minimal reproducible case
2. **Isolate**: Use `step` command to find which step fails
3. **Log**: Enable verbose logging and examine output
4. **Inspect**: Check generated files (graph, logs, constraints)
5. **Trace**: Add debug logging or use debugger
6. **Test**: Create unit test that reproduces issue
7. **Fix**: Implement solution
8. **Verify**: Run unit tests and e2e tests
9. **Document**: Add comments explaining fix

Remember: Most bugs are either:
- State not initialized (check `__init__` methods)
- Wrong assumption (check assertions and log assumptions)
- Edge case not handled (check conditional logic)
- Concurrency issue (check for shared mutable state)
- External failure (check network, file system, system calls)

Happy debugging!

