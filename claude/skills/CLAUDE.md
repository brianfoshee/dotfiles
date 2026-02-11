# Skills Best Practices

Guidelines for writing and maintaining Claude Code custom skills in this directory.

## SKILL.md Structure

Every skill is a directory with a required `SKILL.md` containing YAML frontmatter and a markdown body.

### Frontmatter Fields

```yaml
---
name: my-skill                          # Lowercase, hyphens, max 64 chars
description: What it does and when...   # Third-person, specific, include trigger keywords (max 1024 chars)
allowed-tools: Read, Grep, Glob         # Tools allowed without per-use approval
argument-hint: "[filename] [format]"    # Hint shown in autocomplete
disable-model-invocation: true          # Prevent Claude from auto-triggering
user-invocable: false                   # Hide from / menu
context: fork                           # Run in isolated subagent context
agent: Explore                          # Subagent type (Explore, Plan, general-purpose)
---
```

### Description Quality

The description determines when Claude invokes the skill. Make it specific:

- **Good**: "Expert Ruby on Rails architect for reviewing existing Rails applications, suggesting architectural improvements, and designing new features following modern Rails best practices. Use when working with Rails apps, designing Rails features, or reviewing Rails architecture."
- **Bad**: "Helps with Rails stuff"

## Conciseness Rules

**SKILL.md must be under 500 lines.** Every token competes with conversation context.

Before adding content, ask:
- Does Claude already know this? (Don't explain CSS, design patterns, WCAG, etc.)
- Is this stated elsewhere in the file? (Never repeat the same rule)
- Is this reference material? (Move to a supporting docs/ file)

### What to keep in SKILL.md
- Core rules and constraints Claude must always follow
- Project-specific configuration (font stacks, API endpoints, file formats)
- Concise pattern summaries with brief code examples
- Index of supporting docs/ files with "when to read" triggers

### What to move to docs/ files
- Detailed code examples and complete implementations
- Deep-dive reference material for specific topics
- Anti-pattern catalogs and checklists
- Content only needed when a specific topic comes up

## Content Anti-Patterns

- **Redundancy**: Never state the same rule more than once
- **Over-explaining**: Don't teach Claude concepts it already knows
- **Available Tools sections**: Claude can see its own tools
- **Version history**: No dates, changelogs, or temporal context
- **Verbose DO/DON'T lists**: If rules are already covered in the body, don't repeat them in a summary list

## File Organization

```
my-skill/
├── SKILL.md          # Under 500 lines - core instructions
├── docs/             # Supporting reference material
│   ├── patterns.md
│   └── examples.md
└── scripts/          # Executable utilities (if needed)
```

- Keep docs/ references one level deep from SKILL.md
- Use descriptive filenames (`authorization-and-roles.md`, not `doc2.md`)
- Add a table of contents to reference files over 100 lines
- Don't create empty directories (git won't track them)

## Maintenance

- Clean up `.DS_Store` and backup files periodically
- Large data files (>1MB) should not be tracked in git
- Review skills against these guidelines when making changes
