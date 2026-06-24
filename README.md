# oasdiff-action
[![breaking](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-breaking.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-breaking.yaml)
[![changelog](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-changelog.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-changelog.yaml)
[![diff](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-diff.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-diff.yaml)
[![pr-comment](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-pr-comment.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-pr-comment.yaml)
[![validate](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-validate.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-validate.yaml)
[![verify](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-verify.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions/workflows/test-verify.yaml)

GitHub Actions that check your OpenAPI specs for breaking changes on every pull request. They post a side-by-side review of the changes as a PR comment and, with Pro, let your team approve or reject each change with a commit-status check that gates the merge. Based on [oasdiff](https://github.com/oasdiff/oasdiff).

## Contents

- [Quick start](#quick-start)
- [Versioning](#versioning)
- [Free actions](#free-actions)
  - [Check for breaking changes](#check-for-breaking-changes)
  - [Generate a changelog](#generate-a-changelog)
  - [Generate a diff report](#generate-a-diff-report)
  - [Validate a single spec](#validate-a-single-spec)
- [Configuring with `.oasdiff.yaml`](#configuring-with-oasdiffyaml)
- [Spec paths](#spec-paths)
- [Pro: Rich PR comment](#pro-rich-pr-comment)
- [Pro: Verify your setup](#pro-verify-your-setup)

## Quick start

Add this workflow to `.github/workflows/oasdiff.yaml` to block PRs that introduce breaking API changes.
Replace `openapi.yaml` with the path to your OpenAPI spec:

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
permissions:
  contents: read
  pull-requests: write   # lets the action post the review link as a PR comment
jobs:
  breaking-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/breaking@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          fail-on: WARN
          github-token: ${{ github.token }}
```

This compares your spec on the PR branch against the base branch and fails the workflow if any breaking changes are found. When changes are found it posts a side-by-side review link as a PR comment; drop `github-token` and the `pull-requests: write` permission to keep that link in the job summary instead.

---

## Versioning

The examples here pin the action at `@v0`, the moving major-version tag. It always points at the latest `v0.x.y` release, so you get every later patch and minor (including review and PR-comment improvements) automatically, with no workflow change:

```yaml
- uses: oasdiff/oasdiff-action/breaking@v0
```

`@v0` only advances on stable releases, never on prereleases. If you prefer to control upgrades yourself, pin to a specific release tag from the [Releases page](https://github.com/oasdiff/oasdiff-action/releases) and bump it when you choose. `@main` runs the unreleased tip and is meant for trying changes early, not for production.

---

## Free actions

The following actions run the oasdiff CLI directly in your GitHub runner — no account or token required.

### Check for breaking changes

Detects breaking changes and writes inline `::error::` annotations on the pull request's Files changed tab. Fails the workflow when changes at or above the `fail-on` severity are found. When changes are found it also uploads the comparison and links to a full side-by-side review (the `review` input, on by default); the two specs are encrypted in CI before upload, so the server cannot read them. The link is posted as a pull-request comment when you pass `github-token` (and grant `pull-requests: write`); otherwise, and on fork PRs where the token is read-only, it falls back to the job summary.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
permissions:
  contents: read
  pull-requests: write   # lets the action post the review link as a PR comment
jobs:
  breaking-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/breaking@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          fail-on: WARN
          github-token: ${{ github.token }}
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
| `allow-external-refs` | `false` | Resolve external `$ref`s. Defaults to `false` to prevent SSRF on untrusted pull requests. Set `true` if your spec references external URLs or loads split files by file path | `true`, `false` |
| `review` | `true` | When changes are found, upload the comparison to oasdiff.com and link to a direct side-by-side review. The two specs are encrypted in CI before upload and the decryption key stays in the URL fragment, so the server cannot read them. Set `false` to skip the upload, so no spec leaves CI | `true`, `false` |
| `github-token` | `''` | Token used to post the review link as a pull-request comment, so reviewers see it on the PR instead of only in the job summary. Pass `${{ github.token }}` and grant `permissions: pull-requests: write`. Optional; omit it to keep the link in the job summary only. Fork PRs (read-only token) fall back to the summary | `${{ github.token }}` |

### Generate a changelog

Outputs all changes (breaking and non-breaking) between two specs. When changes are found it also uploads the comparison and links to a full side-by-side review (the `review` input, on by default); the two specs are encrypted in CI before upload, so the server cannot read them. The link is posted as a pull-request comment when you pass `github-token` (and grant `pull-requests: write`); otherwise, and on fork PRs where the token is read-only, it falls back to the job summary.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
permissions:
  contents: read
  pull-requests: write   # lets the action post the review link as a PR comment
jobs:
  changelog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/changelog@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          github-token: ${{ github.token }}
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
| `allow-external-refs` | `false` | Resolve external `$ref`s. Defaults to `false` to prevent SSRF on untrusted pull requests. Set `true` if your spec references external URLs or loads split files by file path | `true`, `false` |
| `review` | `true` | When changes are found, upload the comparison to oasdiff.com and link to a direct side-by-side review. The two specs are encrypted in CI before upload and the decryption key stays in the URL fragment, so the server cannot read them. Set `false` to skip the upload, so no spec leaves CI | `true`, `false` |
| `github-token` | `''` | Token used to post the review link as a pull-request comment, so reviewers see it on the PR instead of only in the job summary. Pass `${{ github.token }}` and grant `permissions: pull-requests: write`. Optional; omit it to keep the link in the job summary only. Fork PRs (read-only token) fall back to the summary | `${{ github.token }}` |

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
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/diff@v0
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
| `allow-external-refs` | `false` | Resolve external `$ref`s. Defaults to `false` to prevent SSRF on untrusted pull requests. Set `true` if your spec references external URLs or loads split files by file path | `true`, `false` |

### Validate a single spec

Validates one OpenAPI spec against the OpenAPI and JSON Schema rules and writes an inline GitHub annotation for each finding. Unlike the other actions it takes a single spec, not a base/revision pair. Findings are classified by severity (error, warning, info); by default the workflow fails only on errors.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: oasdiff/oasdiff-action/validate@v0
        with:
          spec: 'openapi.yaml'
```

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `spec` | — (required) | Path to the OpenAPI spec to validate | file path, URL, git ref |
| `fail-on` | `''` | Fail with exit code 1 when a finding is at or above this severity (empty uses the oasdiff default, `ERR`) | `ERR`, `WARN`, `INFO` |
| `allow-external-refs` | `false` | Resolve external `$ref`s. Defaults to `false` to prevent SSRF on untrusted pull requests. Set `true` if your spec references external URLs | `true`, `false` |

For a non-blocking, report-only run, leave `fail-on` and set `continue-on-error: true` on the step. Outputs: `findings` (total), `error_count`, `warning_count`, `info_count`.

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
- uses: oasdiff/oasdiff-action/breaking@v0
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
- uses: actions/checkout@v7
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
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/pr-comment@v0
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
| `allow-external-refs` | `false` | Resolve external `$ref`s. Defaults to `false` to prevent SSRF on untrusted pull requests. Set `true` if your spec references external URLs or loads split files by file path | `true`, `false` |

[Get oasdiff Pro →](https://www.oasdiff.com/pricing)

## Pro: Verify your setup

`oasdiff/oasdiff-action/verify` is a read-only check that confirms your setup works end to end. It posts no PR comment and sets no commit status. Run it on demand from the **Actions** tab (the "Run workflow" button).

Add it to the same workflow as `pr-comment`, guarded by event type, so one file handles both: `pr-comment` on pull requests, and `verify` when you click "Run workflow".

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
  workflow_dispatch:
jobs:
  pr-comment:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/pr-comment@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
  verify:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.event.repository.default_branch }}
      - uses: oasdiff/oasdiff-action/verify@v0
        with:
          base: 'origin/${{ github.event.repository.default_branch }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
```

The verify run renders a checklist in the workflow **Step Summary**:

- ✅ GitHub Actions workflow is running
- ✅ Connected to oasdiff (your `OASDIFF_TOKEN` secret)
- ✅ oasdiff GitHub App installed on the repo
- ✅ OpenAPI spec found and compared

It exits non-zero with a one-line hint for any check that fails, so a verify run is a clear pass/fail. (Reviewer access is checked separately on your setup page.)

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `base` | — (required) | Path to the base (old) OpenAPI spec | file path, URL, git ref |
| `revision` | — (required) | Path to the revised (new) OpenAPI spec | file path, URL, git ref |
| `oasdiff-token` | — (required) | oasdiff API token, [sign up at oasdiff.com](https://www.oasdiff.com/pricing) | — |
| `allow-external-refs` | `false` | Resolve external `$ref`s. Defaults to `false`; set `true` if your spec references external URLs | `true`, `false` |
