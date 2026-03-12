# V1.5 Simple Artifacts

Describe a capability for generating simple artifacts from browser relay snapshots.

The script `scripts/browser_artifact.sh` supports two subcommands:

- `snapshot <slug>`: captures current tab snapshot to markdown artifact.
- `find <slug> <texto>`: searches within current snapshot for a query string.

Artifacts are saved under `outbox/manual/` with a timestamp and slug, including a minimal header:

```markdown
# <slug>

generated_at: <iso timestamp>
profile: chrome
```

In find mode the file also contains the search query and either matching lines with context or a message that no matches were found.

A final line `ARTIFACT_OK <ruta>` is printed on success.
