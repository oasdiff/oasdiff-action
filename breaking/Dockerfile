FROM tufin/oasdiff:stable
RUN apk add --no-cache jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
