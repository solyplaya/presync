FROM alpine:latest

RUN apk add --no-cache \
        b3sum \
        bash \
        dash \
        oksh\
        shellcheck \
        shunit2 \
        sqlite \
        xxhash \
        zsh \
    && addgroup -g 1000 tester \
    && adduser -D -u 1000 -G tester tester

USER tester

WORKDIR /home/tester