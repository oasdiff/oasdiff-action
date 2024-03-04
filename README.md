# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub actions for comparing OpenAPI specs and detect breaking changes, based on [oasdiff](https://github.com/Tufin/oasdiff) tool

## How to use?
Depending on your use case, refer below for instructions on generating reports for differences, breaking changes and changelog.

### Generate a diff report
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  uses: oasdiff/oasdiff-action/diff@main
  with:
    base: 'specs/base/base.yaml'
    revision: 'specs/revision/revision.yaml'
```

This action supports additional arguments that are converted to parameters for the `oasdiff` CLI.

| CLI | Action input | Default |
|--------|--------|--------|
| --fail-on-diff | fail-on-diff | false |
| --format | format | yaml |
| --include-path-params | include-path-params | false |
| --exclude-elements | exclude-elements | '' |
| --composed                | composed                | false   |

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

| CLI                       | Action input            | Default |
|---------------------------|-------------------------|---------|
| --fail-on WARN            | fail-on-diff            | true    |
| --include-checks          | include-checks          | csv     |
| --include-path-params     | include-path-params     | false   |
| --deprecation-days-beta   | deprecation-days-beta   | 31      |
| --deprecation-days-stable | deprecation-days-stable | 180     |
| --exclude-elements        | exclude-elements        | ''      |
| --composed                | composed                | false   |

This action delivers a summary of breaking changes, accessible as a GitHub step output named `breaking`.

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
| --exclude-elements    | exclude-elements    | ''    |
| --composed            | composed            | false   |