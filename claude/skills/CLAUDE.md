# Skills Best Practices

Conventions for the custom skills in this directory.

## Structure

A skill is a directory with a `SKILL.md`: YAML frontmatter plus a markdown body.

```yaml
---
name: my-skill                          # Lowercase, hyphens, max 64 chars
description: What it does and when...   # Third-person, max 1024 chars
allowed-tools: Read, Grep, Glob         # Usable without per-use approval
argument-hint: "[filename] [format]"    # Shown in autocomplete
disable-model-invocation: true          # Never auto-triggers
user-invocable: false                   # Hidden from the / menu
context: fork                           # Runs in an isolated subagent context
agent: Explore                          # Subagent type when forked
---
```

The description decides when the skill gets invoked, so name the concrete tasks
and their trigger words — "reviewing Rails applications, designing features" —
rather than "helps with Rails stuff".

## Body

Keep SKILL.md under 500 lines; it competes with conversation context. It should
carry the constraints and project-specific configuration that can't be guessed —
font stacks, file formats, API endpoints, license terms — plus an index of
`docs/` files saying when to read each one.

Push detailed examples, deep-dive reference, and topic-specific material into
`docs/` (one level deep, descriptive filenames, table of contents past 100
lines). Leave out anything Claude already knows, anything stated elsewhere in the
file, lists of available tools, and version history or changelogs.

## Maintenance

Data files over 1MB don't belong in git. Clean up `.DS_Store` and backup files as
they accumulate.
