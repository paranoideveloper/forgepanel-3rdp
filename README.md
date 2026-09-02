# ForgePanel — 3rdP

A self-hosted, multi-protocol proxy panel that runs as a **single service on a
third-party host** — the panel, the subscriptions and the tunnels themselves share the
one HTTP port the platform gives you, with the platform's edge providing TLS.

Deploy it, open the panel, click once, hand out the links.

**The panel adapts to where it is running.** It detects Railway, Render, Fly and
Koyeb and *removes* the controls those platforms own — certificates, domains,
ports, host tuning — instead of showing switches that cannot work. Each removal
says why, and says how to get the capability back where that is possible: Fly
routes raw TCP and UDP once `FORGEPANEL_PAAS_TCP_PORTS` / `_UDP_PORTS` declare
them, which is what makes REALITY and Hysteria2 available there and nowhere else
in this table.

## Which host

Four platforms, and they are not equivalent. The differences are the platform's, not
the panel's, and two of them cannot run it at all:

| | Panel | Persistent data | Extra ports | Verdict |
|---|---|---|---|---|
| **Fly.io** | ✅ | volumes | **raw TCP + UDP** | best — REALITY and Hysteria2 work here |
| **Railway** | ✅ | volumes | one HTTP port | fine; ws / httpupgrade / xhttp only |
| **Render** | ✅ **paid** | disks, **paid plans only** | one HTTP port | free tier is unusable — see below |
| **Netlify** | ❌ | — | — | no long-lived server process exists |
| **Vercel** | ❌ | — | — | containers are request-driven with no disk |

**Render's free tier is not "slower", it is broken for this.** A free web service cannot
attach a persistent disk, so every deploy and restart throws away the admin account,
every user and all traffic accounting — silently, looking exactly like a fresh install.
It also sleeps after 15 minutes idle, and a VPN client does not wait 30 seconds for a
cold start; it fails. Use the `starter` plan or another host.

**Netlify and Vercel cannot host the panel, and no configuration changes that.** Netlify
runs functions, not servers — 30 s synchronous, 15 min background, no process that
outlives a request. Vercel runs Dockerfiles now, but containers there are request-driven,
scale to zero after five minutes idle, and have no persistent disk. This panel supervises
long-running xray/sing-box processes and owns a database. Neither platform offers the
shape. What they *can* do is sit in front of a panel hosted elsewhere as an edge relay on
a second clean domain — a different job, done by a different piece.

---


## Deploy

Each platform reads its own manifest from the repository root. Nothing else to configure.

### Fly.io — `fly.toml`

```bash
fly launch --no-deploy --copy-config
fly volumes create forgepanel_data --size 1
fly deploy
```

The volume is not optional; see the warning below. For REALITY and Hysteria2, allocate a
dedicated IPv4 (`fly ips allocate-v4`), uncomment the `[[services]]` blocks in `fly.toml`
and set the matching `FORGEPANEL_PAAS_TCP_PORTS` / `FORGEPANEL_PAAS_UDP_PORTS`.

### Railway — `railway.json`

**New Project → Deploy from GitHub repo.** Then **attach a volume** at `/var/lib/forgepanel`
and **Settings → Networking → Generate Domain** — Railway creates neither for you, and
until the domain exists there is no address for the panel or any link.

### Render — `render.yaml`

**New → Blueprint**, pointed at this repository. The blueprint declares the `starter`
plan and a 1 GB disk deliberately; a free service cannot have the disk.

> **If you already made a Web Service and the build failed with `no Go files in …`:**
> Render picked its native **Go** runtime rather than Docker, so it never read
> `render.yaml` and ran `go build` at the repository root — where there are no `.go`
> files, because they all live under `cmd/` and `internal/`.
>
> Fix it in **Settings → Build → Language → Docker** (leave *Dockerfile Path* empty; the
> root `Dockerfile` is the one to use), or delete the service and create it again as
> **New → Blueprint**, which gets you the disk and the right plan as well.
>
> No native runtime can build this, whatever the language setting: the frontend needs
> `bun` and the image bakes in the xray and sing-box binaries. It is a Docker service or
> it is nothing.

### Any other edge

Set `FORGEPANEL_PAAS=1` and `FORGEPANEL_DOMAIN`. Anything that terminates TLS and hands
the container one HTTP port works.

### On every platform

**Attach the volume at exactly `/var/lib/forgepanel`, before you finish setup.** These
platforms give the container a fresh filesystem on every deploy and restart, so without
one each redeploy silently discards the admin account, every inbound, every user and all
traffic history — and comes back looking like a clean first install, which is what makes
it dangerous. The panel's status page reports a missing volume as **critical**, and the
container says so at boot.

Then open the deploy logs for the panel URL and a one-time setup token:

```
Panel:  https://your-app.fly.dev/panel/3f3bc5e93ffb
PaaS:   fly — the edge terminates TLS on your-app.fly.dev:443 …
Setup token:  4ba5fe57…
```

The panel path is randomised per install and the token is single-use and expires, so
there is no default password to forget to change. If you generate the domain *after*
first boot, the panel learns its hostname from your first admin request and repairs any
inbound created before it knew.

---

## One click, every config the platform can carry

**Inbounds → Create all platform configs** generates the full set and labels each with
what can actually dial it — which is the part no client tells you:

| Protocol | ws | httpupgrade | xhttp |
|---|---|---|---|
| VLESS | universal | modern | Xray-only |
| VMess | universal | modern | Xray-only |
| Trojan | universal | modern | Xray-only |
| Shadowsocks | plugin&nbsp;required | subscription&nbsp;only | subscription&nbsp;only |
| Brook | brook&nbsp;client | — | — |

- **universal** — every client in use: v2rayNG, Hiddify, Streisand, NekoBox, sing-box, Xray.
- **modern** — sing-box 1.8+ or current Xray.
- **Xray-only** — sing-box has no XHTTP implementation and cannot dial it at all. Most
  iOS and desktop apps embed sing-box, so treat these as a bonus, not a default.
- **plugin required** — Shadowsocks over WebSocket is carried by SIP003's
  `v2ray-plugin`, with `mux=0` (its default `mux=1` wraps the stream in a protocol a
  plain Shadowsocks inbound does not speak). Works on Android and desktop clients that
  ship the plugin. **iOS cannot** — the platform forbids spawning a subprocess, and a
  SIP003 plugin is one.
- **brook client** — Brook speaks its own protocol, so no v2ray/Xray/sing-box client can
  dial it, but the clients that do exist (the `brook` CLI, Shadowrocket) take a `brook://`
  link directly. Its `wsserver` mode is a WebSocket server with a path, which the shared
  port routes like any other; a plain `brook server` needs its own TCP port and
  `quicserver` needs UDP, so neither is offered here.
- **subscription only** — no `ss://` URI can express these transports, because no SIP003
  plugin implements them. The inbound works; deliver it with the **Xray** or **JSON**
  subscription, which carry a whole client config instead of a link. Asking for a share
  link on one returns an error saying so, rather than a link that quietly means
  "plain TCP".

Addressing is handled for you: any inbound you create gets the platform hostname, port
443, TLS and a random path. Internally the core binds `127.0.0.1` with no TLS — which is
what the edge actually forwards — while the link, the QR and the subscription describe
the connection your client really makes.

## What cannot run here, and what to do about it

On Railway, Render and Koyeb the platform routes **TCP over one HTTP port**. That is the
whole constraint:

| Not available | Why |
|---|---|
| Hysteria2, TUIC, WireGuard, AmneziaWG | need UDP, which the platform does not route |
| REALITY | performs its own TLS handshake; the edge already completed a different one |
| Raw TCP, AnyTLS, ShadowTLS, plain `brook server` | need a TCP port of their own |
| gRPC, HTTP/2 transports | need end-to-end HTTP/2; the edge re-issues over HTTP/1.1 |
| ForgeDNS | needs UDP/53 |

The panel refuses to create these rather than storing something that looks configured
and carries nothing, and the refusal names what *is* possible.

**On Fly, most of that table is a default rather than a limit.** Fly will route raw TCP
and UDP straight to the container, so REALITY, Hysteria2 and TUIC all work — with a
dedicated IPv4 and the ports declared. Neither fact is visible from inside the container,
so you tell the panel:

```toml
# fly.toml
[env]
  FORGEPANEL_PAAS_TCP_PORTS = "8443"   # REALITY, AnyTLS, raw TCP
  FORGEPANEL_PAAS_UDP_PORTS = "443"    # Hysteria2, TUIC, QUIC

[[services]]
  protocol = "tcp"                     # no handlers: pass-through, nothing terminated
  internal_port = 8443
  [[services.ports]]
    port = 8443
```

An inbound on a declared port is served **as entered** — its own port, its own TLS, no
front proxy — because that is the only way REALITY can work anywhere. UDP inbounds bind
`fly-global-services` automatically, which Fly requires and which silently receives
nothing if you bind the wildcard instead.

Only declare a port Fly actually routes. A port listed here that no `[[services]]` block
carries produces an inbound the panel offers and no client can reach, which is harder to
diagnose than the refusal it replaced.

**Or enrol a node.** The panel runs here and drives proxy servers that own their ports —
that is what `cmd/forgenode` is, and the image ships it so enrolment works from a
platform-hosted panel. Control plane here, data plane on a VPS, every protocol available.

---

## Cost

These platforms bill usage, not the plan fee. The panel idles at roughly 40–80 MB RAM and
almost no CPU. **Egress at $0.05/GB is what you actually pay for** — every gigabyte a
client pulls through the tunnel is a gigabyte of Railway egress.

- Railway Hobby ($5/mo, $5 included) covers the panel plus roughly 80–90 GB of traffic.
- Beyond that it is about **$50 per TB** on Railway; Fly and Render are in the same
  order of magnitude.

For a handful of users, or as a spare route that is trivial to redeploy under a fresh
hostname, that is fine. If you are moving hundreds of gigabytes, a VPS is an order of
magnitude cheaper and this is the wrong host for the traffic — run the panel here and
put the traffic on a node.

Railway's Acceptable Use Policy prohibits "operating proxies or anonymization
services", and the other platforms have comparable clauses. Read the one for the host
you pick and decide for yourself whether your use falls under it.

---

## Configuration

Nothing is required — the platform's own variables are detected. All optional:

| Variable | Effect |
|---|---|
| `FORGEPANEL_DOMAIN` | a custom domain attached at the platform edge; overrides the generated hostname in every link |
| `FORGEPANEL_ADMIN_USER` | first administrator's username (default `admin`) |
| `FORGEPANEL_TELEGRAM_TOKEN`, `FORGEPANEL_TELEGRAM_ADMINS` | bot credentials; also settable in the panel |
| `FORGEPANEL_PAAS` | `1` forces platform mode on somewhere it is not detected; `0` forces it off |

`PORT` is supplied by the platform and read on every start.

| `FORGEPANEL_PAAS_TCP_PORTS` | ports the platform routes as raw TCP, comma separated (Fly) |
| `FORGEPANEL_PAAS_UDP_PORTS` | ports the platform routes as UDP, comma separated (Fly) |

**Detection.** The same image recognises **Railway** (`RAILWAY_PUBLIC_DOMAIN`), **Render**
(`RENDER_EXTERNAL_HOSTNAME`), **Fly.io** (`FLY_APP_NAME`) and **Koyeb**
(`KOYEB_PUBLIC_DOMAIN`) from the variables they inject. Never from `PORT` alone — plenty
of ordinary hosts set that, and treating it as the signal would silently drop a normal
install's TLS.

## Documentation

[Panel guide](docs/PANEL_GUIDE.md) ·
[Protocols](docs/PROTOCOLS.md) ·
[API](docs/API.md) ·
[Configuration](docs/CONFIGURATION.md) ·
[Diagnostics](docs/DIAGNOSTICS.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md) ·
[Security](docs/SECURITY.md) ·
[Design decisions](docs/DECISIONS.md)

## Building it yourself

```bash
make check    # go test ./... + frontend tests + vet + gofmt
make image    # exactly what the platform builds
```

Go 1.25 and [bun](https://bun.sh) for the frontend, which is embedded into the binary.

## Scope of this repository

This is the third-party-host distribution: the panel, its frontend, the node agent and
the deploy files for Fly, Railway and Render. Packaging for distributions, the standalone installer, the Cloudflare
Worker edge and the developer tooling live in the upstream repository and are not
carried here.

## License

MIT — see [LICENSE](LICENSE).
