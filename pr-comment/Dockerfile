FROM tufin/oasdiff:v1.15.3
RUN apk add --no-cache curl jq
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
