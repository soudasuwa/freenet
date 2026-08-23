# Freenet node in Docker

Minimal Alpine image running the stock `freenet.org/install.sh`. Design notes: [DESIGN.md](DESIGN.md).

```bash
docker compose up -d                                # standard node: random port, hole-punching
docker compose -f docker-compose.public.yml up -d   # public node: stable, published port
```

## Checking on it

```bash
docker compose exec -T freenet peers        # connected peer count
docker compose exec -T freenet fdev query   # full peer table
docker compose logs -f
```

## Resetting

```bash
docker compose down -v   # wipes binary, config, data, node identity
```
