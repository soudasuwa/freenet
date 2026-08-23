# Design notes

Why this container is built the way it is. See the [README](README.md) to just run it.

## How it works

Freenet keeps everything under `$HOME`: binaries, config, data, logs (same layout as the
[uninstall page](https://freenet.org/uninstall/) lists), so one volume at `/home/freenet`
persists the whole installation. First boot is detected by the only thing that matters: is
`~/.local/bin/freenet` missing? The image itself is versionless, holding no Freenet release,
just the ability to fetch one.

## Image

`docker-compose.yml`/`docker-compose.public.yml` pull the prebuilt `soudasuwa/freenet` image
([publish workflow](.github/workflows/publish.yml)) instead of building locally, so deploy
platforms that rebuild on every deploy don't have to. Swap `image:` for `build: .` to build
from source.

## Updates and crash-loop rollback

A node that finds a new release exits **42** to request an update rather than applying one
itself. `entrypoint.sh` runs `freenet update` before starting the node, so: exit 42 → Docker
restarts the container → update applies → node starts on the new version. Docker is the whole
supervisor.

The same handoff carries crash-loop rollback: `freenet update` only reverts to the last
known-good binary when told how the node stopped, via `FREENET_POST_STOP_EXIT_CODE`. So
`entrypoint.sh` records the exit status and forwards it next boot. That's why it doesn't
`exec` the node (it must outlive it to observe the exit) and why `init: true` is set (PID 1 is
now a shell, not the node). `stop_grace_period: 60s` exists so a slow SIGTERM drain isn't
mistaken for a crash and doesn't trigger a spurious rollback.

## No published ports, by design (standard node)

The node picks a random UDP port on first boot and persists it: fixed, but not knowable in
advance, so there's nothing to publish. This isn't a workaround: the
[whitepaper](https://github.com/freenet/paper-1) treats NAT'd peers without a stable address as
the normal case, reaching the network via hole-punching. Only gateways need a stable address.

## Logging

The node prints only `CRITICAL` to console (files still get everything); the image sets
`FREENET_LOG_TO_STDERR=1` so `docker logs` isn't empty. It's chatty (~5 MB/hour), hence the
Docker log retention cap. Quiet it with `LOG_LEVEL: warn`; compact JSON lines with
`FREENET_LOG_FORMAT: json`.

## What `peers` actually counts

Transport connections (same as `fdev query`), not ring topology. They usually match, but a
node can hold transport connections with an empty ring (logged as `RING_TRANSPORT_DESYNC`).
So the healthcheck is a liveness signal, not proof the node is routing. Don't wire
`unhealthy` to a restart: an isolated node recovers on its own, and restarting just resets
its bootstrap clock.

## The client API is not exposed

Port 7509 is fully privileged (contract state, identities, keys) and binds loopback by default
per [GHSA-824h-7x5x-wfmf](https://github.com/freenet/freenet-core/security/advisories/GHSA-824h-7x5x-wfmf).
Widen it only with `FREENET_WS_API_ADDRESS=::` behind an authenticating reverse proxy. It also
serves a status dashboard at `/`. Don't scrape its `<title>` for a peer count, since the
number disappears at zero connections; use `peers` instead.
