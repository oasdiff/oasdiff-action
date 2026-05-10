# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub Actions for comparing OpenAPI specs and detecting breaking changes, based on [oasdiff](https://github.com/oasdiff/oasdiff).

## Contents

- [Quick start](#quick-start)
- [Free actions](#free-actions)
  - [Check for breaking changes](#check-for-breaking-changes)
  - [Generate a changelog](#generate-a-changelog)
  - [Generate a diff report](#generate-a-diff-report)
- [Configuring with `.oasdiff.yaml`](#configuring-with-oasdiffyaml)
- [Spec paths](#spec-paths)
- [Pro: Rich PR comment](#pro-rich-pr-comment)

## Quick start

Add this workflow to `.github/workflows/oasdiff.yaml` to block PRs that introduce breaking API changes.
Replace `openapi.yaml` with the path to your OpenAPI spec:

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
jobs:
  breaking-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/breaking@v0.0.47
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          fail-on: WARN
```

This compares your spec on the PR branch against the base branch and fails the workflow if any breaking changes are found.

---

## Free actions

The following actions run the oasdiff CLI directly in your GitHub runner — no account or token required.

### Check for breaking changes

Detects breaking changes and writes inline GitHub annotations to the Actions summary. Fails the workflow when changes at or above the `fail-on` severity are found.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
jobs:
  breaking-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/breaking@v0.0.47
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          fail-on: WARN
```

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `fail-on` | `''` | Fail with exit code 1 if changes are found at or above this severity | `ERR`, `WARN` |
| `include-checks` | `''` | Include optional breaking change checks | check names (comma-separated) |
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
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
jobs:
  changelog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/changelog@v0.0.47
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
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
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
jobs:
  diff:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/diff@v0.0.47
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
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

## Configuring with `.oasdiff.yaml`

All four actions (`breaking`, `changelog`, `diff`, `pr-comment`) automatically pick up a `.oasdiff.yaml` file from the root of your checked-out repository. This lets you keep CLI-flag-shaped configuration in source control instead of repeating the same `with:` block in every workflow file.

Drop a `.oasdiff.yaml` next to your spec:

```yaml
# .oasdiff.yaml
fail-on: ERR
exclude-elements:
  - description
  - title
  - summary
err-ignore: ./oasdiff-err-ignore.txt
```

The actions read this file from the runner's `$GITHUB_WORKSPACE` (which `actions/checkout` populates), so no extra steps are needed.

**Precedence**: action `with:` inputs override `.oasdiff.yaml` values, which override built-in defaults. Setting `fail-on: ERR` in YAML and leaving the action's `fail-on:` input empty applies the YAML value; setting both lets the action input win.

**Legacy filename**: the older `oasdiff.yaml` (without the leading dot) still works as a back-compat fallback. New projects should prefer `.oasdiff.yaml` to match the dotfile convention used by `.eslintrc`, `.golangci.yml`, and similar tools.

**Explicit path**: if your config lives somewhere else, set `OASDIFF_CONFIG` in the workflow `env:` to point at it:

```yaml
- uses: oasdiff/oasdiff-action/breaking@v0.0.47
  env:
    OASDIFF_CONFIG: ./config/oasdiff.yaml
  with:
    base: 'origin/${{ github.base_ref }}:openapi.yaml'
    revision: 'HEAD:openapi.yaml'
```

For the full list of supported keys and how relative paths inside the config file are resolved, see the [oasdiff configuration-file reference](https://github.com/oasdiff/oasdiff/blob/main/docs/CONFIG-FILES.md).

Available since action `v0.0.47` (which ships oasdiff `v1.15.3`).

---

## Spec paths

The `base` and `revision` inputs accept:

| Format | Example |
|---|---|
| Git ref (recommended) | `origin/${{ github.base_ref }}:openapi.yaml` |
| Local file path | `openapi.yaml` |
| http/s URL | `https://example.com/openapi.yaml` |

When using git refs, you need to check out the repo and fetch the base branch:

```yaml
- uses: actions/checkout@v6
- run: git fetch --depth=1 origin ${{ github.base_ref }}
```

> `fetch-depth: 0` is not required — fetching only the base branch is sufficient.

---

## Pro: Rich PR comment

`oasdiff/oasdiff-action/pr-comment` posts a single auto-updating comment on every PR that touches your API spec.

**Getting started:** [Sign up for oasdiff Pro](https://www.oasdiff.com/pricing) to get your token, then follow the setup instructions to install the GitHub App, add your repo secret, and create the workflow.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
jobs:
  pr-comment:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/pr-comment@v0.0.47
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
```

The comment shows a table of all changes, grouped by severity, with a **Review** link for each breaking change:

| Severity | Change | Path | Review |
|---|---|---|---|
| 🔴 | request parameter became required | `GET /products` | ⏳ [Review](https://www.oasdiff.com/review/4a9fd2d5-5ac2-42f5-94cb-c911d6d41680?highlight=a570278809fa) |
| 🔴 | api removed without deprecation | `DELETE /users/{userId}` | ⏳ [Review](https://www.oasdiff.com/review/4a9fd2d5-5ac2-42f5-94cb-c911d6d41680?highlight=bc9f61316c57) |
| 🔴 | request parameter type changed | `GET /users/{userId}` | ⏳ [Review](https://www.oasdiff.com/review/4a9fd2d5-5ac2-42f5-94cb-c911d6d41680?highlight=b9a23e767b29) |

Each **Review** link opens a hosted page with a side-by-side spec diff and **Approve / Reject** buttons. Approvals are tied to the change fingerprint and carry forward automatically when the branch is updated. A commit status check blocks the merge until every breaking change has been reviewed.

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `oasdiff-token` | — (required) | oasdiff API token — [sign up at oasdiff.com](https://www.oasdiff.com/pricing) | — |
| `include-path-params` | `false` | Include path parameter names in endpoint matching | `true`, `false` |
| `exclude-elements` | `''` | Exclude certain kinds of changes from the output | `endpoints`, `request`, `response` (comma-separated) |
| `composed` | `false` | Run in composed mode | `true`, `false` |

[Get oasdiff Pro →](https://www.oasdiff.com/pricing)
