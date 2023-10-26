# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub actions for comparing OpenAPI specs and detect breaking changes, based on [oasdiff](https://github.com/Tufin/oasdiff) tool

## How to use?
Depends on your use case:

### Generate a diff report
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  uses: oasdiff/oasdiff-action/diff@main
  id: oasdiff
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'

# Followup steps can use the output and share on Slack, S3, etc: ${{ steps.oasdiff.outputs.diff }}
```

This action supports additional arguments that are converted to parameters for the `oasdiff` CLI.

| CLI | Action input | Default |
|--------|--------|--------|
| --fail-on-diff | fail-on-diff | false |
| --format | format | yaml |
| --include-path-params | include-path-params | false |

This action provides the diff as a GitHub step output named: `diff`

### Check for breaking API changes, and fail if any are found
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  uses: oasdiff/oasdiff-action/breaking@main
  with:
    base: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test1.yaml
    revision: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test3.yaml
```

Additional arguments:

| CLI                   | Action input | Default |
|-----------------------|--------|--------|
| --fail-on WARN        | fail-on-diff | true |
| --include-checks      | include-checks | csv |
| --include-path-params | include-path-params | false |

This action also provides the breaking changes as a GitHub step output named: `breaking`

### Generate a changelog
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  uses: oasdiff/oasdiff-action/changelog@main
  with:
    base: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test1.yaml
    revision: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test3.yaml
```

Additional arguments:

| CLI | Action input | Default |
|--------|--------|--------|
| --include-path-params | include-path-params | false |

This action also provides the changelog as a GitHub step output named: `changelog`
