#!/bin/sh
set -e

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

write_output () {
    local output="$1"
    if [ -n "$output_to_file" ]; then
        local file_output="$2"
        if [ -z "$file_output" ]; then
            file_output=$output
        fi
        echo "$file_output" >> "$output_to_file"
    fi
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    size=$(echo "$output" | wc -c)
    if [ "$size" -ge "1000000" ]; then
        echo "WARN: diff exceeds the 1MB limit, truncating output..." >&2
        output=$(echo "$output" | head -c 1000000)
    fi
    echo "$output" >>"$GITHUB_OUTPUT"
}

readonly base="$1"
readonly revision="$2"
readonly include_path_params="$3"
readonly exclude_elements="$4"
readonly filter_extension="$5"
readonly composed="$6"
readonly flatten_allof="$7"
readonly output_to_file="$8"
readonly prefix_base="$9"
readonly prefix_revision="${10}"
readonly case_insensitive_headers="${11}"
readonly format="${12}"
readonly template="${13}"
readonly level="${14}"
readonly allow_external_refs="${15}"
readonly review="${16}"

echo "running oasdiff changelog base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements, filter_extension: $filter_extension, composed: $composed, flatten_allof: $flatten_allof, output_to_file: $output_to_file, prefix_base: $prefix_base, prefix_revision: $prefix_revision, case_insensitive_headers: $case_insensitive_headers, format: $format, template: $template, level: $level"

# Build flags to pass in command
flags=""
# allow-external-refs defaults to false (safe for CI on untrusted PRs); pass
# whatever the input resolved to so the explicit action input is authoritative.
if [ -n "$allow_external_refs" ]; then
    flags="$flags --allow-external-refs=$allow_external_refs"
fi
if [ "$include_path_params" = "true" ]; then
    flags="$flags --include-path-params"
fi
if [ -n "$exclude_elements" ]; then
    flags="$flags --exclude-elements $exclude_elements"
fi
if [ -n "$filter_extension" ]; then
    flags="$flags --filter-extension $filter_extension"
fi
if [ "$composed" = "true" ]; then
    flags="$flags -c"
fi
if [ "$flatten_allof" = "true" ]; then
    flags="$flags --flatten-allof"
fi
if [ -n "$prefix_base" ]; then
    flags="$flags --prefix-base $prefix_base"
fi
if [ -n "$prefix_revision" ]; then
    flags="$flags --prefix-revision $prefix_revision"
fi
if [ "$case_insensitive_headers" = "true" ]; then
    flags="$flags --case-insensitive-headers"
fi
if [ -n "$format" ]; then
    flags="$flags --format $format"
fi
if [ -n "$template" ]; then
    flags="$flags --template $template"
fi
if [ -n "$level" ]; then
    flags="$flags --level $level"
fi
echo "flags: $flags"

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "changelog<<$delimiter" >>"$GITHUB_OUTPUT"

exit_code=0
_err=$(mktemp)
if [ -n "$flags" ]; then
    output=$(oasdiff changelog "$base" "$revision" $flags 2>"$_err") || exit_code=$?
else
    output=$(oasdiff changelog "$base" "$revision" 2>"$_err") || exit_code=$?
fi
if [ "$exit_code" -ne 0 ]; then
    [ -s "$_err" ] && cat "$_err" >&2
    # Promote a genuine failure to a Checks-tab annotation. Exit 1 is the
    # intended fail-on result (not an error); only codes >=2 are real errors.
    if [ "$exit_code" -ge 2 ] && [ -s "$_err" ]; then
        echo "::error::$(tr '\n' ' ' < "$_err")"
    fi
    # Exit code 123 = oasdiff refused a disallowed external $ref (stable
    # contract, not message text). Surface the action-specific remedy.
    if [ "$exit_code" -eq 123 ]; then
        echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
    fi
    rm -f "$_err"
    exit "$exit_code"
fi
rm -f "$_err"

if [ -n "$output" ] && ! echo "$output" | head -n 1 | grep -q "^No "; then
    write_output "$output"

    free_review_url=""
    # review (default true): upload the comparison to oasdiff.com and link
    # straight to the rendered side-by-side review. The upload is
    # zero-knowledge -- the oasdiff binary encrypts the two specs client-side
    # and the decryption key lives only in the URL #fragment, so the server
    # stores a blob it cannot read. Set review: false to skip the upload
    # entirely, so no spec ever leaves CI; the changelog output and the inline
    # annotations are unaffected either way.
    if [ "$review" != "false" ]; then
        # Reuse the same semantic flags as the diff above so the uploaded
        # comparison matches. --open prints the review URL on stdout; in CI the
        # browser-open step soft-fails. We grep the /review/e/ URL out by its
        # stable path shape (not by surrounding prose). Tolerate a non-zero
        # exit / no match so `set -e` doesn't abort the run.
        free_review_url=$(oasdiff changelog "$base" "$revision" $flags --open 2>/dev/null \
            | grep -oE 'https://[^[:space:]]+/review/e/[^[:space:]]+' | head -n 1) || true
        if [ -n "$free_review_url" ]; then
            echo "### 📋 [View these API changes in a side-by-side review](${free_review_url})" >> "$GITHUB_STEP_SUMMARY"
        else
            # review was requested but no link came back: an offline runner,
            # oasdiff.com unreachable, or an older oasdiff in the base image.
            # Warn rather than emit a link -- there's no useful local fallback
            # (if the upload failed because the host is unreachable, a manual
            # run would fail the same way), and the changelog above still stands.
            echo "::warning::oasdiff: couldn't upload the side-by-side review (the changelog still ran). Re-run the job, or set 'review: false' to skip the upload."
        fi
    fi
else
    write_output "No changelog changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"
# review_url is a single-line output, written after the multiline `changelog`
# block is closed so it doesn't get folded into that value. Empty when there
# are no changes (the notice/URL only fire then).
echo "review_url=${free_review_url:-}" >> "$GITHUB_OUTPUT"

# *** github action step output ***

