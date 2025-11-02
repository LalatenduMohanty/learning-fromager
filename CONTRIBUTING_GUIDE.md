# Contributing to Fromager: From User to Developer

This guide helps you transition from **using** fromager to **contributing** code to the project. It's designed to work alongside our other documentation:

- **[README](README.md)** → Learn to use fromager (start here)
- **[Architecture Guide](ARCHITECTURE.md)** → Understand system design
- **[How to Read the Code](HOW_TO_READ_THE_CODE.md)** → Navigate the codebase
- **[Debugging Guide](DEBUGGING_GUIDE.md)** → Troubleshoot issues
- **This guide** → Make your first contribution

## Prerequisites

Before diving into contributions, you should be comfortable with:

- **Using fromager**: Completed the examples in this repository's README
- **Python packaging**: Understanding of wheels, sdists, PEP 517, and dependency resolution
- **Git workflows**: Branching, pull requests, and collaborative development
- **Testing**: Writing unit tests and understanding test-driven development

If you need to brush up on any of these, see:
- [How to Read the Code](HOW_TO_READ_THE_CODE.md) - Understanding the codebase structure
- [Architecture Guide](ARCHITECTURE.md) - High-level system design
- [Debugging Guide](DEBUGGING_GUIDE.md) - Troubleshooting and development tools

## Your First Contribution: A Self-Paced Learning Path

This learning path is designed to be **self-paced** - take as much time as you need for each step. Some developers may complete this in a few days, others may take weeks or months. The important thing is to understand each concept thoroughly before moving to the next step.

**Estimated time commitment**: 
- **Beginner**: 2-4 weeks (1-2 hours per day)
- **Experienced**: 1-2 weeks (2-3 hours per day)
- **Expert**: 3-5 days (focused learning)

Feel free to skip steps you're already comfortable with or spend extra time on areas that interest you most.

### Phase 1: Environment Setup and Code Exploration

**Step 1: Development Environment**

```bash
# Fork and clone fromager
git clone https://github.com/YOUR-USERNAME/fromager.git
cd fromager

# Install for development
pip install -e ".[dev,test,docs]"

# Verify setup
fromager --version
hatch run test:test
```

**Step 2: Understand the Entry Points**

Start with the simplest command to understand the pattern:

```bash
# Find command registration
grep -A 5 "canonicalize" pyproject.toml

# Trace: CLI → commands/canonicalize.py → WorkContext flow
```

**Key insight**: All commands receive `WorkContext` via `@click.pass_obj` - this is your gateway to understanding the system.

**Step 3: Follow One Complete Flow**

Pick a package you know (like `click`) and trace it through `bootstrap`:

```bash
# Enable verbose logging to see the flow
fromager -v bootstrap click

2. **Follow the code path**:
   ```python
   # src/fromager/commands/canonicalize.py
   @click.command()
   @click.argument("name", nargs=-1)
   @click.pass_obj
   def canonicalize(wkctx: context.WorkContext, name: tuple[str, ...]) -> None:
       for n in name:
           print(canonicalize_name(n))
   ```

3. **Understand the pattern**:
   - Commands receive `WorkContext` via `@click.pass_obj`
   - Simple commands don't need complex state management
   - Most logic delegates to utility functions

**Step 3: Trace Through Bootstrap Flow**

Follow a simple package through the bootstrap process:

1. **Start with the command**: `src/fromager/commands/bootstrap.py`
2. **Follow to orchestrator**: `src/fromager/bootstrapper.py`
3. **Understand key methods**:
   - `bootstrap()` - main entry point
   - `resolve_version()` - version selection
   - `_download_and_unpack_source()` - source acquisition
   - `_handle_build_requirements()` - dependency processing

### Phase 2: Understanding Core Systems

**Step 4: Dependency Graph System**

The dependency graph is central to fromager's operation:

1. **Study the data structures** in `src/fromager/dependency_graph.py`:
   ```python
   # Key classes to understand
   class DependencyNode:    # Represents a package version
   class DependencyEdge:    # Represents a dependency relationship
   class DependencyGraph:   # The graph itself
   ```

2. **Understand edge types**:
   - `install`: Runtime dependencies
   - `build-system`: PEP 517 build-system requirements
   - `build-backend`: Additional build dependencies
   - `toplevel`: User-specified requirements

3. **Practice with the graph**:
   ```bash
   # Bootstrap a package and examine the graph
   fromager bootstrap requests
   
   # Look at the generated graph
   python -c "
   import json
   with open('work-dir/graph.json') as f:
       graph = json.load(f)
   for key, node in graph.items():
       print(f'{key}: {len(node.get(\"edges\", []))} dependencies')
   "
   ```

**Step 5: Version Resolution**

Understanding how fromager selects package versions:

1. **Study the resolver** in `src/fromager/resolver.py`:
   - `PyPIProvider`: Standard PyPI resolution
   - `GitHubTagProvider`: GitHub release resolution
   - `GitLabTagProvider`: GitLab release resolution

2. **Understand constraints** in `src/fromager/constraints.py`:
   - How version constraints are applied
   - Interaction with requirements

3. **Test resolution manually**:
   ```bash
   # Use the step command to see resolution in action
   fromager step --step resolve "requests>=2.28.0"
   
   # With constraints
   echo "requests<2.32.0" > constraints.txt
   fromager -c constraints.txt step --step resolve "requests>=2.28.0"
   ```

**Step 6: Build System**

How fromager builds packages:

1. **Study build environments** in `src/fromager/build_environment.py`:
   - Virtual environment creation
   - Dependency installation with uv
   - Command execution with isolation

2. **Understand wheel building** in `src/fromager/wheels.py`:
   - PEP 517 build process
   - Metadata extraction and enhancement
   - ELF dependency analysis

3. **Practice building**:
   ```bash
   # Build a single package step by step
   fromager step --step download click==8.1.0
   fromager step --step build-system-dependencies click==8.1.0
   fromager step --step build-wheel click==8.1.0
   ```

### Phase 3: Customization and Extension Systems

**Step 7: Override System**

Fromager's plugin architecture for package-specific customization:

1. **Study the override system** in `src/fromager/overrides.py`:
   - How overrides are discovered via stevedore
   - Method invocation with argument filtering
   - Available override points

2. **Create a simple override**:
   ```python
   # Create test-overrides/package_plugins/mytest.py
   def resolve_source(ctx, req, sdist_server_url, req_type):
       from packaging.version import Version
       return "https://example.com/mytest-1.0.tar.gz", Version("1.0")
   
   # Create test-overrides/setup.py
   from setuptools import setup, find_packages
   setup(
       name="test-overrides",
       packages=find_packages(),
       entry_points={
           "fromager.project_overrides": [
               "mytest = package_plugins.mytest"
           ]
       }
   )
   
   # Install and test
   pip install -e test-overrides/
   fromager step --step resolve mytest
   ```

3. **Study existing overrides** in the main repository's `e2e/` directory.

**Step 8: Settings System**

YAML-based configuration for packages:

1. **Study package settings** in `src/fromager/packagesettings.py`:
   - Pydantic models for validation
   - Inheritance hierarchy (global → package → variant)
   - Template substitution in URLs

2. **Create and test settings**:
   ```yaml
   # overrides/settings/mypackage.yaml
   download_source:
     url: "https://custom.example.com/${canonicalized_name}-${version}.tar.gz"
   env:
     CUSTOM_BUILD_FLAG: "1"
   variants:
     debug:
       env:
         DEBUG: "1"
   ```

3. **Understand the settings loading process** in `WorkContext.package_build_info()`.

**Step 9: Hook System**

Event-driven extensions for cross-cutting concerns:

1. **Study the hook system** in `src/fromager/hooks.py`:
   - Available hook points
   - Multiple plugins per hook
   - Hook invocation patterns

2. **Create a simple hook**:
   ```python
   # Create test-hooks/hook_plugins/myhook.py
   def post_build(ctx, req, dist_name, dist_version, sdist_filename, wheel_filename):
       print(f"Built {dist_name} {dist_version}")
       # Could add custom metadata, run security scans, etc.
   
   # Register in setup.py
   entry_points={
       "fromager.hooks": [
           "myhook = hook_plugins.myhook"
       ]
   }
   ```

### Phase 4: Making Your First Contribution

**Step 10: Identify a Contribution Opportunity**

Good first contributions include:

1. **Documentation improvements**:
   - Fix typos or unclear explanations
   - Add examples for existing features
   - Improve error messages

2. **Small feature additions**:
   - New command-line options
   - Additional package settings
   - Enhanced logging or debugging output

3. **Bug fixes**:
   - Check the issue tracker for "good first issue" labels
   - Reproduce reported bugs
   - Fix issues you've encountered while learning

4. **Test improvements**:
   - Add test coverage for untested code paths
   - Create regression tests for fixed bugs
   - Improve test documentation

**Step 11: Implement Your Contribution**

1. **Create a focused branch**:
   ```bash
   git checkout -b fix-issue-123
   # or
   git checkout -b add-new-command
   ```

2. **Follow the development workflow**:
   - Write tests first (TDD approach)
   - Implement the minimal change needed
   - Ensure all tests pass
   - Update documentation if needed

3. **Example: Adding a new command option**:
   ```python
   # In src/fromager/commands/bootstrap.py
   @click.option(
       "--my-new-option",
       is_flag=True,
       help="Enable my new feature"
   )
   def bootstrap(wkctx, my_new_option, ...):
       if my_new_option:
           # Implement new behavior
           pass
   ```

4. **Test your changes**:
   ```bash
   # Run unit tests
   hatch run test:test tests/test_commands.py
   
   # Run integration tests
   ./e2e/test_bootstrap.sh
   
   # Test manually
   fromager --help
   fromager bootstrap --my-new-option mypackage
   ```

**Step 12: Submit and Iterate**

1. **Prepare your pull request**:
   ```bash
   # Ensure clean commit history
   git log --oneline
   
   # Push to your fork
   git push origin fix-issue-123
   ```

2. **Write a good PR description**:
   ```markdown
   ## Summary
   Brief description of what this PR does and why.
   
   ## Changes
   - Added new command option `--my-new-option`
   - Updated help text and documentation
   - Added unit tests for new functionality
   
   ## Testing
   - All existing tests pass
   - Added new test cases in `tests/test_commands.py`
   - Manually tested with various packages
   
   ## Related Issues
   Fixes #123
   ```

3. **Respond to code review**:
   - Address feedback promptly
   - Ask questions if requirements are unclear
   - Make requested changes in additional commits
   - Thank reviewers for their time

## Common Contribution Patterns

### Adding a New Command

Commands are the primary user interface to fromager. Here's how to add one:

1. **Create the command module**:
   ```python
   # src/fromager/commands/mycommand.py
   import click
   from .. import context
   
   @click.command()
   @click.option("--my-option", help="Description of option")
   @click.argument("package_name")
   @click.pass_obj
   def mycommand(
       wkctx: context.WorkContext,
       my_option: str | None,
       package_name: str,
   ) -> None:
       """Brief description of what this command does."""
       # Implementation here
       print(f"Processing {package_name} with option {my_option}")
   ```

2. **Register the command**:
   ```toml
   # In pyproject.toml
   [project.entry-points."fromager.cli"]
   mycommand = "fromager.commands.mycommand:mycommand"
   ```

3. **Add to command list**:
   ```python
   # In src/fromager/commands/__init__.py
   from .mycommand import mycommand
   
   commands = [
       # ... existing commands
       mycommand,
   ]
   ```

4. **Write tests**:
   ```python
   # In tests/test_commands.py
   from click.testing import CliRunner
   from fromager.commands.mycommand import mycommand
   
   def test_mycommand():
       runner = CliRunner()
       result = runner.invoke(mycommand, ['test-package'])
       assert result.exit_code == 0
       assert 'Processing test-package' in result.output
   ```

### Adding a New Package Setting

Package settings allow users to customize build behavior via YAML files:

1. **Define the setting in the Pydantic model**:
   ```python
   # In src/fromager/packagesettings.py
   class PerPackage(BaseModel):
       # ... existing fields
       my_new_setting: bool = False
       my_complex_setting: dict[str, str] = Field(default_factory=dict)
   ```

2. **Add to PackageBuildInfo**:
   ```python
   # In src/fromager/packagesettings.py
   class PackageBuildInfo:
       @property
       def my_new_setting(self) -> bool:
           # Check variant first, then package, then global
           if self._per_package.variants and self._variant in self._per_package.variants:
               variant_setting = self._per_package.variants[self._variant].my_new_setting
               if variant_setting is not None:
                   return variant_setting
           if self._per_package.my_new_setting is not None:
               return self._per_package.my_new_setting
           return self._global_cfg.my_new_setting
   ```

3. **Use in the codebase**:
   ```python
   # Anywhere you need the setting
   pbi = ctx.package_build_info(req)
   if pbi.my_new_setting:
       # Custom behavior
       pass
   ```

4. **Document the setting**:
   ```yaml
   # In docs/config-reference.rst or example files
   my_new_setting: true  # Enable custom behavior
   my_complex_setting:
     key1: value1
     key2: value2
   ```

### Adding a New Override Point

Override points allow plugins to customize specific behaviors:

1. **Identify where the override should be called**:
   ```python
   # In the relevant module (e.g., src/fromager/sources.py)
   def my_function(ctx, req, ...):
       # Allow override
       result = overrides.find_and_invoke(
           req.name,
           "my_function",  # Override method name
           default_my_function,  # Default implementation
           ctx=ctx,
           req=req,
           # ... other parameters
       )
       return result
   ```

2. **Create the default implementation**:
   ```python
   def default_my_function(ctx, req, ...):
       """Default implementation of my_function."""
       # Standard logic here
       return result
   ```

3. **Document the override point**:
   ```python
   # In docs/hooks.rst or similar
   def my_function(ctx, req, ...):
       """
       Override point for customizing my_function behavior.
       
       Args:
           ctx: Work context
           req: Package requirement
           ...: Other parameters
           
       Returns:
           Expected return type
       """
   ```

4. **Create an example override**:
   ```python
   # In e2e test or documentation
   def my_function(ctx, req, ...):
       # Custom logic for specific package
       if req.name == "special-package":
           return custom_result
       # Fall back to default for others
       return default_my_function(ctx, req, ...)
   ```

### Adding a New Hook Point

Hooks allow multiple plugins to respond to events:

1. **Add hook invocation**:
   ```python
   # At the appropriate point in the code
   from . import hooks
   
   # After some operation completes
   hook_mgr = hooks._get_hooks("my_new_hook")
   for ext in hook_mgr:
       try:
           ext.plugin(
               ctx=ctx,
               req=req,
               result=result,
               # ... other context
           )
       except Exception:
           logger.exception(f"Hook {ext.name} failed")
   ```

2. **Document the hook**:
   ```python
   # In docs/hooks.rst
   def my_new_hook(ctx, req, result, ...):
       """
       Called after my_operation completes.
       
       Args:
           ctx: Work context
           req: Package requirement
           result: Operation result
           ...: Other context
       """
   ```

3. **Create example hook implementation**:
   ```python
   # In e2e test directory
   def my_new_hook(ctx, req, result, ...):
       """Example hook that logs operation completion."""
       print(f"Operation completed for {req.name}: {result}")
   ```

## Development Best Practices

### Code Style and Standards

Fromager follows Python best practices:

1. **Type hints**: All functions should have type hints
   ```python
   def my_function(ctx: context.WorkContext, req: Requirement) -> pathlib.Path:
       ...
   ```

2. **Docstrings**: Use Google-style docstrings
   ```python
   def my_function(ctx: context.WorkContext, req: Requirement) -> pathlib.Path:
       """Brief description of what the function does.
       
       Args:
           ctx: Work context containing build configuration
           req: Package requirement to process
           
       Returns:
           Path to the processed result
           
       Raises:
           ValueError: If req is invalid
       """
   ```

3. **Error handling**: Provide informative error messages
   ```python
   if not source_path.exists():
       raise FileNotFoundError(
           f"Source file not found for {req.name} {version}: {source_path}"
       )
   ```

4. **Logging**: Use structured logging with context
   ```python
   import logging
   from .log import req_ctxvar_context
   
   logger = logging.getLogger(__name__)
   
   def my_function(ctx, req):
       with req_ctxvar_context(req):
           logger.debug(f"Processing {req.name}")
           logger.info(f"Important milestone reached")
   ```

### Testing Guidelines

1. **Test coverage**: Aim for high test coverage of new code
   ```bash
   hatch run test:test tests/test_mymodule.py
   hatch run test:coverage-report
   ```

2. **Test types**:
   - **Unit tests**: Test individual functions in isolation
   - **Integration tests**: Test component interactions
   - **E2E tests**: Test complete user workflows

3. **Test structure**:
   ```python
   def test_my_function():
       """Test that my_function handles normal input correctly."""
       # Arrange
       input_value = create_test_input()
       
       # Act
       result = my_function(input_value)
       
       # Assert
       assert result == expected_output
       assert result.some_property == expected_property
   ```

4. **Use fixtures for common setup**:
   ```python
   @pytest.fixture
   def work_context(tmp_path):
       """Create a WorkContext for testing."""
       return context.WorkContext(
           # ... configuration
       )
   
   def test_with_context(work_context):
       result = my_function(work_context, test_req)
       assert result.exists()
   ```

### Performance Considerations

1. **Caching**: Fromager uses extensive caching to avoid redundant work
   - Respect existing cache patterns
   - Add caching for expensive operations
   - Use appropriate cache keys

2. **Parallel execution**: Consider thread safety
   - Use locks for shared mutable state
   - Prefer immutable data structures
   - Test with parallel builds

3. **Memory usage**: Be mindful of memory consumption
   - Don't load large files entirely into memory
   - Clean up temporary files
   - Use generators for large datasets

### Security Considerations

1. **Input validation**: Validate all external inputs
   - Package names and versions
   - URLs and file paths
   - User-provided configuration

2. **Path traversal**: Prevent directory traversal attacks
   ```python
   # Use pathlib for safe path operations
   safe_path = base_dir / user_input
   if not safe_path.is_relative_to(base_dir):
       raise ValueError("Invalid path")
   ```

3. **Command injection**: Sanitize command arguments
   ```python
   # Use subprocess with list arguments, not shell=True
   subprocess.run([command, arg1, arg2], check=True)
   ```

## Advanced Contribution Topics

### Working with the Dependency Graph

The dependency graph is a complex data structure that requires careful handling:

1. **Understanding immutability**: Nodes and edges are frozen dataclasses
   ```python
   # This won't work - nodes are immutable
   node.version = new_version  # AttributeError
   
   # Instead, create a new node
   new_node = DependencyNode(
       canonicalized_name=node.canonicalized_name,
       version=new_version,
       download_url=node.download_url,
       # ... other fields
   )
   ```

2. **Adding relationships safely**:
   ```python
   # Always check parent exists before adding child
   if parent_key not in graph.nodes:
       raise ValueError(f"Parent {parent_key} must exist")
   
   graph.add_dependency(
       parent_name=parent_name,
       parent_version=parent_version,
       req_type=req_type,
       req=req,
       req_version=resolved_version,
   )
   ```

3. **Traversing the graph**:
   ```python
   # Use the provided traversal methods
   install_deps = graph.get_install_dependencies(node_key)
   build_deps = graph.get_dependency_edges(
       node_key, 
       req_types={RequirementType.BUILD_SYSTEM}
   )
   ```

### Extending the Resolver System

Adding support for new package sources:

1. **Create a new provider class**:
   ```python
   class MyCustomProvider(GenericProvider):
       def _find_tags(self, project_name: str) -> list[tuple[str, str]]:
           """Find available versions for project.
           
           Returns:
               List of (tag_name, download_url) tuples
           """
           # Custom logic to find versions
           return [(version, url), ...]
   ```

2. **Register via override**:
   ```python
   def get_resolver_provider(ctx, req, **kwargs):
       if should_use_custom_provider(req):
           return MyCustomProvider(
               constraints=ctx.constraints,
               req_type=kwargs.get('req_type'),
           )
       # Fall back to default
       return default_resolver_provider(ctx, req, **kwargs)
   ```

### Working with Build Environments

Build environments are complex due to isolation requirements:

1. **Understanding the lifecycle**:
   ```python
   # Create environment
   build_env = BuildEnvironment(ctx, package_work_dir)
   
   # Install dependencies
   build_env.install(build_requirements, RequirementType.BUILD_SYSTEM)
   
   # Run build commands
   output = build_env.run(
       ["python", "-m", "build", "--wheel"],
       cwd=source_dir,
       extra_environ={"CUSTOM_VAR": "value"},
   )
   
   # Environment is cleaned up automatically (if configured)
   ```

2. **Adding environment customization**:
   ```python
   # In build_environment.py
   def get_venv_environ(self, template_env: dict | None) -> dict[str, str]:
       venv_environ = {
           "VIRTUAL_ENV": str(self.path),
           "PATH": f"{self.path / 'bin'}:{existing_path}",
           # Add your custom environment variables
           "MY_CUSTOM_VAR": self._get_custom_value(),
       }
       return venv_environ
   ```

### Debugging Complex Issues

When working on fromager, you'll encounter complex issues:

1. **Use the step command for isolation**:
   ```bash
   # Test individual steps
   fromager step --step resolve mypackage
   fromager step --step download mypackage==1.0.0
   fromager step --step build-wheel mypackage==1.0.0
   ```

2. **Enable comprehensive logging**:
   ```bash
   fromager -v --log-file=debug.log bootstrap mypackage
   ```

3. **Use the Python debugger**:
   ```python
   # Add breakpoint in code
   import pdb; pdb.set_trace()
   
   # Run fromager
   python -m fromager bootstrap mypackage
   ```

4. **Analyze generated files**:
   ```bash
   # Examine dependency graph
   jq '.' work-dir/graph.json | less
   
   # Check build logs
   tail -f work-dir/logs/build-mypackage-1.0.0.log
   
   # Inspect build environment
   ls -la work-dir/mypackage-1.0.0/build-*/
   ```

## Getting Help and Support

### Community Resources

1. **GitHub Issues**: For bug reports and feature requests
   - Use issue templates when available
   - Provide minimal reproduction cases
   - Include relevant logs and environment details

2. **Discussions**: For questions and design discussions
   - Search existing discussions first
   - Be specific about your use case
   - Share code examples when helpful

3. **Documentation**: Keep documentation up to date
   - Update docs when adding features
   - Fix documentation bugs you encounter
   - Add examples for complex features

### Code Review Process

1. **Prepare for review**:
   - Write clear commit messages
   - Keep changes focused and atomic
   - Include tests for new functionality
   - Update documentation as needed

2. **Respond to feedback**:
   - Address all reviewer comments
   - Ask for clarification when needed
   - Make requested changes promptly
   - Thank reviewers for their time

3. **Iterate and improve**:
   - Expect multiple rounds of review
   - Learn from feedback for future contributions
   - Help review others' contributions

### Becoming a Long-term Contributor

1. **Start small**: Begin with documentation, tests, or small bug fixes
2. **Learn the domain**: Understand Python packaging deeply
3. **Engage with the community**: Participate in discussions and reviews
4. **Take ownership**: Adopt areas of the codebase you're passionate about
5. **Mentor others**: Help new contributors get started

## Conclusion

Contributing to fromager is a journey from user to developer to maintainer. The codebase is complex but well-structured, with clear patterns and extensive documentation. Start with small contributions, learn the systems gradually, and don't hesitate to ask for help.

The Python packaging ecosystem benefits from tools like fromager that enable reproducible, secure builds from source. Your contributions help make this vision a reality for the entire Python community.

Remember:
- **Quality over quantity**: Better to make one solid contribution than many rushed ones
- **Learn continuously**: The codebase and ecosystem evolve constantly
- **Be patient**: Complex systems take time to understand fully
- **Have fun**: Contributing to open source should be rewarding and enjoyable

Welcome to the fromager contributor community! 🎉

## Additional Resources

- **Official Documentation**: [https://fromager.readthedocs.io/](https://fromager.readthedocs.io/)
- **Source Code**: [https://github.com/python-wheel-build/fromager](https://github.com/python-wheel-build/fromager)
- **Python Packaging Guide**: [https://packaging.python.org/](https://packaging.python.org/)
- **PEP 517**: [https://peps.python.org/pep-0517/](https://peps.python.org/pep-0517/)
- **Stevedore Documentation**: [https://docs.openstack.org/stevedore/](https://docs.openstack.org/stevedore/)

---

*This guide was created to help bridge the gap between using fromager and contributing to its development. If you find areas that need clarification or expansion, please contribute improvements to this document as well!*
