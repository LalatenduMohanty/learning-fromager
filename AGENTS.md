# AI Agent Guide for Fromager

This guide is specifically designed for AI agents (like Claude, GPT, etc.) to effectively understand and work with the fromager codebase and this learning repository.

## Prerequisites for AI Agents

Before answering any questions about fromager, you **MUST** first:

1. **Read this entire learning repository** - Start with the documentation in this repo:
   - `README.md` - Complete learning guide with examples
   - `ARCHITECTURE.md` - System design and core concepts
   - `HOW_TO_READ_THE_CODE.md` - Code navigation techniques
   - `DEBUGGING_GUIDE.md` - Troubleshooting approaches
   - `CONTRIBUTING_GUIDE.md` - Development workflow

2. **Explore the fromager source code** - The actual fromager codebase is in the `fromager/` submodule:
   - `fromager/src/fromager/` - Main source code
   - `fromager/docs/` - Official documentation
   - `fromager/tests/` - Test suite
   - `fromager/e2e/` - End-to-end tests

3. **Understand the context** - This is a learning repository that:
   - Contains the fromager source as a git submodule
   - Provides educational materials and examples
   - Focuses on teaching fromager concepts and usage

## Key Fromager Concepts for AI Agents

### Core Architecture
- **Bootstrap Process**: Recursive dependency resolution and building
- **Build Backends**: PEP 517 interface for building packages
- **Dependency Graph**: DAG of package dependencies with build order
- **Override System**: Stevedore plugins for customizing builds
- **Wheel Server**: Local HTTP server for build-time dependencies

### Important Files to Understand
```
fromager/src/fromager/
├── bootstrapper.py      # Main bootstrap logic
├── resolver.py          # Dependency resolution
├── wheels.py           # Wheel building (PEP 517)
├── sources.py          # Source acquisition and patching
├── dependencies.py     # Dependency extraction
├── overrides.py        # Plugin system
├── packagesettings.py  # Configuration management
├── server.py           # Local wheel server
└── commands/           # CLI commands
```

### Key Python Packaging Standards
- **PEP 427**: Wheel format
- **PEP 517**: Build system interface
- **PEP 518**: pyproject.toml format
- **PEP 503**: Simple repository API
- **PEP 658**: Metadata files

## Guidelines for AI Agents

### When Answering Questions

1. **Always reference the source code** when explaining how something works
2. **Cite specific files and line numbers** when possible
3. **Use the learning materials** in this repo to provide context
4. **Prioritize readability** - Clear, concise explanations are more important than comprehensive coverage
5. **Avoid emojis in documentation** - Keep all documentation professional and emoji-free
6. **Follow strict formatting standards** - See detailed formatting guidelines below
7. **Distinguish between**:
   - User-facing concepts (from README.md)
   - Technical implementation (from source code)
   - Architecture patterns (from ARCHITECTURE.md)

### Code Analysis Approach

1. **Start with the entry points**: Look at `commands/` for CLI interfaces
2. **Follow the data flow**: Trace from commands → bootstrapper → resolver → builders
3. **Understand the plugin system**: Check `overrides.py` and stevedore integration
4. **Check test cases**: Use `tests/` and `e2e/` for real-world examples

### Documentation Formatting Standards

**CRITICAL**: Always maintain clean, professional formatting in all documentation files. Poor formatting creates maintenance burden and reduces readability.

#### Whitespace Rules

1. **No trailing whitespace**: Never leave spaces or tabs at the end of lines
   ```bash
   # BAD - line ends with spaces
   This is a line with trailing spaces

   # GOOD - line ends cleanly
   This is a line with no trailing spaces
   ```

2. **No whitespace-only blank lines**: Empty lines must be completely empty
   ```bash
   # BAD - blank line contains spaces/tabs
   Line 1

   Line 3

   # GOOD - blank line is truly empty
   Line 1

   Line 3
   ```

3. **Consistent indentation**: Use spaces only, no mixed tabs and spaces
   ```bash
   # BAD - mixing tabs and spaces
   - Item 1
   	  - Subitem (tab + spaces)

   # GOOD - spaces only
   - Item 1
     - Subitem (spaces only)
   ```

#### Line Ending Standards

1. **End files with newline**: All files must end with a single newline character
2. **Use Unix line endings (LF)**: Not Windows (CRLF) or old Mac (CR)
3. **No multiple consecutive blank lines**: Maximum of one blank line between sections

#### Markdown Formatting

1. **Code blocks**: Always specify language for syntax highlighting
   ```markdown
   # BAD - no language specified
   ```
   some code here
   ```

   # GOOD - language specified
   ```python
   def example_function():
       return "hello"
   ```
   ```

2. **Lists**: Use consistent bullet style and indentation
   ```markdown
   # BAD - inconsistent bullets and indentation
   - Item 1
   * Item 2
      - Subitem with wrong indentation

   # GOOD - consistent style
   - Item 1
   - Item 2
     - Subitem with correct indentation
   ```

3. **Headers**: Use proper hierarchy and spacing
   ```markdown
   # BAD - inconsistent spacing
   ##Header without space
   ### Another header


   ####Too many blank lines above

   # GOOD - consistent spacing
   ## Header with space
   ### Another header

   #### Proper spacing above
   ```

#### Quality Checks

Before submitting any documentation changes:

1. **Remove trailing whitespace**: Use `sed -i 's/[ \t]*$//' filename.md`
2. **Check for mixed indentation**: Use `grep -P "^\t+ " filename.md`
3. **Verify blank lines**: Use `grep -n "^[ \t]\+$" filename.md`
4. **Validate markdown**: Use a markdown linter if available

#### Common Formatting Mistakes to Avoid

1. **Trailing spaces after bullet points**
2. **Inconsistent code block indentation**
3. **Mixed tab/space indentation in lists**
4. **Missing newlines at end of files**
5. **Whitespace-only lines in code examples**
6. **Inconsistent header spacing**

**Remember**: Clean formatting is not optional - it's a professional standard that makes documentation maintainable and readable.

### Common Pitfalls to Avoid

1. **Don't confuse package names with override names**:
   - Package: `scikit-learn`
   - Override: `scikit_learn` (hyphens → underscores)

2. **Don't mix up dependency types**:
   - Build-system deps (pyproject.toml `[build-system] requires`)
   - Build-backend deps (from PEP 517 hooks)
   - Install deps (from wheel metadata)

3. **Don't assume simple pip behavior**:
   - Fromager builds everything from source
   - Uses isolated build environments
   - Maintains local wheel repositories

### Useful Search Patterns

When exploring the codebase, look for:
- `@click.command()` - CLI command definitions
- `def bootstrap(` - Main bootstrap logic
- `pep517_` - PEP 517 build interface usage
- `stevedore` - Plugin system integration
- `Requirement` - Package requirement handling
- `WorkContext` - Central state object

## Example Analysis Workflow

When asked about a fromager feature:

1. **Check the learning docs first**: Does README.md or ARCHITECTURE.md explain it?
2. **Find the CLI command**: Look in `commands/` for the user interface
3. **Trace the implementation**: Follow the code path through the main modules
4. **Check for tests**: Look for test cases that demonstrate the feature
5. **Provide comprehensive answer**: Include both user perspective and technical details

## Repository Structure Reference

```
learning-fromager/           # This learning repository
├── README.md               # Main learning guide
├── GLOSSARY.md             # Terminology reference
├── ARCHITECTURE.md         # System design
├── HOW_TO_READ_THE_CODE.md # Code navigation
├── DEBUGGING_GUIDE.md      # Troubleshooting
├── CONTRIBUTING_GUIDE.md   # Development guide
├── AGENTS.md              # This file
├── examples/              # Learning examples
├── setup.sh              # Environment setup
└── fromager/             # Git submodule → actual fromager source
    ├── src/fromager/     # Main source code
    ├── docs/            # Official documentation
    ├── tests/           # Test suite
    └── e2e/             # End-to-end tests
```

## Getting Started Checklist for AI Agents

- [ ] Read README.md completely
- [ ] Review GLOSSARY.md for key terminology
- [ ] Understand ARCHITECTURE.md concepts
- [ ] Browse HOW_TO_READ_THE_CODE.md techniques
- [ ] Explore fromager/src/fromager/ source structure
- [ ] Check fromager/docs/ for official documentation
- [ ] Look at fromager/tests/ for usage examples
- [ ] Review examples/ directory in this repo
- [ ] Understand the git submodule relationship

## Questions to Ask Yourself

Before answering any fromager question:

1. Have I read the relevant documentation in this learning repo?
2. Have I checked the actual source code in the fromager submodule?
3. Do I understand the difference between user-facing and implementation details?
4. Can I provide specific file/line references?
5. Am I explaining concepts in a way that matches the learning materials?

---

**Remember**: This learning repository exists to make fromager more accessible. Your role as an AI agent is to bridge the gap between the comprehensive source code and users who want to understand and use fromager effectively.
