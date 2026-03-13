# V1.5 Simple Comparison

Describe a stable first version of the comparison capability for Golem.

This version does not compare live browser tabs. It compares two existing text or markdown files that already live inside the repo, such as artifacts under `outbox/manual/`.

The script `scripts/browser_compare.sh` currently supports:

- `files <slug> <file_a> <file_b>`

Behavior:

- validates that both inputs exist and are regular files
- validates that both inputs resolve inside the repo
- creates `outbox/manual/` if missing
- writes the report to a temporary file first
- publishes the final markdown only when comparison generation succeeded

Artifacts are saved under `outbox/manual/` using:

```text
<timestamp>_<slug>.md
```

The generated markdown includes:

- title
- `generated_at`
- `input_a`
- `input_b`
- `## Summary`
- `## Common lines`
- `## Only in A`
- `## Only in B`
- `## Notes`

The comparison is intentionally simple and textual:

- line-based
- ignores empty lines
- normalizes repeated whitespace
- does not attempt semantic understanding

If input validation or report generation fails, the script must exit non-zero and must not print `COMPARISON_OK`.

Only a successful run prints:

```text
COMPARISON_OK <ruta>
```
