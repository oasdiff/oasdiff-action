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
- [Pro: Approve and gate changes](#pro-approve-and-gate-changes)

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

## Pro: Approve and gate changes

oasdiff Pro adds a sign-off step to the review, so a breaking change can't merge until your team approves it. It's the **same `changelog` action** as above, with your `oasdiff-token` added.

On every pull request, oasdiff posts the encrypted side-by-side review and gives each change **Approve / Reject** buttons. A commit status check named `oasdiff` blocks the merge until every breaking change is approved. Approvals are tied to the change fingerprint and carry forward across commits, with a record of who approved what and when.

[Start a free trial](https://www.oasdiff.com/start-trial) (no credit card) to get your token, then add it as an `OASDIFF_TOKEN` repository secret.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
permissions:
  pull-requests: write   # post the review comment
  statuses: write        # set the merge-gate commit status
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/changelog@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
          github-token: ${{ github.token }}
```

The only difference from the free [changelog workflow](#generate-a-changelog) is the `oasdiff-token` secret and the `statuses: write` permission. Your specs are still encrypted in CI before upload, so the server can't read them.

This is the `changelog` action [documented above](#generate-a-changelog); the one added input is:

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `oasdiff-token` | `''` | Your oasdiff Pro token (the `OASDIFF_TOKEN` secret). When set, the action uploads an authenticated review, posts the approve/reject comment, and sets the `oasdiff` commit status check that gates the merge. Requires `pull-requests: write` and `statuses: write` | — |

**Optional:** install the [oasdiff GitHub App](https://github.com/apps/oasdiff/installations/new) for an instant gate (the status updates the moment a change is approved, instead of on the next CI run) and for reviews on pull requests from forks. The workflow above already posts the review and sets the gate without it.

[Get oasdiff Pro →](https://www.oasdiff.com/pricing)
