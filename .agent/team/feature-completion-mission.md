# Feature Completion Mission: ReleaseHx MCP Server MVP

**Mission Type:** Feature Development & Refactoring  
**Date Assigned:** December 25, 2025  
**Assigned Role:** Product Engineer  
**Parent Mission:** Multi-Project Release (releasehx-release-project)  
**Mission Status:** READY TO START

---

## Mission Overview

Complete the implementation and refactoring of the ReleaseHx MCP (Model Context Protocol) server MVP feature to enable AI agents to discover and query ReleaseHx configuration schema, sample configs, and documentation through a standardized protocol.

This feature is **blocking** the ReleaseHx 0.1.0 release and must be completed before Phase 2 of the parent release mission can proceed.

---

## Role Assignment

You are assigned the **Product Engineer** role for this mission.

### Required Reading

Before beginning work, read these documents IN ORDER:

1. **Your role definition:** `<workspace>/releasehx/.agent/docs/roles/product-engineer.md`
2. **Feature requirements:** `<workspace>/releasehx/specs/docs/mcp-mvp-prd.adoc` (READ COMPLETELY)
3. **Testing guidance:** `<workspace>/releasehx/.agent/docs/skills/tests-writing.md`
4. **Ruby style guide:** `<workspace>/releasehx/.agent/docs/skills/ruby.md`
5. **Test running guide:** `<workspace>/releasehx/.agent/docs/skills/tests-running.md`

### Context Documents

These provide additional context:
- `<workspace>/releasehx/README.adoc` - Project overview
- `<workspace>/releasehx/AGENTS.md` - Agent orientation
- `<workspace>/releasehx/specs/tests/README.adoc` - Test framework

---

## Technical Context

### Current Implementation State

The MCP server has been **partially implemented** but is not fully functional:

**What exists:**
- `bin/rhx-mcp` - Executable entrypoint
- `lib/releasehx/mcp/` - Server infrastructure
- `specs/data/mcp-manifest.yml` - Resource definitions
- `lib/schemagraphy/cfgyml/reference.rb` - JSON Pointer resolution
- Asset files in `lib/releasehx/mcp/assets/` (currently copied, should be generated)

**What's incomplete:**
- MCP server has not been validated end-to-end with a real MCP client
- Assets are hardcoded/copied instead of generated during prebuild
- Tests are missing (`specs/tests/rspec/mcp_server_spec.rb` doesn't exist)
- Namespace needs migration from SchemaGraphy to DocOpsLab::MCP
- Reference class needs renaming to PathReference
- README.adoc documentation incomplete
- No Rake task for smoke testing

**Known Issues:**
- Bundler context issues when launching via MCP client (see PRD Appendix)
- VS Code Copilot MCP integration fails with "Could not locate Gemfile"

### Repository Context

**Current branch:** `config-mcp-mvp`  
**Working directory:** `<workspace>/releasehx`  
**Target version:** 0.1.0

---

## Mission Objectives

Complete the following work items to make the MCP server feature production-ready:

### 1. Namespace Migration (HIGH PRIORITY)

**Objective:** Migrate MCP core functionality from `SchemaGraphy` namespace to `DocOpsLab::MCP`

**Requirements from PRD:**
- Extract MCP core classes into a neutral location for future gem extraction
- Replace ReleaseHx-specific references with configurable inputs
- Maintain backward compatibility where needed
- Keep SchemaGraphy for CFGYML functionality only

**Files to update:**
- [ ] `lib/releasehx/mcp/server.rb`
- [ ] `lib/releasehx/mcp/resource_pack.rb`
- [ ] `lib/releasehx/mcp/manifest.rb` (if exists)
- [ ] `bin/rhx-mcp`
- [ ] Any other files in `lib/releasehx/mcp/`

**Success criteria:**
- All MCP-specific code uses `DocOpsLab::MCP` namespace
- SchemaGraphy remains for CFGYML utilities only
- Tests pass after migration
- No breaking changes to public API

---

### 2. Reference Class Refactoring (HIGH PRIORITY)

**Objective:** Rename `Reference` class to `PathReference` to avoid naming conflicts

**Rationale:** The generic name "Reference" is likely to conflict with other code. A more specific name indicates its JSON Pointer / path-based functionality.

**Files to update:**
- [ ] `lib/schemagraphy/cfgyml/reference.rb` → `path_reference.rb`
- [ ] Update class definition: `class Reference` → `class PathReference`
- [ ] Update all references in `lib/releasehx/mcp/server.rb`
- [ ] Update all references in `lib/releasehx/mcp/resource_pack.rb`
- [ ] Update any require statements
- [ ] Search for any other references: `grep -r "Reference" lib/`

**Success criteria:**
- No files named `reference.rb` remain
- All code uses `PathReference`
- Tests pass after refactor
- No runtime errors when running `bin/rhx-mcp`

---

### 3. Asset Management Refactoring (MEDIUM PRIORITY)

**Objective:** Move asset generation from manual copy to automated prebuild process

**Current problem:** Assets are currently copied into `lib/releasehx/mcp/assets/` and tracked in Git. They should be generated during prebuild from source files.

**Source files:**
- `specs/data/config-def.yml` (schema definition)
- `build/docs/config-reference.adoc` (generated reference docs)
- `build/docs/config-reference.json` (generated JSON reference)
- `build/docs/sample-config.yml` (generated sample config)
- `specs/docs/releasehx-configuration-agent-guide.md` (agent guide)

**Target location for agent guide:**
- [ ] Move/source `agent-config-guide.md` to `docs/agent/mcp-server/agent-config-guide.md`

**Prebuild integration:**
- [ ] Review existing `Rakefile` prebuild tasks
- [ ] Add asset copy/generation step to prebuild
- [ ] Ensure assets are included in gem package (check `.gemspec`)
- [ ] Ensure assets are NOT tracked in Git (check `.gitignore`)
- [ ] Update `lib/releasehx/mcp/resource_pack.rb` to find assets correctly

**Success criteria:**
- Assets are generated/copied during `rake prebuild`
- Assets are in `.gitignore`
- Assets are included in built gem
- Server can find and serve all assets at runtime
- `bin/rhx-mcp` works without manual asset preparation

---

### 4. Test Coverage (HIGH PRIORITY)

**Objective:** Create comprehensive test coverage for MCP server functionality

**Test file:** `specs/tests/rspec/mcp_server_spec.rb` (create new)

**Reference examples:**
- Review `specs/tests/rspec/schemagraphy_integration_spec.rb`
- Review `specs/tests/rspec/spec_helper.rb`
- Follow patterns from existing specs

**Test requirements from PRD:**
```ruby
RSpec.describe ReleaseHx::MCP::Server do
  # Test resource listing
  # Test resource retrieval (guide, sample, schema, JSON ref)
  # Test JSON Pointer tool (config.reference.get)
  # Test error handling for missing assets
  # Test stdio transport (if feasible)
end
```

**Additional tests:**
- [ ] Unit tests for PathReference class
- [ ] Integration tests for full resource serving
- [ ] Error handling tests (missing files, invalid pointers)
- [ ] Asset packaging verification

**Success criteria:**
- `specs/tests/rspec/mcp_server_spec.rb` exists and passes
- Test coverage includes all resources and tools
- Tests run successfully via `bundle exec rspec`
- CI/CD pipeline passes (if configured)

---

### 5. Rake Task Integration (MEDIUM PRIORITY)

**Objective:** Add Rake task to smoke-test MCP server functionality

**Requirements:**
- [ ] Create new Rake task: `rake test:mcp` or similar
- [ ] Task should start the MCP server
- [ ] Task should attempt to list resources
- [ ] Task should attempt to read at least one resource
- [ ] Task should validate JSON Pointer tool works
- [ ] Task should report success/failure clearly

**Integration:**
- Add to `Rakefile` in appropriate namespace
- Consider adding to existing test suites
- Document usage in `specs/tests/README.adoc`

**Success criteria:**
- Rake task exists and can be run
- Task provides useful diagnostic output
- Task fails loudly on errors
- Can be used in CI/CD (future)

---

### 6. Documentation Updates (MEDIUM PRIORITY)

**Objective:** Ensure README.adoc accurately documents MCP server feature

**Upgrade:** Adopt the skills of `.agent/docs/roles/tech-writer.md` for this task.

**Documentation requirements:**
- [ ] Add MCP server section to README.adoc
  - [ ] Explain what MCP server provides
  - [ ] Document how to run: `rhx-mcp`
  - [ ] Document MCP client configuration
  - [ ] List available resources
  - [ ] Show example usage with MCP clients
  - [ ] Troubleshooting section (Bundler issues, etc.)
- [ ] Update version attributes if needed (verify 0.1.0)
- [ ] Add MCP server to feature list
- [ ] Validate all example commands work

**AsciiDoc formatting:**
- Use proper AsciiDoc syntax (not Markdown)
- Follow existing patterns in README.adoc
- Use code blocks with language hints
- Use admonitions (NOTE, TIP, IMPORTANT) appropriately

**Success criteria:**
- README.adoc has complete MCP server documentation
- Documentation is clear and actionable
- All examples can be copy-pasted and work
- Version attributes are correct

---

### 7. End-to-End Validation (CRITICAL)

**Objective:** Verify MCP server works with a real MCP client

**Known blockers:**
- VS Code Copilot MCP fails with Bundler context issues
- Server exits with "Could not locate Gemfile or .bundle/ directory"

**Validation approaches:**
1. **Test with minimal JSON-RPC client** (recommended first)
   - Create simple stdio client to send JSON-RPC requests
   - Verify `resources/list` works
   - Verify `resources/read` works for each resource
   - Verify `config.reference.get` tool works

2. **Test with VS Code Copilot MCP**
   - Configure in `~/.config/Code/User/mcp.json`
   - Test various `cwd` and `command` configurations
   - Document working configuration

3. **Test with other MCP clients**
   - Consider Claude Desktop or other MCP-capable tools
   - Document working configurations

**Success criteria:**
- At least one MCP client successfully connects
- All resources are accessible
- JSON Pointer tool works correctly
- Configuration is documented for users

---

## Acceptance Criteria (Definition of Done)

This mission is complete when ALL of the following are true:

- [ ] Namespace migration complete: All MCP code uses `DocOpsLab::MCP`
- [ ] Reference → PathReference refactoring complete and tested
- [ ] Assets are generated during prebuild, not tracked in Git
- [ ] Comprehensive test coverage exists in `specs/tests/rspec/mcp_server_spec.rb`
- [ ] All tests pass: `bundle exec rspec`
- [ ] Rake task exists for smoke testing MCP server
- [ ] README.adoc has complete, accurate MCP documentation
- [ ] At least one end-to-end validation with real MCP client succeeds
- [ ] All PRD requirements from `mcp-mvp-prd.adoc` are met
- [ ] No regressions: existing functionality still works
- [ ] Code follows Ruby style guidelines
- [ ] All changes committed to `config-mcp-mvp` branch

---

## Implementation Sequence

**Recommended order:**

1. **Start with refactorings** (minimal risk, unblocks other work)
   - Reference → PathReference rename
   - Namespace migration to DocOpsLab::MCP

2. **Fix asset management** (enables testing)
   - Move agent guide to docs/agent/
   - Update prebuild to copy/generate assets
   - Update .gitignore and .gemspec

3. **Add test coverage** (validates implementation)
   - Create mcp_server_spec.rb
   - Test all resources and tools
   - Validate error handling

4. **Create Rake task** (developer ergonomics)
   - Add smoke test task
   - Integrate with test suite

5. **Update documentation** (enables users)
   - Add MCP section to README
   - Document configuration and usage

6. **End-to-end validation** (final verification)
   - Test with minimal JSON-RPC client
   - Test with VS Code or other MCP client
   - Document working configurations

---

## Working Guidelines

### Code Quality Standards

- **Ruby style:** Follow existing patterns plus `.agent/docs/skills
- **No parentheses in block/class defs:** `def method_name arg1, arg2:`
- **Use parentheses in method calls:** `method_call(arg1, arg2)`
- **Documentation:** Add RDoc comments for public APIs
- **Error handling:** Provide clear, actionable error messages
- **Logging:** Use existing logger patterns from ReleaseHx

### Git Workflow

- All work happens on `config-mcp-mvp` branch
- Commit once at the end (everything is getting squashed up later)
- Run tests before committing:
  - `bundle exec rspec`
  - `bundle exec rake labdev:lint:all`

### Testing Philosophy

- Test behavior, not implementation
- Cover happy paths and error cases
- Use descriptive test names
- Follow existing test patterns in `specs/tests/rspec/`
- Consult `specs/tests/README.adoc` for framework details

### When to Ask for Help

Ask the Operator when:
- Requirements are ambiguous or conflicting
- You discover technical blockers
- You need access to external resources (API keys, etc.)
- You want to propose alternative approaches
- Tests reveal unexpected failures
- You need clarification on acceptance criteria

---

## Handoff Notes from Previous Session

From PRD Appendix "Implementation Status":

**Bundler Context Issue:**
The MCP client (VS Code Copilot) launches the server without Bundler context. Using `bundle exec rhx-mcp` fails because there's no Gemfile in the client's working directory.

**Possible solutions:**
1. Install gem globally and use `rhx-mcp` directly (no bundle exec)
2. Configure MCP client with correct `cwd`
3. Make `rhx-mcp` work without Bundler (detect and load gems manually)
4. Document workaround for users

**Previous implementation:**
- Basic MCP server structure exists
- Resources defined in manifest
- Asset serving partially implemented
- No end-to-end validation completed

---

## Success Metrics

Upon completion, this feature should enable:

1. **Agent discoverability:** AI agents can find ReleaseHx config docs via MCP
2. **Reduced token costs:** Agents use compact resources instead of full HTML docs
3. **Config authoring accuracy:** Agents stop inventing config keys
4. **Developer ergonomics:** `rhx-mcp` command just works

---

## Mission Completion

When all acceptance criteria are met:

1. Run full test suite and verify all pass
2. Manually test MCP server with at least one client
3. Commit all changes with message: "feat: complete MCP server MVP implementation"
4. Report completion to Release Manager
5. Update parent mission tracking document Phase 1.1 checklist

**Parent mission document:** `<workspace>/lab/.agent/team/releasehx-release-project.md`

---

**Mission Status:** READY TO START  
**Estimated Effort:** 4-8 hours of focused development  
**Priority:** CRITICAL (blocking 0.1.0 release)  
**Next Review:** Upon completion or if blocked

---

## Quick Reference

**Repository:** `<workspace>/releasehx`  
**Branch:** `config-mcp-mvp`  
**PRD:** `specs/docs/mcp-mvp-prd.adoc`  
**Test command:** `bundle exec rspec`  
**Server command:** `bundle exec bin/rhx-mcp`  
**Build command:** `bundle exec rake prebuild`
