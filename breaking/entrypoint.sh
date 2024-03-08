#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly fail_on="$3"
readonly include_checks="$4"
readonly include_path_params="$5"
readonly deprecation_days_beta="$6"
readonly deprecation_days_stable="$7"
readonly exclude_elements="$8"

echo "running oasdiff breaking... base: $base, revision: $revision, fail_on: $fail_on, include_checks: $include_checks, include_path_params: $include_path_params, deprecation_days_beta: $deprecation_days_beta, deprecation_days_stable: $deprecation_days_stable, exclude_elements: $exclude_elements"

# Build flags to pass in command
flags=""
if [ -z "$fail_on" ]; then
    flags="${flags} --fail-on $fail_on"
fi
if [ "$include_path_params" = "true" ]; then
    flags="${flags} --include-path-params"
fi
if [ -n "$include_checks" ]; then
    flags="${flags} --include-checks $include_checks"
fi
if [ -n "$deprecation_days_beta" ]; then
    flags="${flags} --deprecation-days-beta $deprecation_days_beta"
fi
if [ -n "$deprecation_days_stable" ]; then
    flags="${flags} --deprecation-days-stable $deprecation_days_stable"
fi
if [ "$exclude_elements" != "" ]; then
    flags="${flags} --exclude-elements ${exclude_elements}"
fi
echo "flags: $flags"

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "breaking<<$delimiter" >>$GITHUB_OUTPUT

if [ -n "$flags" ]; then
    output=$(oasdiff breaking "$base" "$revision" $flags | head -n 1)
else
    output=$(oasdiff breaking "$base" "$revision" | head -n 1)
fi

if [ -n "$output" ]; then
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    size=$(echo "$output" | wc -c)
    if [ "$size" -ge "1000000" ]; then
        echo "WARN: breaking exceeds the 1MB limit, truncating output..." >&2
        output=$(echo "$output" | head -c 1000000)
    fi
    echo "$output" >>$GITHUB_OUTPUT
else
    echo "No breaking changes" >>$GITHUB_OUTPUT
fi

echo "$delimiter" >>$GITHUB_OUTPUT

# *** github action step output ***

# Updating GitHub Action summary with formatted output
flags="${flags} --format githubactions"
# Writes the summary to log and updates GitHub Action summary
oasdiff breaking "$base" "$revision" $flags
