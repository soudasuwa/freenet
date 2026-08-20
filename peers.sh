#!/bin/sh
# Print the node's connected peer count on stdout.
#
# This counts TRANSPORT connections -- what `fdev query` reports, which reads
# the node's connection map, not its ring topology. The two normally agree, but
# they diverge exactly when something is wrong: a node can hold transport
# connections while its ring is empty, which it logs as RING_TRANSPORT_DESYNC,
# and this script will cheerfully count those. Treat it as a liveness signal,
# not as proof the node is routing anything.
#
# Exit status is the check itself, so this doubles as the container
# healthcheck and as something you can read:
#
#   0  at least one connection  -- the node is talking to someone
#   1  zero connections         -- the node answers but is isolated
#   3  could not query          -- the node is down or its API unreachable
#
# (2 is skipped: Docker reserves it for healthchecks.)
set -u

FDEV="${FDEV_BIN:-$HOME/.local/bin/fdev}"

if ! out="$("$FDEV" query 2>/dev/null)"; then
	echo "0"
	echo "peers: could not query the node" >&2
	exit 3
fi

# `fdev query` prints a table with one row per peer under an `Identifier`
# header. Peer identifiers are 15+ alphanumerics; the header itself is not, so
# this counts rows without counting the heading.
count="$(printf '%s\n' "$out" | grep -cE '^\| [A-Za-z0-9]{15,}')" || count=0

echo "$count"
[ "$count" -gt 0 ]
