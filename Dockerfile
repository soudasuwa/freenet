FROM alpine:3.22

# Everything install.sh needs: it is POSIX sh and fetches a static musl binary.
RUN apk add --no-cache ca-certificates curl \
 && adduser -D -u 1000 freenet

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Reports the connected peer count and exits nonzero when there is none, so it
# serves as both the healthcheck and a command you can run to look.
COPY peers.sh /usr/local/bin/peers
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/peers

USER freenet
# SHELL             install.sh reads it and aborts under `set -u` if unset.
# PATH              adds where install.sh puts freenet and fdev, so they are
#                   runnable by name. Appended, not prepended: the volume is
#                   mutable, and it has no business shadowing system binaries.
# LOG_TO_STDERR     otherwise only CRITICAL reaches the console, leaving
#                   `docker compose logs` empty. Log files are unaffected.
# SUPERVISED        marks that something will catch the exit-42 update request,
#                   which entrypoint.sh and the restart policy do. Without it
#                   every update logs an ERROR claiming it will not be applied.
ENV HOME=/home/freenet \
    SHELL=/bin/sh \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/freenet/.local/bin \
    FREENET_LOG_TO_STDERR=1 \
    FREENET_SUPERVISED=1
WORKDIR /home/freenet

# Freenet keeps its binaries, config, data, cache and state under $HOME, so one
# volume here persists the whole installation.
VOLUME ["/home/freenet"]

# No EXPOSE: with stock defaults the node picks its UDP port on first boot.

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
