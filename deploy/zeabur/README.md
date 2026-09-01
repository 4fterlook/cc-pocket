# Zeabur relay deployment

This deployment runs one cc-pocket relay container behind Zeabur's managed HTTP ingress (Traefik/TLS):

```text
Android app -> wss://relay.planet-corp.cn -> Zeabur ingress -> relay:9000
                                                        -> /data/relay.db
WSL daemon  -> wss://relay.planet-corp.cn --------------^
```

Do not deploy a second Traefik service. Zeabur's HTTP port and custom-domain binding provide TLS and WebSocket forwarding.

## 1. Publish the private Docker image

The custom relay uses its own release line, independent of upstream cc-pocket application tags. A Git tag such as `relay-v1.0.0` publishes the private Docker image `4fterlook/cc-pocket-relay:1.0.0`. Do not reuse an upstream `vX.Y.Z` tag and do not deploy a mutable `latest` tag.

1. Create the private Docker Hub repository `4fterlook/cc-pocket-relay`.
2. In Docker Hub repository settings, make all tags immutable.
3. Create a Docker Hub access token with read/write permission for GitHub Actions and store these repository secrets:

   - `DOCKERHUB_USERNAME`: `4fterlook`
   - `DOCKERHUB_TOKEN`: the CI read/write token

4. Publish an immutable version from a reviewed commit:

   ```bash
   git tag -a relay-v1.0.0 -m "relay image 1.0.0"
   git push origin relay-v1.0.0
   ```

The `relay-image` workflow runs the protocol and relay tests, builds `Dockerfile.relay` for `linux/amd64`, and pushes the versioned image. Keep the digest printed in the workflow summary with the deployment record.

Create a separate read-only Docker Hub access token for Zeabur. Enter that token only in Zeabur's private registry credentials. Never place either token in this repository, a Zeabur template, an application environment variable, or an image layer.

## 2. Deploy a verification service from the private image

In the existing Zeabur project, add a **Docker Image** service with the following settings. Keep the checked-in Git deployment as the production baseline until verification finishes.

| Setting | Value |
| --- | --- |
| Image | `4fterlook/cc-pocket-relay:<version>` |
| Registry username | `4fterlook` |
| Registry password | read-only `DOCKERHUB_TOKEN` created for Zeabur |
| `PORT` | `9000` |
| `JAVA_OPTS` | `-Xms64m -Xmx256m` |
| HTTP port | `9000` |
| Health path | `/healthz` |
| Volume id | `relay-data` |
| Volume path | `/data` |
| Replicas | exactly `1` |

Use a temporary `*.zeabur.app` domain and a fresh empty volume for this verification service. Verify `/healthz` and the production relay smoke test before copying production data or moving `relay.planet-corp.cn`.

Do not configure Zeabur's `runAsUserID` override. The image starts as root only to correct the ownership of a newly attached `/data` volume, then immediately drops to UID/GID `10001` through `gosu` before starting the JVM.

## 3. Existing Git deployment and rollback baseline

For the repository fork in this project, deploy the checked-in Zeabur template:

```bash
zeabur template deploy \
  --file deploy/zeabur/template.yaml \
  --project-id YOUR_PROJECT_ID
```

The template creates the GitHub service, port, health check, and `/data` volume together. Zeabur's `DOMAIN` template variable creates a `*.zeabur.app` domain; bind the custom domain separately after the service exists:

```bash
zeabur domain create \
  --name cc-pocket-relay \
  --env-id YOUR_ENVIRONMENT_ID \
  --domain relay.planet-corp.cn \
  --yes
```

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

## 4. Promote the private image

1. Stop client writes and suspend the verification service.
2. Back up the production service's `/data/relay.db` from the Zeabur volume and verify that the backup is non-empty.
3. Restore the backup as `/data/relay.db` on the private-image service volume.
4. Start the private-image service and verify its temporary domain before moving production traffic.
5. Remove `relay.planet-corp.cn` from the Git service and bind it to the private-image service's HTTP port.
6. Run the health check, production smoke test, and a real Android/daemon reconnect.
7. Keep the stopped Git service and its original volume for 24 hours. Roll back by moving the domain to it if any verification fails; delete it only after the observation window.

Never attach the same SQLite volume to two running relay services. Their WebSocket broker is process-local, and concurrent writers to a copied database would make rollback unsafe.

## 5. Bind and verify the domain

Bind `relay.planet-corp.cn` to the service's HTTP port. The existing `*.planet-corp.cn` DNS record must resolve to the ingress target Zeabur shows for this project. Wait for Zeabur to issue a certificate, then verify:

```bash
curl -fsS https://relay.planet-corp.cn/healthz
```

The expected response is `ok`. The container itself serves plain HTTP/WS; public clients always use `https://` and `wss://`.

## 6. Verify the encrypted relay path

Build the test daemon distribution, then run the repository's isolated production smoke test. It uses a throwaway identity and pair port and cleans up its processes on exit.

```bash
JAVA_HOME=/path/to/jdk-17 ./gradlew :daemon:installDist
JAVA_HOME=/path/to/jdk-17 bash scripts/relay-smoke-prod.sh wss://relay.planet-corp.cn
```

Do not switch the real daemon until the smoke test proves the public health check, daemon attachment, E2E handshake, and encrypted round trip.

## 7. Point the WSL daemon at the relay

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

## 8. Operate and upgrade

- Keep one replica and retain the `/data` volume across deployments.
- Publish upgrades with a new `relay-vX.Y.Z` Git tag, verify the new private image on a temporary service, and update Zeabur only after the smoke test passes.
- Back up the `relay-data` volume before every relay upgrade and periodically while in service.
- After a redeploy, repeat `/healthz`, the production smoke test, and a real Android reconnect.
- Monitor container restarts, WebSocket disconnects, disk use, and SQLite errors.
- This setup intentionally leaves FCM/APNs credentials unset. The existing Android app reconnects when active, but self-hosted background push is out of scope.
