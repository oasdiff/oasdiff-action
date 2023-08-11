# oasdiff-action
[![CI](https://github.com/oasdiff/oasdiff-action/actions/workflows/test.yaml/badge.svg)](https://github.com/oasdiff/oasdiff-action/actions)

GitHub actions for comparing OpenAPI specs and detect breaking changes, based on [oasdiff](https://github.com/Tufin/oasdiff) tool

## How to use?
Depends on your use case:

### Generate a diff report
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  id: test_ete
  uses: oasdiff/oasdiff-action/diff@main
  with:
    base: 'specs/base.yaml'
    revision: 'specs/revision.yaml'
    format: 'text'
    fail-on-diff: false
```

### Check for breaking API changes, and fail if any are found
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  id: test_ete
  uses: oasdiff/oasdiff-action/check-breaking@main
  with:
    base: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test1.yaml
    revision: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test3.yaml
    fail-on-diff: true
```

#### Include optional breaking change checks
In order to ensure even stricter breaking policies, oasdiff provides with a few optional checks.
Complete list can be found [here](https://github.com/Tufin/oasdiff/blob/main/BREAKING-CHANGES.md#optional-breaking-changes-checks).

These checks can be added by filling the `include-checks` argument in the action like the following:
```
- name: Running OpenAPI Spec diff action
  id: test_ete
  uses: oasdiff/oasdiff-action/check-breaking@main
  with:
    base: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test1.yaml
    revision: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test3.yaml
    fail-on-diff: true
    include-checks: "response-non-success-status-removed,api-operation-id-removed"
```

### Generate a changelog
Copy and paste the following snippet into your build .yml file:
```
- name: Running OpenAPI Spec diff action
  id: test_ete
  uses: oasdiff/oasdiff-action/changelog@main
  with:
    base: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test1.yaml
    revision: https://raw.githubusercontent.com/Tufin/oasdiff/main/data/openapi-test3.yaml
```
