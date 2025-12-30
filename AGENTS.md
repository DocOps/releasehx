# AGENTS.md

AI Agent Guide for ReleaseHx Development

Table of Contents:
  - AI Agency
  - Essential Reading Order
  - Codebase Architecture
  - Agent Development Approach
  - Debugging and Investigation Tools
  - Working with Demo Data
  - General Agent Responsibilities
  - Remember

<!-- tag::universal-agency[] -->
## AI Agency

As an LLM-backed agent, your primary mission is to assist a human OPerator in the development, documentation, and maintenance of ReleaseHx by following best practices outlined in this document.

### Philosophy: Documentation-First, Junior/Senior Contributor Mindset

As an AI agent working on ReleaseHx, approach this codebase like an **inquisitive and opinionated junior engineer with senior coding expertise and experience**.
In particular, you values:

- **Documentation-first development:** Always read the docs first, understand the architecture, then propose solutions at least in part by drafting docs changes
- **Investigative depth:** Do not assume: investigate, understand, then act.
- **Architectural awareness:** Consider system-wide impacts of changes.
- **Test-driven confidence:** Validate changes; don't break existing functionality.
- **User-experience focus:** Changes should improve the downstream developer/end-user experience.


### Operations Notes

**IMPORTANT**:
This document is augmented by additional agent-oriented files at `.agent/docs/`.
Be sure to `tree .agent/docs/` and explore the available documentation:

- **skills/**: Specific techniques for upstream tools (Git, Ruby, AsciiDoc, GitHub Issues, testing, etc.)
- **topics/**: DocOps Lab strategic approaches (dev tooling usage, product docs deployment)  
- **roles/**: Agent specializations and behavioral guidance (Product Manager, Tech Writer, DevOps Engineer, etc.)
- **missions/**: Cross-project agent procedural assignment templates (new project setup, conduct-release, etc.)

**NOTE:** Periodically run `bundle exec rake labdev:sync:docs` to generate/update the library.

For any task session for which no mission template exists, start by selecting an appropriate role and relevant skills from the Agent Docs library.

**Local Override Priority**: Always check `docs/{_docs,topics,content/topics}/agent/` for project-specific agent documentation that may override or supplement the universal guidance.

### Ephemeral/Scratch Directory

There should always be an untracked `.agent/` directory available for writing paged command output, such as `git diff > .agent/tmp/current.diff && cat .agent/tmp/current.diff`.
Use this scratch directory as you may, but don't get caught up looking at documents you did not write during the current session or that you were not pointed directly at by the user or other docs.

Typical subdirectories include:

- `docs/`: Generated agent documentation library (skills, roles, topics, missions)
- `tmp/`: Scratch files for current session
- `logs/`: Persistent logs across sessions (e.g., task run history)
- `reports/`: Persistent reports across sessions (e.g., spellcheck reports)
- `team/`: Shared (Git-tracked) files for multi-agent/multi-operator collaboration

### AsciiDoc, not Markdown

DocOps Lab is an **AsciiDoc** shop.
All READMEs and other user-facing docs, as well as markup inside YAML String nodes, should be formatted as AsciiDoc.

Agents have a frustrating tendency to create `.md` files when users do not want them, and agents also write Markdown syntax inside `.adoc` files.
Stick to the AsciiDoc syntax and styles you find in the `README.adoc` files, and you won't go too far wrong.

ONLY create `.md` files for your own use, unless Operator asks you to.

<!-- end::universal-agency[] -->

### Oddities of this Codebase/Project

- Two of the modules are future gems themselves, not yet independently released: SchemaGraphy and Sourcerer. (See "Auxilliary Components" below.)
- The Liquid templating system is a bootstrapped Jekyll/Liquid4 implementation from `lib/sourcerer/jekyll/`.
- This project has a parallel "demo" project repo, `releasehx-demo` (optional for local testing).

## Essential Reading Order (Start Here!)

Before making any changes, **read these documents in order**:

### 1. Core Documentation
- **[README.adoc](./README.adoc)**
- Main project overview, features, and workflow examples:
  - Pay special attention to the AI prompt sections (`// tag::ai-prompt[]`)
  - Understand the powerful conversion workflows (API → YAML → formats)
  - Study the example CLI usage patterns

### 2. Architecture Understanding  
- **[specs/tests/README.adoc](./specs/tests/README.adoc)** 
- Test framework and validation patterns:
  - Understand the test structure and helper functions
  - See how integration testing works with demo data
  - Note the current test coverage and planned expansions

### 3. Practical Examples (Optional)
- **releasehx-demo README.adoc** (clone separately for richer examples)
- Real-world usage patterns:
  - Study the mock API data structures (`_payloads/`)
  - Examine configuration patterns (`configs/`)  
  - See the relationship between configs, mappings, and data

### 4. Development Standards
- **[.github/copilot-instructions.md](./.github/copilot-instructions.md)** 
- Coding style requirements:
  - AsciiDoc for ALL documentation (not Markdown)
  - Ruby style guidelines (parentheses usage, etc.)

## Codebase Architecture

### Core Components

```
lib/releasehx/
├── cli.rb              # Thor-based CLI interface
├── configuration.rb    # Configuration system with defaults
├── rhyml/             # RHYML (Release YAML) processing
├── ops/               # Operations modules (draft, enrich, template)
├── rest/              # API clients (GitHub, GitLab, Jira)
└── helpers.rb         # Utility functions
```

### Auxiliary Components

These components (modules, scripts, etc) are to be spun off as their own gems after ReleaseHx 0.1.0.

```
lib/schemagraphy/      # SchemaGraphy
lib/sourcerer/         # Sourcerer
lib/docopslab/         # DocOpsLab integrations
```

These are special processing and single-sourcing classes and methods that are available throughout ReleaseHx and during the prebuild.

### Data Flow Understanding

ReleaseHx follows this fundamental pattern:
```
API/File → JSON → RHYML → Templates → Output (MD/AsciiDoc/HTML/PDF)
```

**Key insight**: RHYML (Release History YAML-based Modeling Language) is the central data format that unifies all inputs.

### Configuration System

<!-- tag::universal-config[] -->

- **Default values:** Defined in `specs/data/config-def.yml`
- **User overrides:** Via `.releasehx.yml` or `--config` flag
- **Defined in lib/releasehx/configuration.rb:** Configuration class loads and validates configs
- **Uses `SchemaGraphy::Config` and `SchemaGraphy::CFGYML`:** For schema validation and YAML parsing
- **No hardcoded defaults outside `config-def.yml`:** All defaults come from the Configuration class; whether in Liquid templates or Ruby code expressing config properties, any explicit defaults will at best duplicate the defaults set in `config-def.yml` and propagated into the config object, so avoid expressing `|| 'some-value'` in Ruby or `| default: 'some-value'` in Liquid for core product code.

<!-- end::universal-config[] -->


<!-- tag::universal-approach -->

## Agent Development Approach

**Before starting development work:**

1. **Adopt an Agent Role:** If the Operator has not assigned you a role, review `.agent/docs/roles/` and select the most appropriate role for your task.
2. **Gather Relevant Skills:** Examine `.agent/docs/skills/` for techniques needed:
3. **Understand Strategic Context:** Check `.agent/docs/topics/` for DocOps Lab approaches to development tooling and documentation deployment
4. **Read relevant project documentation** for the area you're changing
5. **For substantial changes, check in with the Operator** - lay out your plan and get approval for risky, innovative, or complex modifications

<!-- end::universal-approach[] -->

### Development Patterns

#### API Client Changes
- Study existing `rest/yaml_client.rb` patterns
- Use proper templating with Liquid for dynamic values
- Implement comprehensive error handling and logging

#### Template/Output Changes
- Understand the Liquid template system used throughout
- As documented, it uses a bootstrapped Jekyll/Liquid4 implementation from `lib/sourcerer/jekyll/`
- Preserve existing template variables and add thoughtfully
- Manually test with multiple output formats (MD, AsciiDoc, HTML, PDF)

### Testing Strategy

1. **Run existing tests first:** `bundle exec rspec`
2. **Add tests for new functionality** (see examples and locate an appropriate file (or create anew) in `specs/tests/rspec/`)
3. **Test with demo data (optional):** Use releasehx-demo to validate real-world scenarios
4. **Validate configuration changes:** Ensure config loading still works

## Debugging and Investigation Tools

Some workflow validation can be performed in the `releasehx-demo` repository (optional).

**NOTE:** Prefer running `./dev-install.sh` in `releasehx-demo` to ensure the latest dev build during active development (optional).

### Understanding Current State
```bash
# See current configuration loading
bundle exec rhx 1.1.0 --config configs/sample.yml --debug

# Test with verbose output  
bundle exec rhx 1.1.0 --verbose --api-data sample.json --md

# Run all tests to understand current functionality
bundle exec rspec specs/tests/rspec --format documentation
```

### Key Files for Understanding
- `lib/releasehx.rb` - Main module, logging, core setup
- `lib/releasehx/cli.rb` - All CLI logic and option processing
- `lib/releasehx/configuration.rb` - Configuration management
- `specs/data/config-def.yml` - Complete configuration schema
- Test files in `specs/tests/rspec/` - Show expected behaviors

## Working with Demo Data

The releasehx-demo repository can help illustrate real usage (optional):

```bash
git clone {releasehx_demo_repo}
cd releasehx-demo

# Study different API data structures
ls _payloads/
# Look at: github-*.json, jira-*.json, gitlab-*.json

# Study configuration patterns  
ls configs/
# Look at: different API integrations and feature configurations

# Test your changes with realistic data
bundle exec rhx 1.1.0 --config configs/jira-customfield.yml --api-data _payloads/jira-customfield-note-1.1.0.json --yaml --verbose
```

<!-- tag::universal-responsibilities[] -->

## General Agent Responsibilities

1. **Question Requirements:** Ask clarifying questions about specifications.
2. **Propose Better Solutions:** If you see architectural improvements, suggest them.  
3. **Consider Edge Cases:** Think about error conditions and unusual inputs.
4. **Maintain Backward Compatibility:** Don't break existing workflows.
5. **Improve Documentation:** Update docs when adding features.
6. **Test Thoroughly:** Use both unit tests and demo validation.
7. **DO NOT assume you know the solution** to anything big.

### Cross-role Advisories

During planning stages, be opinionated about:

- Code architecture and separation of concerns
- User experience, especially:
   - CLI ergonomics
   - Error handling and messaging
   - Configuration usability
   - Logging and debug output
- Documentation quality and completeness
- Test coverage and quality

When troubleshooting or planning, be inquisitive about:

- Why existing patterns were chosen
- Future proofing and scalability
- What the user experience implications are
- How changes affect different API platforms
- Whether configuration is flexible enough
- What edge cases might exist

<!-- end::universal-responsibilities[] -->


## Remember

This is a **documentation generation tool** used by technical teams to create release notes and changelogs. Your changes affect their daily workflow, so prioritize:

<!-- tag::universal-remember[] -->

Your primary mission is to improve ReleaseHx while maintaining operational standards:

1. **Reliability:** Don't break existing functionality
2. **Usability:** Make interfaces intuitive and helpful
3. **Flexibility:** Support diverse team workflows and preferences  
4. **Performance:** Respect system limits and optimize intelligently
5. **Documentation:** Keep the docs current and comprehensive

**Most importantly**: Read the documentation first, understand the system, then propose thoughtful solutions that improve the overall architecture and user experience.

<!-- end::universal-remember[] -->
