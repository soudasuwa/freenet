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
# install.sh reads $SHELL to print PATH advice and aborts under `set -u` if it
# is unset, which it is in a container.
#
# The node logs to files under ~/.local/state/freenet and prints only CRITICAL
# lines to the console, which would leave `docker compose logs` empty. Sending
# them to stderr as well is what every other container does; the files are
# still written to the volume.
#
# The node only emits a usable warning about exit-42 updates when it can see a
# supervisor that will catch them. entrypoint.sh plus Docker's restart policy
# is exactly that contract, so claiming it is honest here; without the marker
# every update logs an ERROR saying it will not be applied, which is false.
# This only selects the warning -- the exit-45 fast-crash code is gated on a
# different marker (FREENET_SYSTEMD_FAST_CRASH) that we deliberately leave unset.
ENV HOME=/home/freenet \
    SHELL=/bin/sh \
    FREENET_LOG_TO_STDERR=1 \
    FREENET_SUPERVISED=1
WORKDIR /home/freenet

# Freenet keeps its binaries, config, data, cache and state under $HOME, so one
# volume here persists the whole installation.
VOLUME ["/home/freenet"]

# No EXPOSE: with stock defaults the node picks its UDP port on first boot.

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
