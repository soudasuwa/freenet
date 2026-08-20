# Freenet node in Docker

A minimal Alpine container that runs the stock `freenet.org/install.sh` on first boot and
then gets out of the way. No pinned version, no tuning flags, no environment overrides —
the node runs on its own defaults.

```bash
docker compose up -d
```

## How it works

Freenet keeps everything under `$HOME` — binaries in `~/.local/bin`, config in
`~/.config/freenet`, data in `~/.local/share/freenet`, logs in `~/.local/state/freenet`
(the same paths the [uninstall page](https://freenet.org/uninstall/) lists). So a single
volume mounted at `/home/freenet` persists the entire installation.

"Is this the first boot?" is answered by the only thing that matters: **is the binary
there?** If `~/.local/bin/freenet` is missing, install it; otherwise skip. That makes the
image versionless — it holds no Freenet release, just the ability to fetch one.

## Updates

A node that spots a new release exits with code **42** to *request* an update — it never
applies one itself. That is why `entrypoint.sh` runs `freenet update` before starting the
node: the node exits 42, Docker's restart policy brings the container back, the update is
applied, and the node starts on the new version. Docker is the supervisor, so no external
tooling is needed. (`update` exits 2 when already current, which is not a failure.)

Verified end to end: a deliberately installed 0.2.126 was upgraded in place to 0.2.128.

The same handoff carries **crash-loop rollback**. `freenet update` only counts crashes and
reverts to the last known-good binary when the supervisor tells it how the node stopped,
via `FREENET_POST_STOP_EXIT_CODE` — upstream's systemd unit sets it from `ExecStopPost`. So
`entrypoint.sh` records the node's exit status to `~/.local/state/freenet/.last-exit` and
forwards it into the next boot's `update` call.

That is why the entrypoint does **not** `exec` the node: it has to outlive it to observe how
it stopped. Restoring the `exec` would silently disable rollback and leave a bad release
looping forever, since `restart: unless-stopped` brings the container back regardless. PID 1
is a shell as a result, so `init: true` puts a real reaper behind it.

Not every exit is a crash: 0, 2, 42, 43 and 44 are not, everything else — signal deaths
included — is. Hence `stop_grace_period: 60s`. The node drains in-flight operations on
SIGTERM, and a SIGKILL at Docker's 10s default would be recorded as a crash and could
trigger a spurious rollback on a perfectly good version.

## No published ports, by design

With no `--network-port` the node picks a free UDP port on first boot and writes it to
`~/.config/freenet/config.toml`, so it is fixed from then on but not knowable in advance.
A hardcoded `ports:` mapping would therefore publish nothing, and none is set.

This is not a workaround. The [whitepaper](https://github.com/freenet/paper-1) treats peers
without a stable inbound address as the normal case:

> Most peers operate behind consumer NAT and do not have a stable inbound address. The
> transport supports hole-punching: when two peers want to connect and at least one is
> behind a NAT, both peers send hello packets toward each other's observed external
> addresses simultaneously. — §6.2, NAT Traversal and Bootstrap

Gateways are the role that needs a stable address; a regular peer does not. Confirmed in
practice — this node reached 17 ring connections with nothing published.

## Logging

The node writes rotating files to `~/.local/state/freenet/` and prints only `CRITICAL` to
the console, which would leave `docker compose logs` empty. The image sets
`FREENET_LOG_TO_STDERR=1` so it behaves like a normal container; the files are still written.

```bash
docker compose logs -f
```

It is chatty — roughly 150 events/min at steady state, ~5 MB/hour — so `docker-compose.yml`
caps Docker's retention at 5 × 20 MB (about 18 hours). To make it quiet, set
`LOG_LEVEL: warn` in the service `environment`; for compact one-line records instead of the
default multi-line human-readable format, set `FREENET_LOG_FORMAT: json`.

## Checking on the node

`fdev` is installed alongside the node, and `fdev query` asks it directly rather than
inferring anything from the logs:

```bash
docker compose exec -T freenet /home/freenet/.local/bin/fdev query
```

It prints the connected peers with their identifiers and addresses, plus any application
subscriptions. Progress lines go to stderr, so add `2>/dev/null` for just the table. For the
connection count on its own:

```bash
docker compose exec -T freenet peers
```

`peers` is a small script in the image that wraps the same query. It prints the count and
carries the answer in its exit status: 0 with at least one peer, 1 when the node answers but
is isolated, 3 when it could not be queried at all. That last distinction is the reason it
exists -- "isolated" and "node is down" are both unhealthy but call for different responses.

Note what it counts: **transport** connections, which is what `fdev query` reports. That is
the node's connection map, not its ring topology. In normal operation the two agree, but they
come apart precisely when something is wrong — a node can hold transport connections while
its ring is empty, and `peers` will count them. The node logs that case as
`RING_TRANSPORT_DESYNC`; there is no non-HTML endpoint that reports ring state directly.

So the healthcheck built on it is a liveness signal, not a guarantee the node is routing.
Docker does not restart unhealthy containers on its own — and it should not be wired to,
since restart cycling is what provokes the isolation this is meant to catch. `docker compose
ps` reports the state.

## The client API is not exposed

Port 7509 is fully privileged — it can read and modify contract state, identities and keys —
and binds loopback by default per
[GHSA-824h-7x5x-wfmf](https://github.com/freenet/freenet-core/security/advisories/GHSA-824h-7x5x-wfmf).
Publishing it as-is would not even work (it listens on the container's own loopback). Only
widen it with `FREENET_WS_API_ADDRESS=::` behind an authenticating reverse proxy.

The node also serves a status dashboard at `/` on that port, which `docker compose exec`
reaches without publishing anything:

```bash
docker compose exec -T freenet curl -s http://127.0.0.1:7509/
```

Do not scrape its `<title>` for a connection count. The number only appears while
connections are above zero; at zero the title is a warning glyph instead, so a title-based
check goes silent in exactly the situation worth noticing. Use `fdev query`.

## Resetting

`docker compose down -v` removes the volume, which is the container equivalent of
`freenet uninstall --purge`: binaries, config, data and node identity all go with it.
