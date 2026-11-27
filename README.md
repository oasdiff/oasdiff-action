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
- [Pull requests from forks](#pull-requests-from-forks)
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
  pull-requests: write   # lets the action post the changes as a PR comment
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
```

This compares your spec on the PR branch against the base branch and fails the workflow if any breaking changes are found. When changes are found it posts a PR comment listing them, linking to a side-by-side review; without the `pull-requests: write` permission, the link goes to the job summary instead.

---

## Versioning

The examples here pin the action at `@v0`, the moving major-version tag. It always points at the latest `v0.x.y` release, so you get every later patch and minor (including review and PR-comment improvements) automatically, with no workflow change:

```yaml
- uses: oasdiff/oasdiff-action/breaking@v0
```

`@v0` only advances on stable releases, never on prereleases. If you prefer to control upgrades yourself, pin to a specific release tag from the [Releases page](https://github.com/oasdiff/oasdiff-action/releases) and bump it when you choose. `@main` runs the unreleased tip and is meant for trying changes early, not for production.

---

## Free actions

The following actions run the oasdiff CLI directly in your GitHub runner. No account or token is required.

### Check for breaking changes

Detects changes that break existing API clients. On a pull request it writes inline annotations on the Files changed tab, posts a comment listing the changes with a link to a side-by-side review, and fails the job when a change reaches the `fail-on` severity. The two specs are encrypted in CI before the review is uploaded, so the server cannot read them.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
permissions:
  contents: read
  pull-requests: write   # lets the action post the changes as a PR comment
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
```

| Input | Default | Description |
|---|---|---|
| `base` | required | The base (old) OpenAPI spec: a file path, a URL, or a git ref such as `origin/main:openapi.yaml` |
| `revision` | required | The revised (new) OpenAPI spec, in the same forms |
| `fail-on` | `''` | Fail the job when a change is at or above this severity: `ERR` or `WARN`, or `MISSING-VERSION-BUMP` to fail only when breaking changes come without a major version increase in `info.version`. Empty never fails. This is policy rather than a fact about the run: once you have a `.oasdiff.yaml`, set it there |
| `oasdiff-token` | `''` | Your oasdiff Pro token. See [Pro: Approve and gate changes](#pro-approve-and-gate-changes) |
| `github-token` | `${{ github.token }}` | Token used to post the comment. The default is the job's own token, so you only need to grant `permissions: pull-requests: write`. Without that permission the step fails with an error saying so. Set it to `''` to keep the review link in the job summary only |
| `review` | `true` | Upload the encrypted comparison and link to the side-by-side review. Set `false` so that no spec leaves CI; annotations and the job result are unaffected |
| `config` | `''` | Path to an oasdiff config file, when `.oasdiff.yaml` is not at the repository root |
| `output-to-file` | `''` | Also write the report to this file |
| `composed` | `false` | Run in [composed mode](https://github.com/oasdiff/oasdiff/blob/main/docs/COMPOSED.md), comparing globs of spec files |
| `allow-external-refs` | `false` | Resolve external `$ref`s. Off by default to prevent SSRF on untrusted pull requests; set `true` if your spec references external URLs you trust |

These inputs describe the run, with one exception: `fail-on` is policy, and is an input so that a workflow can block a merge without a second file. How oasdiff judges the API is configuration, and it goes in [`.oasdiff.yaml`](#configuring-with-oasdiffyaml): the severity that fails the job, ignore files, severity levels, `flatten-allof`, `filter-extension`, `include-path-params`, the deprecation windows, and every other oasdiff flag. The inputs of those names that earlier versions documented still work.

### Generate a changelog

The same action, reporting every change that can affect API consumers instead of only the breaking ones. It annotates the changes at error and warning level and takes the inputs listed above; `fail-on` also accepts `INFO` here.

```yaml
      - uses: oasdiff/oasdiff-action/changelog@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
```

What the report includes and how it is rendered (`level`, `format`, `template`, path prefixes) is configuration too, set in `.oasdiff.yaml`.

### Generate a diff report

Outputs the full diff of the API definition between two specs, including documentation-only edits.

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
| `exclude-elements` | `''` | Exclude certain kinds of changes from the output | `description`, `endpoints`, `examples`, `extensions`, `summary`, `tags`, `title` (comma-separated) |
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

Action inputs cover what a run needs: which specs to compare and the tokens. Everything about how oasdiff judges the API (the severity that fails the job, ignore files, severity levels, deprecation windows) goes in `.oasdiff.yaml`, where every oasdiff flag works and the same file gives you the same answer when you run oasdiff locally.

The `breaking`, `changelog` and `diff` actions automatically pick up a `.oasdiff.yaml` file from the root of your checked-out repository. This lets you keep CLI-flag-shaped configuration in source control instead of repeating the same `with:` block in every workflow file.

Drop a `.oasdiff.yaml` next to your spec:

```yaml
# .oasdiff.yaml
fail-on: ERR
err-ignore: ./oasdiff-err-ignore.txt
severity-levels: ./oasdiff-levels.txt
```

`severity-levels` points at a file that overrides the severity of individual checks, one `check-id level` per line, where level is `err`, `warn`, `info` or `none`. Raise a check to `err` (with `fail-on: ERR`) to make it fail the build, or set it to `none` to silence it:

```
# oasdiff-levels.txt
response-non-success-status-removed    err
api-tag-removed                        none
```

`exclude-elements` and `exclude-extensions` apply to the `diff` action only. The `breaking`, `changelog` and `pr-comment` actions compare the specs in full, so that excluding part of a spec cannot remove a change from the report. To turn a check off there, set its level to `none`.

The actions read this file from the runner's `$GITHUB_WORKSPACE` (which `actions/checkout` populates), so no extra steps are needed.

**Precedence**: action `with:` inputs override `.oasdiff.yaml` values, which override built-in defaults. Setting `fail-on: ERR` in YAML and leaving the action's `fail-on:` input empty applies the YAML value; setting both lets the action input win.

**Legacy filename**: the older `oasdiff.yaml` (without the leading dot) still works as a back-compat fallback. New projects should prefer `.oasdiff.yaml` to match the dotfile convention used by `.eslintrc`, `.golangci.yml`, and similar tools.

**Explicit path**: if your config lives somewhere else, point the `config` input at it (`breaking` and `changelog`; for `diff`, set `OASDIFF_CONFIG` in the step's `env:`):

```yaml
- uses: oasdiff/oasdiff-action/breaking@v0
  with:
    base: 'origin/${{ github.base_ref }}:openapi.yaml'
    revision: 'HEAD:openapi.yaml'
    config: ./config/oasdiff.yaml
```

For the full list of supported keys and how relative paths inside the config file are resolved, see the [oasdiff configuration-file reference](https://github.com/oasdiff/oasdiff/blob/main/docs/CONFIG-FILES.md).

Available since action `v0.0.47` (which ships oasdiff `v1.15.3`).

---

## Pull requests from forks

GitHub gives a pull request from a fork a read-only token and no secrets. The actions still run, annotate and fail the job as configured; the link to the review goes to the job summary instead of a comment, and the log says so. Pro reviews on fork pull requests need the [oasdiff GitHub App](https://github.com/apps/oasdiff/installations/new).

Do not switch the workflow to `pull_request_target` to get a comment or a Pro review on fork pull requests. That event runs with your repository's secrets against a spec the fork's author wrote.

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

oasdiff Pro adds a sign-off step to the review, so a breaking change can't merge until your team approves it. It's the **same action you already run**, `breaking` or `changelog`, with your `oasdiff-token` added.

On every pull request, oasdiff posts the encrypted side-by-side review and gives each change **Approve / Reject** buttons. A commit status check named `oasdiff` blocks the merge until every breaking change is approved. Approvals are tied to the change fingerprint and carry forward across commits, with a record of who approved what and when.

[Start a free trial](https://www.oasdiff.com/start-trial) (no credit card) to get your token, then add it as an `OASDIFF_TOKEN` repository secret.

```yaml
name: oasdiff
on:
  pull_request:
    branches: [ "main" ]
permissions:
  contents: read
  pull-requests: write   # post the review comment
  statuses: write        # set the merge-gate commit status
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: git fetch --depth=1 origin ${{ github.base_ref }}
      - uses: oasdiff/oasdiff-action/breaking@v0
        with:
          base: 'origin/${{ github.base_ref }}:openapi.yaml'
          revision: 'HEAD:openapi.yaml'
          oasdiff-token: ${{ secrets.OASDIFF_TOKEN }}
```

The only difference from the free [breaking workflow](#check-for-breaking-changes) is the `oasdiff-token` secret and the `statuses: write` permission. Your specs are still encrypted in CI before upload, so the server can't read them. With `breaking`, the changes to approve are the breaking ones; use `changelog` with the same token to put every change up for review.

If your workflow sets `fail-on`, keep it. The job fails until every breaking change is approved, and passes on the next run after that, so a job that is a required check keeps blocking the merge. For a gate that clears the moment a change is approved, make the `oasdiff` status check the required one: with the GitHub App installed it updates without a new run. `fail-on: MISSING-VERSION-BUMP` is not cleared by approval.

Both actions are documented above; the one added input is:

| Input | Default | Description | Accepted values |
|---|---|---|---|
| `oasdiff-token` | `''` | Your oasdiff Pro token (the `OASDIFF_TOKEN` secret). When set, the action uploads an authenticated review, posts the approve/reject comment, and sets the `oasdiff` commit status check that gates the merge. Requires `pull-requests: write` and `statuses: write` | — |

**Optional:** install the [oasdiff GitHub App](https://github.com/apps/oasdiff/installations/new) for an instant gate (the status updates the moment a change is approved, instead of on the next CI run) and for reviews on pull requests from forks. The workflow above already posts the review and sets the gate without it.

[Get oasdiff Pro →](https://www.oasdiff.com/pricing)
