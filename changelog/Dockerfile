FROM tufin/oasdiff:main
RUN apk add --no-cache expect
ENV PLATFORM github-action
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
