# Repository guidance

This directory is its own Git repository. The parent Gnorium workspace is not a repository; run Git commands here and inspect sibling repositories separately.

- Preserve unrelated working changes. When renaming an internal API, update callers in sibling packages rather than leave obsolete aliases.
- Run focused checks for the changed behavior. Do not run full server/browser suites unless requested.
- Keep build caches and `.build` directories. Diagnose build/toolchain errors before rebuilding; do not wipe caches to troubleshoot.
- Batch related changes before building. Deployment requires an explicit user request; a local build or server restart is not deployment.
- If committing authorized work, omit attribution trailers and push normally after the commit; never force-push.

## Diff semantics

Preserve exact source characters, spaces, and line breaks. Keep old/new source-line numbers available for source-to-diff synchronization. Highlight changed whitespace without inserting visible stand-in characters into copied text.

Keep display formatting separate from the comparison engine. Changes to core diff behavior need focused tests with real insertion/removal and Unicode cases.
