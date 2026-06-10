FROM tufin/oasdiff:v1.18.6
RUN apk add --no-cache jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
