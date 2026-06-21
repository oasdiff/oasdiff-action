# TODO(pro-review): bump to the oasdiff release that adds authenticated --open
# (--review-token / --review-meta) before merging. v1.19.1 lacks it, so the Pro
# path in entrypoint.sh cannot work until this base image is bumped.
FROM tufin/oasdiff:v1.19.1
RUN apk add --no-cache curl jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
