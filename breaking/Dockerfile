FROM tufin/oasdiff:v1.15.2
RUN apk add --no-cache jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
