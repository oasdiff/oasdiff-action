FROM tufin/oasdiff:v1.15.0-openapi31.beta.1
RUN apk add --no-cache jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
