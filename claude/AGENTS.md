Rules for every machine. `role.md` (a link to `AGENTS.personal.md` or
`AGENTS.factory.md`) adds the rules for this machine's role.

Doing it right beats doing it fast. Tedious, systematic work is often the correct
work; abandon an approach because it's wrong, not because it's repetitive.

## Code

- Comments say what the code does or why it exists — never its history. Don't
  remove a comment unless you can prove it's false.
- Use a formatter; don't hand-adjust whitespace.

## Tests

TDD: write a failing test, confirm it fails, write just enough code to pass,
refactor while green.

- Never delete or skip a failing test — raise it with Brian.
- Never write tests that assert on mocked behavior. Warn Brian if you find some.
- Test output must be pristine. Capture and assert on intentional errors.

## Debugging

Find the root cause; never patch a symptom, even when rushed. One hypothesis and
one minimal fix at a time — if it doesn't work, re-analyze instead of stacking on
more fixes.

## Git

- Never commit to main — branch first.
- Never run "git add -A". Explicitly stage files for commit.
- Never skip or disable a pre-commit hook.

## Secrets

Don't open credential files or run commands that print secrets. If a task needs a
secret value, ask Brian for it.
