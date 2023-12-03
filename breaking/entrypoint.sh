#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"
readonly include_checks="$4"
readonly include_path_params="$5"
readonly deprecation_days_beta="$6"
readonly deprecation_days_stable="$7"

echo "running oasdiff breaking base: $base, revision: $revision, fail_on_diff: $fail_on_diff, include_checks: $include_checks, include_path_params: $include_path_params, deprecation_days_beta: $deprecation_days_beta, deprecation_days_stable: $deprecation_days_stable"

# Build flags to pass in command
flags=""
if [ "$fail_on_diff" = "true" ]; then
    flags="${flags} --fail-on WARN"
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
echo "flags: $flags"

# *** github action step output ***

# output name should be in the format of syntax for multiple lines:
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
    echo "$output" >>$GITHUB_OUTPUT
else
    echo "No breaking changes" >>$GITHUB_OUTPUT
fi

echo "$delimiter" >>$GITHUB_OUTPUT

# *** github action step output ***

flags="${flags} --format githubactions"
output_github_action_summary=$(oasdiff breaking "$base" "$revision" $flags)
# writes the summary to log and to github action summary
echo $output_github_action_summary
