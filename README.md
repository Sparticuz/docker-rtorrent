# rTorrent on Alpine
This fork runs upstream rTorrent/libtorrent on Alpine. It keeps the original container's mount layout and exposes XML-RPC and JSON-RPC over a shared Unix SCGI socket for [Flood](https://github.com/jesec/flood) or an HTTP proxy. No web UI is bundled.

## Published image

GitHub Actions builds and tests both `linux/amd64` and `linux/arm64` on native runners before publishing a multi-platform image to `ghcr.io/sparticuz/docker-rtorrent`. Docker selects the matching architecture when pulling. Each tested architecture is also published as `sha-<full-commit-sha>-<architecture>`.

## Configuration

The container copies its default configuration only if `/config/.rtorrent.rc` does not exist.

```sh
mkdir -p config downloads session watch socket
docker run --rm -v "$(pwd)/config:/config" ghcr.io/sparticuz/docker-rtorrent:latest bootstrap
```

Existing configs are not migrated automatically. When migrating to this image, use `schedule` instead of `schedule2` and `network.listen.port.*` instead of `network.port_*`. Remove `encoding.add`, `trackers.use_udp.set`, and obsolete `network.http.max_open.set` / `network.max_open_files.set` settings. The default config now leaves file/socket allocation to upstream and uses `protocol.encryption.set = allow`.

## Running

Run the published image directly:

```
docker run -d --stop-timeout 120 \
	-v ./downloads:/downloads \
	-v ./session:/session \
	-v ./watch:/watch \
	-v ./config:/config \
	-v rtorrent-sock:/socket \
	-p 49161:49161 \
	-e PUID=1000 -e PGID=1000 \
	ghcr.io/sparticuz/docker-rtorrent:latest
```

Or use Docker Compose:

```yaml
services:
  rtorrent:
    image: ghcr.io/sparticuz/docker-rtorrent:latest
    volumes:
      - "./downloads:/downloads"
      - "./session:/session"
      - "./watch:/watch"
      - "./config:/config"
      - "rtorrent-sock:/socket"
    ports:
      - "49161:49161"
    environment:
      - PUID=1000
      - PGID=1000
volumes:
  rtorrent-sock: {}
```

Save it as `docker-compose.yml` and run `docker compose up -d` after preparing directory ownership.

### Flood integration

Use [Flood's official container instructions](https://github.com/jesec/flood#docker) and [container examples](https://github.com/jesec/flood/discussions/120). To connect Flood to this image:

- Mount the same socket volume into both containers at `/socket`. If using separate Compose projects, reference the same external volume rather than creating project-local volumes.
- Select rTorrent with Unix socket `/socket/rtorrent.sock`. Run Flood with the matching UID or GID so it can access the socket.
- Mount the same downloads directory at `/downloads` in both containers, with permissions that allow Flood to manage the files.

## Volumes

| Volume     | Explanation                              |
| ---------- | ---------------------------------------- |
| /downloads | Your downloads.                          |
| /session   | rTorrent specific folder. Used for persistence accross restarts |
| /watch     | Watch folder for .torrent files          |
| /config    | rTorrent configuration                   |
| /socket    | The rTorrent Unix socket                 |

## Environment Variables

When started as root, the entrypoint uses `PUID` and `PGID` (default `1000:1000`), prepares the writable directory roots, and drops privileges with `su-exec`. It does not recursively change existing files or change `/downloads` ownership. Prepare downloads and any existing session/watch files with the correct ownership before startup.

With Docker `--user UID:GID`, the process runs directly as that user. Supply a readable config (a read-only bind mount is supported), pre-create `/watch/load` and `/watch/start`, and make `/session`, `/socket`, `/watch`, and `/downloads` writable by that user. Use pre-owned bind mounts or `volume-nocopy` for prepared named volumes: Docker can reset an empty volume's directory ownership when copying image contents into it.

Only one rTorrent instance may own a session directory. The entrypoint never deletes `rtorrent.lock`; do not delete a lock to bypass a running instance. Before migrating existing torrents, stop the old instance gracefully and back up its session and configuration. Keep that backup for rollback rather than assuming rewritten resume files work with an older client.

## Ports

Publish `49161/tcp` for incoming peers. DHT is disabled by default; if enabled with `dht.port.set = 49160`, also publish `49160/udp`. The RPC endpoint is `/socket/rtorrent.sock` with mode `0770`, not a published TCP port. Give Flood/the proxy the matching UID or GID; socket access grants control of rTorrent and must be restricted to trusted clients.

## Development / local build

From the repository root, build and check a local image instead of using GHCR:

```sh
docker build -t rtorrent:local .
docker run --rm --network=none \
  --mount type=bind,src="$(pwd)/tests",dst=/tests,readonly \
  --entrypoint sh rtorrent:local /tests/entrypoint.sh
```

Use `rtorrent:local` in place of the GHCR image in the commands above. For local Compose development, save the Compose file in the repository root, replace the rTorrent service's `image` with `rtorrent:local`, add `build: .`, and run Compose with `--build`.

The multi-stage build verifies both upstream source archives and enables TinyXML2 support. This also provides `system.listMethods`, which Flood needs even when probing JSON-RPC. Clang is used to avoid an Alpine GCC compiler crash in `command_system.cc`; no compiler is included in the runtime image.

The regression checks run in disposable containers without production volumes. They cover repeated bootstrap, existing config and lock preservation, failed initialization, invalid IDs, rejection of a second writer, and graceful shutdown.
