# Zeabur relay deployment

This deployment runs one cc-pocket relay container behind Zeabur's managed HTTP ingress (Traefik/TLS):

```text
Android app -> wss://relay.planet-corp.cn -> Zeabur ingress -> relay:9000
                                                        -> /data/relay.db
WSL daemon  -> wss://relay.planet-corp.cn --------------^
```

Do not deploy a second Traefik service. Zeabur's HTTP port and custom-domain binding provide TLS and WebSocket forwarding.

## 1. Deploy from GitHub

For the repository fork in this project, deploy the checked-in Zeabur template:

```bash
zeabur template deploy \
  --file deploy/zeabur/template.yaml \
  --project-id YOUR_PROJECT_ID \
  --var PUBLIC_DOMAIN=relay.planet-corp.cn
```

The template creates the GitHub service, port, health check, `/data` volume, and domain binding together.

To configure the same service manually instead:

1. Push the synchronized fork and these deployment files to GitHub.
2. Create a Zeabur project, preferring Hong Kong and falling back to Singapore.
3. Add a **GitHub** service from the fork's `main` branch.
4. Configure:

   | Setting | Value |
   | --- | --- |
   | `ZBPACK_DOCKERFILE_PATH` | `Dockerfile.relay` |
   | `PORT` | `9000` |
   | `JAVA_OPTS` | `-Xms64m -Xmx256m` |
   | HTTP port | `9000` |
   | Health path | `/healthz` |
   | Volume id | `relay-data` |
   | Volume path | `/data` |
   | Replicas | exactly `1` |

The relay's live WebSocket broker is process-local. SQLite persists identities, devices, pairing records, and push registrations, but it does not coordinate multiple relay replicas. Do not enable horizontal autoscaling.

Zeabur's relevant configuration references are [Dockerfile deployment](https://zeabur.com/docs/en-US/deploy/methods/dockerfile), [custom Docker images and volumes](https://zeabur.com/docs/zh-CN/deploy/methods/custom-docker-image), and [health checks](https://zeabur.com/docs/en-US/operations/monitoring/health-checks).

## 2. Bind the domain

Bind `relay.planet-corp.cn` to the service's HTTP port. The existing `*.planet-corp.cn` DNS record must resolve to the ingress target Zeabur shows for this project. Wait for Zeabur to issue a certificate, then verify:

```bash
curl -fsS https://relay.planet-corp.cn/healthz
```

The expected response is `ok`. The container itself serves plain HTTP/WS; public clients always use `https://` and `wss://`.

## 3. Verify the encrypted relay path

Build the test daemon distribution, then run the repository's isolated production smoke test. It uses a throwaway identity and pair port and cleans up its processes on exit.

```bash
JAVA_HOME=/path/to/jdk-17 ./gradlew :daemon:installDist
JAVA_HOME=/path/to/jdk-17 bash scripts/relay-smoke-prod.sh wss://relay.planet-corp.cn
```

Do not switch the real daemon until the smoke test proves the public health check, daemon attachment, E2E handshake, and encrypted round trip.

## 4. Point the WSL daemon at the relay

Install/update the existing single systemd user service; never start a second foreground daemon with `:daemon:run` or `cc-pocket-daemon run`.

```bash
cc-pocket-daemon service-install --apply --relay wss://relay.planet-corp.cn
systemctl --user status cc-pocket-daemon
cc-pocket-daemon status
```

`cc-pocket-daemon status` must report `wss://relay.planet-corp.cn` and an attached relay connection. Port `127.0.0.1:8799` must have only one listener.

Generate a full self-hosted pairing link and paste it into the existing Android app immediately:

```bash
bash scripts/pair-self-hosted.sh wss://relay.planet-corp.cn
```

Do not type the six-digit code: released apps resolve short codes through the official default relay. The full link carries the custom relay URL and a short-lived, single-use ticket.

## 5. Operate and upgrade

- Keep one replica and retain the `/data` volume across deployments.
- Back up the `relay-data` volume before every relay upgrade and periodically while in service.
- After a redeploy, repeat `/healthz`, the production smoke test, and a real Android reconnect.
- Monitor container restarts, WebSocket disconnects, disk use, and SQLite errors.
- This setup intentionally leaves FCM/APNs credentials unset. The existing Android app reconnects when active, but self-hosted background push is out of scope.
