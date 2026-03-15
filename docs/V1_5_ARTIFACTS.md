# V1.5 Simple Artifacts

Describe a capability for generating simple artifacts from browser relay snapshots.

The script `scripts/browser_artifact.sh` supports two subcommands:

- `snapshot <slug>`: captures current tab snapshot to markdown artifact.
- `find <slug> <texto>`: searches within current snapshot for a query string.

By default it uses the `chrome` browser profile. For validation or managed-browser flows, you can override it with `GOLEM_BROWSER_PROFILE=<perfil>`.

That override only counts as a real success-path if the selected profile can actually expose a usable tab or managed target.

Artifacts are saved under the repo's `outbox/manual/` directory, regardless of the current working directory, with a timestamp and slug, including a minimal header:

```markdown
# <slug>

generated_at: <iso timestamp>
profile: chrome
```

In find mode the file also contains the search query and either matching lines with context or a message that no matches were found.

The script writes to a temporary file first and only publishes the final artifact if the browser snapshot succeeds.

If the snapshot command fails, exits non-zero, or returns relay/gateway errors such as `Error:`, `gateway closed`, or `abnormal closure`, the script must exit non-zero and must not print `ARTIFACT_OK`.

A final line `ARTIFACT_OK <ruta>` is printed only after a valid artifact has been written successfully.
