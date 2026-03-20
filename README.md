# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub Actions for comparing OpenAPI specs and detecting breaking changes, based on [oasdiff](https://github.com/oasdiff/oasdiff).

## Spec paths

The `base` and `revision` inputs accept:

| Format | Example |
|---|---|
| Local file path | `specs/base.yaml` |
| http/s URL | `https://example.com/openapi.yaml` |
| Git ref | `origin/${{ github.base_ref }}:openapi.yaml` |

File paths and git refs require the repository to be checked out first:

```yaml
- uses: actions/checkout@v6
- run: git fetch --depth=1 origin ${{ github.base_ref }}
- uses: oasdiff/oasdiff-action/breaking@v0.0.34
  with:
    base: 'origin/${{ github.base_ref }}:openapi.yaml'
    revision: 'HEAD:openapi.yaml'
```

> A targeted `git fetch` is needed so that `origin/${{ github.base_ref }}` is available. `fetch-depth: 0` is not required — fetching only the base branch is sufficient.

---

## Free actions

The following actions run the oasdiff CLI directly in your GitHub runner — no account or token required.

### Check for breaking changes

Detects breaking changes and writes inline GitHub annotations (`::error::`) to the Actions summary. Fails the workflow if breaking changes are found.

```yaml
- uses: oasdiff/oasdiff-action/breaking@v0.0.34
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
- uses: oasdiff/oasdiff-action/changelog@v0.0.34
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
- uses: oasdiff/oasdiff-action/diff@v0.0.34
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

`oasdiff/oasdiff-action/pr-comment@v0.0.34` posts a single auto-updating comment on every PR that touches your API spec.

```yaml
- uses: oasdiff/oasdiff-action/pr-comment@v0.0.34
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'
    oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
```

The comment shows a table of all changes, grouped by severity, with a **Review** link for each breaking change:

| Severity | Change | Path | Review |
|---|---|---|---|
| 🔴 | response-property-removed | `GET /users` | ✅ [Approved by @alice](https://oasdiff.com/review/…) |
| 🔴 | request-parameter-type-changed | `GET /products` | ⏳ [Review](https://oasdiff.com/review/…) |
| 🟡 | response-optional-property-removed | `POST /orders` | ⏳ [Review](https://oasdiff.com/review/…) |

Each **Review** link opens a hosted page with a side-by-side spec diff and **Approve / Reject** buttons. Approvals are tied to the change fingerprint and carry forward automatically when the branch is updated. A commit status check blocks the merge until every breaking change has been reviewed.

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
