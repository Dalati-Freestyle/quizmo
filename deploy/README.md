# Deploy a Quizmo release

The release contains a Linux **amd64/x86-64** backend image, including the
browser host/editor, player and TV clients. It is not an ARM64 image. Windows
Docker Desktop must use Linux containers. Active rooms live in memory;
restarts end games. Quiz libraries remain in the host browser's storage.

## Use the GitHub Container Registry

Copy `.env.example` to `.env`. Set `QUIZMO_DOMAIN` to your domain (no scheme or
path) and `QUIZMO_IMAGE` to the exact image reference from the GitHub Release,
for example `ghcr.io/owner/repository-server:1.1.0`. Pin a version rather than
`latest` for controlled upgrades.

From this deployment directory:

```sh
docker compose --env-file .env -f compose.yaml pull
docker compose --env-file .env -f compose.yaml up -d --no-build
docker compose --env-file .env -f compose.yaml logs -f
```

If the GHCR package is private, authenticate with a GitHub token with
`read:packages`, or use the release archive instead. A repository administrator
can make the package public in its package settings. Repository visibility
does not automatically make a new package public.

## Use the downloadable image archive (no GHCR login)

Download `quizmo-VERSION-docker-linux-amd64.tar.gz` and verify it against the
release's `SHA256SUMS.txt`. Import it with:

```sh
docker load --input quizmo-VERSION-docker-linux-amd64.tar.gz
```

Set `QUIZMO_IMAGE=quizmo-server:VERSION` in `.env`, then start without pulling
the Quizmo image or trying to build missing source files:

```sh
docker compose --env-file .env -f compose.yaml up -d --no-build --pull never
```

If Caddy is not installed locally yet, first run `docker compose pull caddy`.
The release ZIP contains these deployment files; application source code is
not needed when using `--no-build`.

## Network and TLS

Open `https://YOUR_DOMAIN`. Guests use room invitation links; TVs use their
`/tv` suffix. The same deployment works in a LAN with DNS and a valid HTTPS
certificate/reverse proxy. Internet exposure additionally requires suitable
DNS, firewall/router configuration and reachable TLS endpoints. The included
Caddy configuration automatically obtains public certificates; a private-only
LAN generally needs your own HTTPS setup or an appropriate DNS challenge.
Plain HTTP via a LAN IP is intentionally rejected; HTTP is only allowed for
localhost development.

Only Caddy publishes ports 80/443. Preserve its certificate volumes. Behind
your own reverse proxy, set `PUBLIC_ORIGIN=https://YOUR_DOMAIN`, forward HTTP
and WebSocket upgrades to container port 8080, and retain the security headers
from `Caddyfile`. Bind the backend's published port only on loopback or the
private interface used by that proxy. Never expose an unprotected HTTP port
directly to the internet. The backend health endpoint is `/api/health`.

For local-only development without TLS:

```sh
docker run --rm -p 127.0.0.1:8080:8080 -e PUBLIC_ORIGIN=http://localhost:8080 quizmo-server:VERSION
```

Open exactly `http://localhost:8080`. Other devices cannot use this loopback-only
example. Hosting is invitation-based, not account-authenticated; treat room
links as secrets and use a suitable proxy/firewall/rate limiting for public
deployments.
