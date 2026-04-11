FROM tufin/oasdiff:v1.13.5
RUN apk add --no-cache jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
