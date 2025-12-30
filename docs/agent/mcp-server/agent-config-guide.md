# ReleaseHx configuration: agent guide (MVP)

This server exposes several authoritative artifacts for configuration work:

- `releasehx://agent/guide` (this file): how to use the two files above effectively
- `releasehx://config/sample` (YAML): the best map of the entire config tree (defaults + comments + commented-out optional keys)
- `releasehx://config/schema` (YAML): the authoritative definition (types, constraints, long docs)
- `releasehx://config/reference.json` (JSON): a queryable version of the complete config-reference docs
- tool `config.reference.get` (accepts: JSON Pointer string; returns JSON object)
- `releasehx://config/reference.adoc` (AsciiDoc) the formatted version of the reference output.

## DSL Notice

You are interacting with a YAML extension called SGYML, with its own ways of referencing YAML nodes and data types. It may be worth being able to "translate" some of this terminology or tailor it to your Operator's needs or preferences.

### Glossary

**object**: Any instance of keyed data in the YAML file.
**Map**: A "mapping" in YAML or "object" in JSON.
**Array**: A sequence in YAML, "array" in most languages.
**ArrayTable**: A sequence of sibling Maps with expected parameters.

### Key Tip: Distinguish *declared* keys from *arbitrary* keys

ReleaseHx has both:

**Declared keys** (fixed, “standard” properties):
   These are explicitly defined in the schema/sample tree. Do not make up new *declared* keys.

**Arbitrary keys** (user-defined names inside certain maps):  
   Some objects are intentionally “free-key” dictionaries where the user supplies their own key names (for example: named type definitions, named tag definitions, named link templates, etc). In those places, inventing keys is correct and expected.

How to tell which you’re in:

- If the sample tree shows placeholder keys like `<name>`, `<type_name>`, `<id>`, or similar “template keys,” treat the *key name* as arbitrary and user-defined.
- If the sample tree shows a concrete key name (e.g., `origin`, `href`, `mode`) treat it as declared and do not invent siblings that aren’t present.
- When in doubt, consult `releasehx://config/schema` for the node’s semantics (look for wording indicating “map of … keyed by …”, wildcard keys, or examples using placeholders).

## What You Can Help With, Agent

Use these assets for any of the following scenarios:

### Scenario A: Create a new config
- Generate a minimal `.releasehx.yml` that sets only what the user needs.
- Start from the sample tree to avoid missing required structure.
- Keep changes small: only override what must differ from defaults.
- If the user needs a named item (type/tag/link/etc), create it under the appropriate “arbitrary keys” map using a sensible name.

### Scenario B: Modify an existing config
- Read the user’s current config.
- Compare the affected subtree against the sample tree.
- Make the smallest possible edit (avoid restructuring unrelated blocks).
- If the change involves a named entry (arbitrary key map), add/update only that one entry.

### Scenario C: Troubleshoot behavior
- When output/content is surprising, locate the relevant top-level block in the sample tree first.
- Use the schema definition to confirm allowed values and semantics before proposing changes.
- Prefer quoting the schema’s constraints/intent rather than guessing.
- If behavior depends on a named entry (type/tag/link/etc), confirm the user’s key name matches the referenced name elsewhere.

### Scenario D: Discover available knobs
- Use the sample config as a TOC.
- If you need deeper meaning, consult the schema entry for that subtree.
- If the user asks for “all options,” point them to the sample tree and offer to focus on one subtree at a time.

## Where config comes from

- Defaults are defined by the schema definition (`releasehx://config/schema`).
- Users override defaults via `.releasehx.yml` or a `--config <path>` flag.

## How to navigate quickly (recommended method)

1) Load `releasehx://config/sample` and use it as the “table of contents.”
2) Identify the smallest subtree relevant to the user’s goal.
3) Decide whether you are working with:
   - a declared-key subtree (fixed property names), or
   - an arbitrary-key map (user-defined item names).
4) Only if needed, consult `releasehx://config/schema` for:
   - allowed values (enums)
   - types (string/boolean/integer/uri/path/template/etc)
   - templating rules and any special behaviors
5) Apply minimal edits to the user’s config.

## Hack for inspecting the effective config

Append the following to any proper `rhx` command to write an "effective config" to file.

```shell
--debug 2>&1 | awk '
  /^DEBUG: Operative config settings:/ {p=1; next}
  p && /^---[[:space:]]*$/ {y=1}
  y {print}
  y && /^[[:space:]]*$/ {exit}
' > .agent/tmp/effective-config.yml
```

Replace the `> PATH` with one appropriate to your Operator's preferences or local application structure.

## Counter-prompts (questions to ask the Operator)

Ask only what you need to select the right subtree and values:

- What is the issues origin source? (Jira / GitHub / GitLab / RHYML file)
- What is the origin endpoint or file location?
- Do you want Markdown or AsciiDoc output? (and do you want frontmatter?)
- Are you generating drafts, final outputs, or both?
- Do you want to group/sort by type/part/tags, or keep defaults?
- Are credentials provided via environment variables, or do you need explicit auth config?
- If you’re defining named items (types/tags/links/etc), what names do you want to use for those entries?

If the user provides only a vague goal, ask one question at a time until you can pick the right subtree.

## Common top-level blocks (use the sample tree as the source of truth)

Typical blocks include (names may vary; consult the sample tree):

- `$meta` (markup + conventions)
- `origin` (API/file source + auth + project identifiers)
- `conversions` (how summaries/heads/notes are derived)
- `extensions` (file extension settings)
- `types`, `parts`, `tags` (classification/grouping controls; often include arbitrary keys)
- `links` (templated link formats; often include arbitrary keys)
- `paths` (input/output locations)
- `modes` (execution defaults)
- `rhyml` (RHYML-specific behaviors)

## When to consult schema (instead of sample)

Use `releasehx://config/schema` when:

- the user’s desired value is not obvious from comments
- you need to confirm an enum (e.g., `origin.source` values)
- a property is templated and you need to understand substitution variables
- you suspect a type mismatch (URI vs Path vs String, etc)
- you need to confirm whether a subtree allows arbitrary keys, and what each entry’s structure must be

## Potentially unintuitive principles

- **“Frontmatter” is controlled in two places (toggle vs template).**  
  If you’re trying to *turn frontmatter on/off*, look under `modes.*_frontmatter`. If you’re trying to *change what frontmatter contains*, look under `templates.*_frontmatter` (Markdown/AsciiDoc/HTML each have their own). Also note `modes.wrapped` affects HTML wrapping, which can look like a frontmatter problem when it’s really wrapping/boilerplate.

- **Links require both a template and an enable switch.**  
  Defining URL templates under `links.web.href` / `links.git.href` does nothing by itself. You must also enable display under `history.items.show_issue_links` / `history.items.show_git_links` (or the per-section overrides under changelog/notes items, if present). If a user says “I set the link template but no links appear,” check the `history.*items*` flags.

- **There are multiple “markup” concepts.**  
  `$meta.markup` is the markup format used inside *config strings* (and is meant to keep defaults cross-compatible). `rhyml.markup` is the markup for the *RHYML note/memo content* and can also be overridden inside RHYML documents themselves. If a user complains “my Markdown isn’t converting to AsciiDoc,” don’t only look at `$meta`.

- **API source selection is under `origin`, but API customization lives under `paths`.**  
  `origin.source` selects the API type (`jira`, `github`, `gitlab`, `rhyml`) and `origin.href` points at the endpoint or payload location. But “where do I put custom mappings/clients?” is not in `origin.*`; it’s in `paths.mappings_dir` and `paths.api_clients_dir`, and those directories are searched using filenames derived from `origin.source`.

- **`origin.href` can be templated, and its variables come from siblings and CLI args.**  
  If the endpoint/path needs to vary by project or version, `origin.href` supports templating (for example, using the sibling `origin.project` and the argued release version). If a user expects `{{ version }}` or project placeholders to work and they don’t, treat it as a templating/evaluation-order issue, not a path issue.

- **“How do I change what becomes `summ` / `head` / note text?” is under `conversions`, not templates.**  
  The `conversions` block is about *where content originates* (issue title vs custom field vs commit message, etc) and how it maps into RHYML fields. If the user asks “use a custom field for summaries,” don’t go hunting in output templates first.

- **Classification maps are intentionally “invent-your-own-key” dictionaries.**  
  Blocks like `types`, `parts`, and (parts of) `tags` are designed so users define named entries. If you see placeholder keys like `<type_name>` or `<part_name>` or language implying “arbitrarily named,” that means the *map keys are user-defined identifiers* and should be invented to match the user’s taxonomy or existing labels.

- **Tags are both a filter and a dictionary of tag definitions.**  
  The tags system is easy to misread:
  - Some keys (like `_include` / `_exclude`) behave like filter controls for *including* or *excluding* entire issue/change records at RHYML conversion time.
  - Many other keys represent *individual tags* that may be imported from the issue system or assigned in RHYML.
  - Only tags that are declared in the tags block will typically be preserved/ported from API payload into RHYML tags.  
  If a user says “my label exists in GitHub but it’s not showing up,” it’s usually because it isn’t declared under `tags`.

- **Some tags are “operational” and default to being dropped.**  
  A tag can exist only to drive inclusion (example: `changelog`) and may default to `drop: true`, meaning it influences selection but is not shown in published output unless explicitly configured otherwise. If the user expects to see it in output, check the tag’s `drop` and `groupable` settings.

- **Output location is split into base dir, subdirs, and filename templates.**
  If a user says “ReleaseHx is writing to the wrong folder,” check:
  - `paths.output_dir` (the base)
  - `paths.drafts_dir` and `paths.enrich_dir` (subdirectories)
  - `paths.*_filename` templates (which may include `{{ version }}` and `{{ format_ext }}` and are resolved late).  
  If file extensions look wrong, it may be an `extensions.*` issue, not a `paths.*` issue, because `format_ext` comes from extension preferences.

- **Cache settings live under `paths.cache` (not under origin or modes).**  
  If a user wants fewer API calls or wonders “why am I seeing cached payload behavior,” look under `paths.cache.*` (enabled/ttl/dir) and related gitignore prompting. This often presents like an origin/API issue but isn’t.
