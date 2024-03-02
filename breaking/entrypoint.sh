#!/bin/sh
set -e

write_output () {
    local output="$1"
    local truncate_if_needed="$2"
    if [ -n "$output_to_file" ]; then
        echo "$output" >> "$output_to_file"
    fi
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    if [ "$truncate_if_needed" = "true" ]; then
        size=$(echo "$output" | wc -c)
        if [ "$size" -ge "1000000" ]; then
            echo "WARN: diff exceeds the 1MB limit, truncating output..." >&2
            output=$(echo "$output" | head -c 1000000)
        fi
    fi 
    echo "$output" >>"$GITHUB_OUTPUT"
}

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"
readonly include_checks="$4"
readonly include_path_params="$5"
readonly deprecation_days_beta="$6"
readonly deprecation_days_stable="$7"
readonly exclude_elements="$8"
readonly output_to_file="$9"

echo "running oasdiff breaking... base: $base, revision: $revision, fail_on_diff: $fail_on_diff, include_checks: $include_checks, include_path_params: $include_path_params, deprecation_days_beta: $deprecation_days_beta, deprecation_days_stable: $deprecation_days_stable, exclude_elements: $exclude_elements"

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
write_output "breaking<<$delimiter"

if [ -n "$flags" ]; then
    output=$(oasdiff breaking "$base" "$revision" "$flags" | head -n 1)
else
    output=$(oasdiff breaking "$base" "$revision" | head -n 1)
fi

if [ -n "$output" ]; then
    write_output "$output" "true"
else
    write_output "No breaking changes"
fi

write_output "$delimiter"

# *** github action step output ***

# Updating GitHub Action summary with formatted output
flags="${flags} --format githubactions"
# Writes the summary to log and updates GitHub Action summary
oasdiff breaking "$base" "$revision" "$flags"
