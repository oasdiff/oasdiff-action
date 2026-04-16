# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub Actions for comparing OpenAPI specs and detecting breaking changes, based on [oasdiff](https://github.com/oasdiff/oasdiff).

## Free actions

The following actions run the oasdiff CLI directly in your GitHub runner — no account or token required.

### Check for breaking changes

Detects breaking changes and writes inline GitHub annotations (`::error::`) to the Actions summary. Does not fail the workflow by default — set `fail-on` to `ERR` or `WARN` to fail on changes.

```yaml
jobs:
  oasdiff:
    runs-on: ubuntu-latest
    steps:
      - uses: oasdiff/oasdiff-action/breaking@v0.0.40-beta.3
        with:
          base: 'specs/base.yaml'
          revision: 'specs/revision.yaml'
```

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `fail-on` | `''` | Fail with exit code 1 if changes are found at or above this severity | `ERR`, `WARN` |
| `include-path-params` | `false` | Include path parameter names in endpoint matching | `true`, `false` |
| `deprecation-days-beta` | `31` | Minimum sunset period (days) for deprecation of beta API endpoints | integer |
| `deprecation-days-stable` | `180` | Minimum sunset period (days) for deprecation of stable API endpoints | integer |
| `exclude-elements` | `''` | Exclude certain kinds of changes from the output | `endpoints`, `request`, `response` (comma-separated) |
| `filter-extension` | `''` | Exclude paths and operations with an OpenAPI Extension matching this expression | regex |
| `composed` | `false` | Run in composed mode | `true`, `false` |
| `flatten-allof` | `false` | Merge allOf subschemas into a single schema before diff | `true`, `false` |
| `err-ignore` | `''` | Path to a file containing regex patterns for error-level changes to ignore | file path |
| `warn-ignore` | `''` | Path to a file containing regex patterns for warning-level changes to ignore | file path |
| `output-to-file` | `''` | Write output to this file path instead of stdout | file path |

### Generate a changelog

Outputs all changes (breaking and non-breaking) between two specs.

```yaml
jobs:
  oasdiff:
    runs-on: ubuntu-latest
    steps:
      - uses: oasdiff/oasdiff-action/changelog@v0.0.40-beta.3
        with:
          base: 'specs/base.yaml'
          revision: 'specs/revision.yaml'
```

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `format` | `''` | Output format | `text`, `json`, `yaml`, `markdown`, `html` |
| `level` | `''` | Minimum severity level to include in output | `INFO`, `WARN`, `ERR` |
| `include-path-params` | `false` | Include path parameter names in endpoint matching | `true`, `false` |
| `exclude-elements` | `''` | Exclude certain kinds of changes from the output | `endpoints`, `request`, `response` (comma-separated) |
| `filter-extension` | `''` | Exclude paths and operations with an OpenAPI Extension matching this expression | regex |
| `composed` | `false` | Run in composed mode | `true`, `false` |
| `flatten-allof` | `false` | Merge allOf subschemas into a single schema before diff | `true`, `false` |
| `prefix-base` | `''` | Prefix to add to all paths in the base spec | string |
| `prefix-revision` | `''` | Prefix to add to all paths in the revised spec | string |
| `case-insensitive-headers` | `false` | Compare headers case-insensitively | `true`, `false` |
| `template` | `''` | Custom Go template for output formatting | Go template string |
| `output-to-file` | `''` | Write output to this file path instead of stdout | file path |

### Generate a diff report

Outputs the raw structural diff between two specs.

```yaml
jobs:
  oasdiff:
    runs-on: ubuntu-latest
    steps:
      - uses: oasdiff/oasdiff-action/diff@v0.0.40-beta.3
        with:
          base: 'specs/base.yaml'
          revision: 'specs/revision.yaml'
```

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `fail-on-diff` | `false` | Fail with exit code 1 if any difference is found | `true`, `false` |
| `format` | `yaml` | Output format | `yaml`, `json`, `text` |
| `include-path-params` | `false` | Include path parameter names in endpoint matching | `true`, `false` |
| `exclude-elements` | `''` | Exclude certain kinds of changes from the output | `endpoints`, `request`, `response` (comma-separated) |
| `filter-extension` | `''` | Exclude paths and operations with an OpenAPI Extension matching this expression | regex |
| `composed` | `false` | Run in composed mode | `true`, `false` |
| `flatten-allof` | `false` | Merge allOf subschemas into a single schema before diff | `true`, `false` |
| `output-to-file` | `''` | Write output to this file path instead of stdout | file path |

---

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
- uses: oasdiff/oasdiff-action/breaking@v0.0.40-beta.3
  with:
    base: 'origin/${{ github.base_ref }}:openapi.yaml'
    revision: 'HEAD:openapi.yaml'
```

> A targeted `git fetch` is needed so that `origin/${{ github.base_ref }}` is available. `fetch-depth: 0` is not required — fetching only the base branch is sufficient.

---

## Pro: Rich PR comment

`oasdiff/oasdiff-action/pr-comment@v0.0.40-beta.3` posts a single auto-updating comment on every PR that touches your API spec.

**Prerequisite:** oasdiff posts comments and commit statuses as a GitHub App. [Install the oasdiff GitHub App](https://github.com/apps/oasdiff/installations/new) on each repository before using this action.

```yaml
jobs:
  oasdiff:
    runs-on: ubuntu-latest
    steps:
      - uses: oasdiff/oasdiff-action/pr-comment@v0.0.40-beta.3
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

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `oasdiff-token` | — (required) | oasdiff API token — [get one at oasdiff.com/pricing](https://oasdiff.com/pricing) | — |
| `github-token` | `${{ github.token }}` | GitHub token for posting the PR comment; requires `pull-requests: write`, `statuses: write` | — |
| `include-path-params` | `false` | Include path parameter names in endpoint matching | `true`, `false` |
| `exclude-elements` | `''` | Exclude certain kinds of changes from the output | `endpoints`, `request`, `response` (comma-separated) |
| `composed` | `false` | Run in composed mode | `true`, `false` |

An `OASDIFF_TOKEN` is issued per GitHub organization. [See pricing →](https://www.oasdiff.com/pricing)
