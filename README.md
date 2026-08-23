# Freenet node in Docker

A minimal Docker image for running a [Freenet](https://freenet.org) node, a peer-to-peer
network for censorship-resistant, decentralized applications. This image runs the stock
installer and stays out of the way: no pinned version, no tuning, the node manages its own
updates.

Image: [`soudasuwa/freenet`](https://hub.docker.com/r/soudasuwa/freenet) · Design notes for
contributors: [DESIGN.md](DESIGN.md)

- **Updates itself**: the node checks for new releases and applies them on its own, nothing
  to script or remember.
- **Recovers from a bad update**: if a new version crash-loops, it's rolled back to the last
  known-good binary automatically.
- **One volume, your whole node**: binary, config, data, and identity all live in a single
  volume, so backing it up or moving it is the whole node.
- **Standard or public, same image**: one flag switches between a NAT'd peer and a node with
  a stable, dialable port.

## Run it

```bash
docker run -d --name freenet \
  --restart unless-stopped \
  -v freenet:/home/freenet \
  soudasuwa/freenet
```

Or with Compose:

```yaml
services:
  freenet:
    image: soudasuwa/freenet
    restart: unless-stopped
    volumes:
      - freenet:/home/freenet
volumes:
  freenet:
```

This runs a **standard node**: it picks a random port and reaches the network through NAT
hole-punching, like most peers. No configuration needed.

## Running a public node

A public node uses a fixed, published port so other peers can connect to it directly:

```bash
docker run -d --name freenet \
  --restart unless-stopped \
  -v freenet:/home/freenet \
  -e NETWORK_PORT=31337 -p 31337:31337/udp \
  soudasuwa/freenet
```

Full example: [docker-compose.public.yml](docker-compose.public.yml)
(vs. the standard [docker-compose.yml](docker-compose.yml)).

## Checking on it

```bash
docker exec freenet peers        # connected peer count
docker exec freenet fdev query   # full peer table
docker logs -f freenet
```

## Resetting

Removing the `freenet` volume wipes the binary, config, data, and node identity: the
container equivalent of `freenet uninstall --purge`.
