# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub Actions for comparing OpenAPI specs and detecting breaking changes, based on [oasdiff](https://github.com/oasdiff/oasdiff).

## Spec paths

The `base` and `revision` inputs accept:

- **File paths** — e.g. `openapi.yaml` or `specs/openapi.yaml` (files on disk)
- **Git refs** — e.g. `origin/${{ github.base_ref }}:openapi.yaml` or `HEAD:openapi.yaml`
- **URLs** — e.g. `https://example.com/openapi.yaml`

File paths and git refs require the repository to be checked out first:

```yaml
- uses: actions/checkout@v6   # required for file paths and git refs
- uses: oasdiff/oasdiff-action/breaking@v0.0.30
  with:
    base: 'origin/${{ github.base_ref }}:openapi.yaml'
    revision: 'HEAD:openapi.yaml'
```

> `fetch-depth: 0` is **not** needed — the default shallow checkout is sufficient.

---

## Spec sources

The `base` and `revision` inputs accept:

| Format | Example |
|---|---|
| Local file path | `specs/base.yaml` |
| http/s URL | `https://example.com/openapi.yaml` |
| Git revision | `origin/${{ github.base_ref }}:openapi.yaml` |

Git revision syntax (`<ref>:<path>`) lets you compare specs directly from git history without extra checkout steps. `fetch-depth: 0` is required in `actions/checkout` when using git revisions.

```yaml
- uses: actions/checkout@v6
  with:
    fetch-depth: 0

- uses: oasdiff/oasdiff-action/breaking@v0.0.31
  with:
    base: 'origin/${{ github.base_ref }}:openapi.yaml'
    revision: 'HEAD:openapi.yaml'
```

---

## Free actions

The following actions run the oasdiff CLI directly in your GitHub runner — no account or token required.

### Check for breaking changes

Detects breaking changes and writes inline GitHub annotations (`::error::`) to the Actions summary. Fails the workflow if breaking changes are found.

```yaml
- uses: oasdiff/oasdiff-action/breaking@v0.0.31
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'
```

The result is also available as a step output named `breaking`.

| Input | CLI flag | Default |
|---|---|---|
| `fail-on` | `--fail-on` | `''` |
| `include-checks` | `--include-checks` | `''` |
| `include-path-params` | `--include-path-params` | `false` |
| `deprecation-days-beta` | `--deprecation-days-beta` | `31` |
| `deprecation-days-stable` | `--deprecation-days-stable` | `180` |
| `exclude-elements` | `--exclude-elements` | `''` |
| `filter-extension` | `--filter-extension` | `''` |
| `composed` | `-c` | `false` |
| `output-to-file` | N/A | `''` |

### Generate a changelog

Outputs all changes (breaking and non-breaking) between two specs.

```yaml
- uses: oasdiff/oasdiff-action/changelog@v0.0.31
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'
```

| Input | CLI flag | Default |
|---|---|---|
| `format` | `--format` | `''` |
| `level` | `--level` | `''` |
| `include-path-params` | `--include-path-params` | `false` |
| `exclude-elements` | `--exclude-elements` | `''` |
| `filter-extension` | `--filter-extension` | `''` |
| `composed` | `-c` | `false` |
| `prefix-base` | `--prefix-base` | `''` |
| `prefix-revision` | `--prefix-revision` | `''` |
| `case-insensitive-headers` | `--case-insensitive-headers` | `false` |
| `template` | `--template` | `''` |
| `output-to-file` | N/A | `''` |

### Generate a diff report

Outputs the raw structural diff between two specs.

```yaml
- uses: oasdiff/oasdiff-action/diff@v0.0.31
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'
```

| Input | CLI flag | Default |
|---|---|---|
| `fail-on-diff` | `--fail-on-diff` | `false` |
| `format` | `--format` | `yaml` |
| `include-path-params` | `--include-path-params` | `false` |
| `exclude-elements` | `--exclude-elements` | `''` |
| `filter-extension` | `--filter-extension` | `''` |
| `composed` | `-c` | `false` |
| `output-to-file` | N/A | `''` |

---

## Pro: Rich PR comment

`oasdiff/oasdiff-action/pr-comment@v0.0.31` posts a single auto-updating comment on the PR timeline every time the spec changes. Changes are grouped by severity (breaking → warnings → info) with links to the affected source lines.

```yaml
- uses: oasdiff/oasdiff-action/pr-comment@v0.0.31
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'
    oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
```

| Input | Description | Required |
|---|---|---|
| `base` | Path to the base (old) OpenAPI spec | Yes |
| `revision` | Path to the revised (new) OpenAPI spec | Yes |
| `oasdiff-token` | oasdiff API token — [sign up at oasdiff.com](https://oasdiff.com) to get one | Yes |
| `github-token` | GitHub token for posting the comment | No (defaults to `${{ github.token }}`) |
| `include-path-params` | Include path parameter names in endpoint matching | No |
| `exclude-elements` | Exclude certain kinds of changes | No |
| `composed` | Run in composed mode | No |

An `OASDIFF_TOKEN` is issued per GitHub organization. [See pricing →](https://www.oasdiff.com/pricing)
