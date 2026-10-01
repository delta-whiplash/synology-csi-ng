# synology-csi-talos-ng

[![Lint](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/lint.yml/badge.svg)](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/lint.yml)
[![Release chart](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/release-chart.yml/badge.svg)](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/release-chart.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-SynologyOpenSource%2Fsynology--csi-232c95)](https://github.com/SynologyOpenSource/synology-csi)

**The maintained, production-grade distribution of the [official Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi) — for Talos Linux, k3s, OpenShift, kubeadm and anywhere the upstream deployment story falls short.**

> **Our deal with upstream: *help without depending*.** Everything we fix is packaged so it can be pushed upstream, and everything we ship works even if upstream never merges it. You should not have to choose between a maintained project and a driver that works on your platform — you get both here.

---

## Why this exists

The official driver is good software with a broken delivery pipeline. The evidence, as of October 2026:

| Symptom | Reality |
|---|---|
| **63 open issues** (2021→2026) | Ranging from one-line docs gaps to multi-year broken features |
| **v1.4.0 released with no image** | The source tag exists; their own Dockerfile (UBI9) requires a RHEL entitlement and was never built/published — `docker pull synology/synology-csi:v1.4.0` returns 404 |
| **Talos Linux broken since v1.2.1** | The driver chroots into the host to run `iscsiadm`; Talos keeps it in `/usr/local/sbin`, outside the paths the driver resolves — every stock deployment fails at mount time with `env: can't execute 'iscsiadm'` |
| **NFS provisioning silently broken** | DSM truncates share names at 32 chars while the driver generates 48-char names and mounts the untruncated path — every NFS PVC fails at publish time |
| **Sidecars from 2023** | Older charts pin `csi-provisioner:v3.0.0`-era sidecars that upstream SIG-Storage no longer supports |

None of this is exotic. Every one of these was reproduced, traced to a specific file and line, and fixed or worked around here — with the evidence published.

## What we ship

```
┌─────────────────────────────────────────────────────────────────────┐
│  YOUR CLUSTER                                                       │
│                                                                     │
│  ┌──────────────┐  flags + hardening   ┌──────────────────────────┐ │
│  │ THIS CHART   │ ───────────────────► │ OFFICIAL DRIVER IMAGES   │ │
│  │ (helm, OCI)  │   --chroot-dir       │ synology/synology-csi    │ │
│  └──────────────┘   --iscsiadm-path   │ or our unmodified builds │ │
│         │                             └──────────────────────────┘ │
│         │  SCs, VolumeSnapshotClasses, RBAC, secrets, profiles     │
└─────────┼───────────────────────────────────────────────────────────┘
          ▼
   YOUR SYNOLOGY / XPEROLOGY NAS (DSM API + iSCSI + NFS)
```

1. **A hardened Helm chart** that passes the flags upstream charts forget (`--chroot-dir`, `--iscsiadm-path`), ships current CSI sidecars, non-root controller/snapshotter, least-privilege RBAC, and platform profiles.
2. **Unmodified image builds** of driver releases Synology published without images — built by CI from the exact upstream tag, published to our GHCR, provenance-tracked.
3. **A curated fix backlog**: upstream's 63 open issues triaged, the chart-level ones fixed here, the driver-level ones applied as reviewed patches to our builds and pushed upstream as PRs.

## Compatibility

### Driver versions

| Upstream | Images | This chart |
|---|---|---|
| v1.1.3 | official ✅ | legacy profile (PATH-shim era) |
| v1.2.0 – v1.2.1 | official ✅ | ✅ |
| v1.3.0 / v1.3.1 | official ✅ | ✅ recommended |
| v1.4.0 | ❌ upstream never published | ✅ **default** — built unmodified from the upstream tag ([our GHCR](https://github.com/delta-whiplash/synology-csi-talos-ng/pkgs/container/synology-csi)) |

### Platforms

| Platform | Status | Notes |
|---|---|---|
| **Talos Linux** | ✅ validated | `hostTools.iscsiadmPath=/usr/local/sbin/iscsiadm` — the reason this chart exists |
| k3s / kubeadm (Debian, Ubuntu…) | ✅ profile | hosts need `open-iscsi` |
| OpenShift | ✅ profile | fully-qualified image refs (CRI-O short-name mode), node plugin SCC privileged — as with every CSI driver |

### Feature support (driver v1.4.0 + this chart)

| Feature | iSCSI | NFS | SMB |
|---|---|---|---|
| Provision / delete | ✅ | ✅ provisioning ✅ | ⚠️ untested here |
| Mount / cross-node move | ✅ validated | ⚠️ blocked by upstream bugs (see below) | ⚠️ untested here |
| Snapshots | ✅ (LUN) | ⚠️ driver-side gaps | — |
| Resize | ✅ | ✅ | ✅ |

## The Talos story (why we can prove it works)

On Talos, stock deployments fail at mount: the driver chroots into the host and resolves `iscsiadm` through `env`, which Talos does not ship, and whose real location (`/usr/local/sbin/iscsiadm`) the resolution never sees. We reproduced the failure on three distinct images (official v1.3.1, a community fork, upstream main), traced it to `pkg/utils/hostexec/hostexec.go` + a missing flag, and validated the fix live: **LUN provisioning, mounting, and cross-node pod rescheduling all pass** with the official image + two chart flags. Full protocol and evidence: [`docs/TESTING.md`](docs/TESTING.md).

## Quickstart (Talos)

```yaml
# values-talos.yaml
fullnameOverride: synology-csi

driver:
  image: ghcr.io/delta-whiplash/synology-csi
  tag: v1.4.0            # our unmodified build of the upstream v1.4.0 tag

clientInfoSecret:
  create: false          # bring your own Secret/SealedSecret (key: client-info.yml)
  name: synology-csi-credentials

hostTools:
  chrootDir: /host
  iscsiadmPath: /usr/local/sbin/iscsiadm

storageClasses:
  synology-iscsi:
    reclaimPolicy: Delete
    parameters: {fsType: xfs, location: /volume2}
```

```sh
helm install synology-csi oci://ghcr.io/delta-whiplash/charts/synology-csi-talos-ng \
  --version 0.2.3 -n synology-csi --create-namespace -f values-talos.yaml
```

Classic HTTPS repo also available: `helm repo add synology-csi-talos-ng https://delta-whiplash.github.io/synology-csi-talos-ng`.

## The upstream issue backlog we are working through

Upstream's open issues are triaged in [docs/BACKLOG.md](docs/BACKLOG.md): what each one is, whether this chart already fixes it, whether it needs a driver patch (ours or upstream's), and the link. One issue = one branch = one PR, here and upstream. Highlights:

- ✅ fixed here: image publication (#149), CRI-O refs (#128/#129), OCI chart (#112), chart login failures (#105), RBAC secrets overreach (#47), securityContext (#30)
- 🔧 driver patches applied to our builds: Talos chroot (#130/#89), NFS 2370 retry (#140/#139), NFS allowlist for NAT-ed networks (#113/#142)
- 📋 tracked upstream: share naming (#121/#92/#96), CHAP (#63/#82), metrics (#36), capacity policy (#104/#78)

## Documentation

- [docs/TESTING.md](docs/TESTING.md) — the functional validation protocol (the one used to certify every release here)
- [docs/BACKLOG.md](docs/BACKLOG.md) — the full upstream issue triage
- [SECURITY.md](SECURITY.md) — security posture and reporting
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to contribute

## Credits

- [SynologyOpenSource/synology-csi](https://github.com/SynologyOpenSource/synology-csi) — the driver (Apache-2.0). We modify no driver code unless a fix demands it, and push those fixes upstream.
- [zebernst/synology-csi-talos](https://github.com/zebernst/synology-csi-talos) — the pioneering Talos fork that proved it could work and carried the community for years.

## License

Apache-2.0, same as upstream. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
