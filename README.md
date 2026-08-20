# Freenet node in Docker

A minimal Alpine container that runs the stock `freenet.org/install.sh` on first boot and
then gets out of the way. No pinned version, no tuning flags, no environment overrides —
the node runs on its own defaults.

```bash
docker compose up -d
```

One volume at `/home/freenet` holds the whole installation, so the image carries no Freenet
release — only the ability to fetch one. Updates apply themselves on restart.

## Checking on it

```bash
docker compose exec -T freenet peers
```

Prints the number of connected peers. Its exit status doubles as the container healthcheck:
0 with at least one connection, 1 when the node answers but is isolated, 3 when it could not
be queried at all.

```bash
docker compose logs -f
```

The node is chatty at info level (~5 MB/hour); `docker-compose.yml` caps retention at
5 × 20 MB. For the full peer table with addresses, `fdev query` is the underlying command:

```bash
docker compose exec -T freenet /home/freenet/.local/bin/fdev query
```

## Resetting

`docker compose down -v` removes the volume, which is the container equivalent of
`freenet uninstall --purge`: binaries, config, data and node identity all go with it.

## Notes

Port 7509 is a fully privileged control API and stays on loopback — see
[DESIGN.md](DESIGN.md), which also covers the update and rollback handling, why no ports are
published, and what the healthcheck does and does not tell you.
