#!/bin/sh
set -eu

BIN="$HOME/.local/bin/freenet"

# Where we record how the node stopped, for the next boot to read back. Lives
# on the volume beside the logs, so it survives the container but goes with a
# purge, like everything else Freenet owns.
STOP_FILE="$HOME/.local/state/freenet/.last-exit"

# The node never restarts itself: 42 asks to be updated, 43 means another
# instance already holds the port.
EXIT_UPDATE_NEEDED=42
EXIT_ALREADY_RUNNING=43

# First boot on a fresh volume: no binary, so install one. On every later boot
# it is already there and this is skipped.
if [ ! -x "$BIN" ]; then
	echo "==> installing freenet"
	curl -fsSL https://freenet.org/install.sh | FREENET_NO_SERVICE=1 sh
fi

# Crash-loop rollback only runs when the supervisor hands `freenet update` the
# status the node stopped with; upstream's systemd unit does it from
# ExecStopPost. Without it a bad release loops forever, because Docker restarts
# us unconditionally and nothing ever counts the crashes. We are the supervisor
# here, so we forward what the previous run recorded at the bottom of this file.
if [ -f "$STOP_FILE" ]; then
	FREENET_POST_STOP_EXIT_CODE="$(cat "$STOP_FILE")"
	export FREENET_POST_STOP_EXIT_CODE
	rm -f "$STOP_FILE"
	echo "==> previous run stopped with $FREENET_POST_STOP_EXIT_CODE"
fi

# A node that finds a new release exits 42 to ask to be updated; it never
# updates itself. Docker's restart policy brings us back here, and this applies
# the update before the node starts again. Exit 2 means "already latest".
status=0
"$BIN" update --quiet </dev/null || status=$?
if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
	echo "==> update check failed (exit $status), starting anyway"
fi
unset FREENET_POST_STOP_EXIT_CODE

# Not `exec`: we have to outlive the node to record how it stopped, which is
# the whole point of the block above. PID 1 is therefore this shell, so
# docker-compose.yml sets `init: true` to get a real reaper behind us.
mkdir -p "$(dirname "$STOP_FILE")"
"$BIN" network &
node_pid=$!

# Forward a stop signal rather than dying under it, so the node drains
# in-flight operations and exits 0 instead of being recorded as a crash.
trap 'kill -TERM "$node_pid" 2>/dev/null || true' TERM INT

# A trapped signal makes `wait` return >128 while the child is still shutting
# down, so wait again for the real status. If the child is genuinely gone, the
# >128 was a real death-by-signal and we keep it.
rc=0
while :; do
	rc=0
	wait "$node_pid" || rc=$?
	if [ "$rc" -le 128 ]; then break; fi
	if ! kill -0 "$node_pid" 2>/dev/null; then break; fi
done

echo "$rc" > "$STOP_FILE"

if [ "$rc" -eq "$EXIT_UPDATE_NEEDED" ]; then
	echo "==> update requested (exit $rc), restarting to apply it"
elif [ "$rc" -eq "$EXIT_ALREADY_RUNNING" ]; then
	# `restart: unless-stopped` brings us back whatever we exit with, so the
	# most we can do is not come back hot: another instance holds the port
	# and an immediate retry would just fight it again.
	echo "==> another instance already running (exit $rc), pausing before restart"
	sleep 30
fi

exit "$rc"
