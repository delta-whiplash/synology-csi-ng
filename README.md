# synology-csi-ng

[![Lint](https://github.com/delta-whiplash/synology-csi-ng/actions/workflows/lint.yml/badge.svg)](https://github.com/delta-whiplash/synology-csi-ng/actions/workflows/lint.yml)
[![Release chart](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/release-chart.yml/badge.svg)](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/release-chart.yml)
[![Driver build](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/build-driver.yml/badge.svg)](https://github.com/delta-whiplash/synology-csi-talos-ng/actions/workflows/build-driver.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-SynologyOpenSource%2Fsynology--csi-232c95)](https://github.com/SynologyOpenSource/synology-csi)
[![PRs upstream](https://img.shields.io/badge/PR%20upstream-%23151-blue)](https://github.com/SynologyOpenSource/synology-csi/pull/151)

**The maintained, production-grade distribution of the [official Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi), for Talos Linux, k3s, OpenShift, kubeadm and anywhere the upstream deployment story falls short.** Running in production on a 3-node Talos cluster against DSM/Xpenology.

> **Our deal with upstream: *help without depending*.** Everything we fix is packaged so it can be pushed upstream, and everything we ship works even if upstream never merges it. You should not have to choose between a maintained project and a driver that works on your platform, you get both here.

---

## Why this exists

The official driver is good software with a broken delivery pipeline. The evidence, as of October 2026:

| Symptom | Reality |
|---|---|
| **63 open issues** (2021→2026) | Ranging from one-line docs gaps to multi-year broken features |
| **v1.4.0 released with no image** | The source tag exists; their own Dockerfile (UBI9) requires a RHEL entitlement and was never built/published, `docker pull synology/synology-csi:v1.4.0` returns 404. [We build it](https://github.com/delta-whiplash/synology-csi-talos-ng/pkgs/container/synology-csi) from the unmodified tag. |
| **Talos Linux broken since v1.2.1** | The driver chroots into the host to run `iscsiadm`; Talos keeps it in `/usr/local/sbin`, outside the paths the driver resolves, every stock deployment fails at mount time with `env: can't execute 'iscsiadm'` |
| **NFS provisioning partially broken** | DSM truncates share names at 32 chars (handled by `GenShareName` since v1.1.0); the remaining mount failures trace to DSM export-table handling of driver-created shares (documented, under investigation upstream) |
| **Sidecars from 2023** | Older charts pin `csi-provisioner:v3.0.0`-era sidecars that upstream SIG-Storage no longer supports |
| **[PR #151](https://github.com/SynologyOpenSource/synology-csi/pull/151) opened** | Our Talos + Xpenology fixes proposed back to upstream, *help without depending* |

None of this is exotic. Every one of these was reproduced, traced to a specific file and line, and fixed or worked around here, with the evidence published.

## What we ship

```
┌─────────────────────────────────────────────────────────────────────┐
│  YOUR CLUSTER                                                       │
│                                                                     │
│  ┌──────────────┐  flags + hardening   ┌──────────────────────────┐ │
│  │ THIS CHART   │ ───────────────────► │ OFFICIAL DRIVER IMAGES   │ │
│  │ (helm, OCI)  │   --chroot-dir       │ synology/synology-csi    │ │
│  └──────────────┘   --iscsiadm-path   │ or our patched builds    │ │
│         │                             └──────────────────────────┘ │
│         │  SCs, VolumeSnapshotClasses, RBAC, secrets, profiles     │
└─────────┼───────────────────────────────────────────────────────────┘
          ▼
   YOUR SYNOLOGY / XPEROLOGY NAS (DSM API + iSCSI + NFS)
```

1. **A hardened Helm chart** that passes the flags upstream charts forget (`--chroot-dir`, `--iscsiadm-path`), ships current CSI sidecars, least-privilege RBAC, and platform profiles. **Every container in the chart (driver + all sidecars) runs with a locked-down securityContext**, no privilege escalation, all caps dropped, readOnlyRootFilesystem, seccomp RuntimeDefault, non-root where the CSI contract allows it.
2. **Driver builds you can trust**, official images when Synology publishes them, and unmodified-tag builds (e.g. v1.4.0) or reviewed-patch builds (`v1.4.0-ng.x`) from our CI when they don't. Every build passes the smoke tests and the driver's own `-race` test suite before push.
3. **A curated fix backlog**: upstream's 63 open issues triaged in [docs/BACKLOG.md](docs/BACKLOG.md), the chart-level ones fixed here, the driver-level ones applied as reviewed patches and proposed upstream ([PR #151](https://github.com/SynologyOpenSource/synology-csi/pull/151)).
4. **Production-hardened docs**: [TESTING.md](docs/TESTING.md) (the live validation protocol), [OPERATIONS.md](docs/OPERATIONS.md) (runbook: upgrades, stale iSCSI session purge, tested, NFS diagnostics), [DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md), [CODE-REVIEW-v1.4.0.md](docs/CODE-REVIEW-v1.4.0.md) (security/perf/stability sweep, every finding with `file:line`).

## Shipped fixes (patch series over v1.4.0)

All patches are reviewed (independent GLM review + mutation testing), TDD'd, and ship inside `v1.4.0-ng.x` driver builds + apply cleanly on vanilla v1.4.0.

| Patch | Fixes | What it does |
|---|---|---|
| `0001` | NFS | `root_squash` configurable via `CSI_NFS_ROOT_SQUASH` env (default `root` = upstream; empty = no squash, required on Xpenology), 2370 (`NFS_SHARE_LOAD_FAIL`) save retry |
| `0002` | security/stability | Data races on DSM sessions fixed (mutex + serialized re-login), DSM password moved out of GET query strings and redacted from debug logs, HTTP timeouts, parsing panics guarded (multipath lsblk, IQN split) |
| `0003` | Issues | Talos chroot fallback (#130 family), capacity clamp to DSM minimum (#104), digits-only namespace sanitization (#134), `mountPermissions` NFS documented (#95) |
| `0004` | Features | `minVolumeSize` StorageClass parameter (CreateVolume-only floor), overflow-guarded parsing, CHAP **groundwork** (`TargetSetAuth` webapi), full CHAP deferred until `ControllerPublish/UnpublishVolume` wiring exists |

## Compatibility

### Driver versions

| Upstream | Images | This chart |
|---|---|---|
| v1.1.3 | official ✅ | legacy profile (PATH-shim era) |
| v1.2.0 – v1.2.1 | official ✅ | ✅ |
| v1.3.0 / v1.3.1 | official ✅ | ✅ |
| v1.4.0 | ❌ upstream never published | ✅ **default**, [our GHCR](https://github.com/delta-whiplash/synology-csi-talos-ng/pkgs/container/synology-csi) |
| v1.4.0-**ng.2/ng.3** (reviewed patch builds) | ✅ our GHCR | ✅ **running in production here** |

### Platforms

| Platform | Status | Notes |
|---|---|---|
| **Talos Linux** | ✅ validated | `hostTools.iscsiadmPath=/usr/local/sbin/iscsiadm`, the reason this chart exists |
| k3s / kubeadm (Debian, Ubuntu…) | ✅ profile | hosts need `open-iscsi` |
| OpenShift | ✅ profile | fully-qualified image refs (CRI-O short-name mode), node plugin SCC privileged, as with every CSI driver |

### Feature support (driver v1.4.0 + this chart)

| Feature | iSCSI | NFS | SMB |
|---|---|---|---|
| Provision / delete | ✅ | ✅ provisioning ✅ | ⚠️ untested here |
| Mount / cross-node move | ✅ validated | ⚠️ blocked by upstream bugs (see below) | ⚠️ untested here |
| Snapshots | ✅ (LUN) | ⚠️ driver-side gaps |, |
| Resize | ✅ | ✅ | ✅ |
| Configurable `minVolumeSize` floor | ✅ (patch 0004, CreateVolume only; expansion paths use no floor) |, |, |
| `mountPermissions` (NFS/SMB) | n/a (block) | ✅ documented | ✅ |
| iSCSI CHAP auth | ⏳ **deferred**, groundwork in 0004 (`TargetSetAuth` webapi); full feature requires `ControllerPublish/UnpublishVolume` wiring (tracked, not shipped) |, |, |

<details><summary>Example, StorageClass with custom minVolumeSize</summary>

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: synology-iscsi
provisioner: csi.san.synology.com
parameters:
  protocol: iscsi
  dsm: "10.0.0.1"
  location: "/volume1"
  minVolumeSize: "500Mi"   # optional; default 1GiB. Accepts Ki/Mi/Gi/Ti suffixes or plain bytes.
reclaimPolicy: Delete
```

</details>

<details><summary>Example, NFS StorageClass with explicit mount permissions</summary>

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: synology-nfs
provisioner: csi.san.synology.com
parameters:
  protocol: nfs
  dsm: "10.0.0.1"
  location: "/volume1"
  mountPermissions: "0755"   # octal, applied to the pod's target path
reclaimPolicy: Delete
mountOptions: ["nolock"]
```

</details>

## The Talos story (why we can prove it works)

On Talos, stock deployments fail at mount: the driver chroots into the host and resolves `iscsiadm` through `env`, which Talos does not ship, and whose real location (`/usr/local/sbin/iscsiadm`) the resolution never sees. We reproduced the failure on three distinct images (official v1.3.1, a community fork, upstream main), traced it to `pkg/utils/hostexec/hostexec.go` + a missing flag, and validated the fix live: **LUN provisioning, mounting, and cross-node pod rescheduling all pass** with the official image + two chart flags. Full protocol and evidence: [`docs/TESTING.md`](docs/TESTING.md).

## Quickstart (Talos)

```yaml
# values-talos.yaml
fullnameOverride: synology-csi

driver:
  image: ghcr.io/delta-whiplash/synology-csi
  tag: v1.4.0-ng.3       # our reviewed patch build (v1.4.0 + 0001-0003)

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
helm install synology-csi oci://ghcr.io/delta-whiplash/charts/synology-csi-ng \
  --version 0.6.1 -n synology-csi --create-namespace -f values-talos.yaml
```

Classic HTTPS repo also available: `helm repo add synology-csi-ng https://delta-whiplash.github.io/synology-csi-ng`.

## The upstream issue backlog we are working through

Upstream's open issues are triaged in [docs/BACKLOG.md](docs/BACKLOG.md): what each one is, whether this chart already fixes it, whether it needs a driver patch (ours or upstream's), and the link. One issue = one branch = one PR, here and upstream. Highlights:

- ✅ fixed here: image publication (#149), CRI-O refs (#128/#129), OCI chart (#112), chart login failures (#105), RBAC secrets overreach (#47, for real: the node role was trimmed to `nodes [get,list,watch]`), securityContext (#30, every container)
- 🔧 driver patches applied to our builds: Talos chroot fallback (#130 family), NFS 2370 retry (#140/#139), capacity clamp (#104), namespace sanitization (#134), configurable NFS `root_squash`
- 🔍 **a full code audit of driver v1.4.0** lives in [docs/CODE-REVIEW-v1.4.0.md](docs/CODE-REVIEW-v1.4.0.md): 4 critical (data races on DSM sessions, DSM passwords in GET query strings + debug logs, no HTTP timeouts, unrecovered panics on multipath/iSCSI parsing), 11 major (dead NVMe session detection, iSCSI targets created without auth, #82/#63 confirmed at code level, SMB passwords unescaped, #59, N+1 API storms on the kubelet stats path), 9 minor, each with file:line and a suggested fix. These findings are the roadmap for our patched builds and the material for upstream PRs.
- 📋 tracked upstream: share naming (#121/#92/#96), CHAP full wiring, metrics (#36), and the rest of the triage in the backlog

## Troubleshooting, every known error, mapped

These are the exact failure strings people hit with Synology CSI deployments.
If you arrived here by searching one of them: yes, this chart fixes it.

| Error you are seeing | Cause | Fix |
|---|---|---|
| `env: can't execute 'iscsiadm': No such file or directory` | Driver chroots into the host but resolves `iscsiadm` through `env`, absent on **Talos** and anywhere it lives outside the default PATH | This chart: `--chroot-dir` + `--iscsiadm-path` flags (see Quickstart) |
| `Volume[UUID] is not found` at mount after a node change | Stale per-node CSI state or lost DSM export entry | Restart the node plugin DaemonSet on that node; see [docs/TESTING.md](docs/TESTING.md) |
| `rpc.statd is not running but is required for remote locking` | NFS v3 mount without local locking (no statd on Talos/minimal hosts) | Add `mountOptions: [nolock]` to the StorageClass |
| `Missing secrets for node staging volume` | NFS/SMB StorageClass without the DSM credentials reference | Add `csi.storage.k8s.io/node-stage-secret-name` / `-namespace` parameters |
| DSM error `2370` when saving NFS rules | Concurrent NFS privilege saves on DSM | Driver retry fix, applied in our driver builds |
| `Already existing volume name with different capacity` | DSM truncates share names at 32 chars → name collisions between PVCs | Driver fix (hash-suffixed names), in progress, [code review](docs/CODE-REVIEW-v1.4.0.md) finding m1 |
| `access denied by server` on NFS mounts of driver-created shares | DSM export/squash handling of driver-created rules | Under investigation, see the NFS section of [docs/CODE-REVIEW-v1.4.0.md](docs/CODE-REVIEW-v1.4.0.md) |
| `Failed to inspect image` / short-name mode errors (CRI-O) | Unqualified image references | ✅ fixed, fully-qualified refs by default |

## Community

**Issues and pull requests are welcome, with pleasure.** Whether you run Talos, k3s, OpenShift, kubeadm or something stranger: if you hit a bug, need a platform profile, or want a driver fix, open an issue. PRs are reviewed fast and honestly (strict review pass + real-cluster validation), and driver-level fixes ship as reviewed patches in our builds while they wait for upstream.

- 🐛 [Open an issue](https://github.com/delta-whiplash/synology-csi-ng/issues/new) — include your platform, DSM version, and the exact error string (see the Troubleshooting table)
- 🔧 [Open a PR](CONTRIBUTING.md) — one fix per branch, tests over patches, CI gates everything
- 💬 [Discussions](https://github.com/delta-whiplash/synology-csi-talos-ng/discussions) — for platform profiles, NFS/iSCSI war stories, and everything in between

Every report helps: the 63-issue upstream backlog gets shorter because people like you file what breaks.

## Documentation

- [docs/TESTING.md](docs/TESTING.md), the functional validation protocol (the one used to certify every release here)
- [docs/DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md), backup and restore of Synology CSI PVCs (iSCSI LUN snapshots via VolumeSnapshot + Velero, NFS/SMB rsync, recovery order, known pitfalls)
- [docs/OPERATIONS.md](docs/OPERATIONS.md), operational runbook: driver upgrade (order + gates), node plugin restart (symptom "Volume not found"), stale iSCSI session purge (tested `iscsiadm -m node --logout` procedure via privileged pod), NFS diagnostics (`nolock`, `vers`, squash), controller sizing
- [docs/CODE-REVIEW-v1.4.0.md](docs/CODE-REVIEW-v1.4.0.md), security/perf/stability sweep on upstream v1.4.0 (every finding cites `file:line`)
- [docs/BACKLOG.md](docs/BACKLOG.md), the full upstream issue triage, including how to contribute patches upstream (1 issue = 1 branch = 1 PR, transferrable patches)
- [SECURITY.md](SECURITY.md), security posture and reporting
- [CONTRIBUTING.md](CONTRIBUTING.md), how to contribute

## A note on AI

This project is built **with AI in the loop, openly**: brainstorming, pairing on
implementation, deep code auditing, and viability testing. Every change is
gated by a strict review pass and validated on a real 3-node cluster before it
ships. Humans set the direction, AI does the heavy lifting, CI keeps everyone
honest.

## Credits

- [SynologyOpenSource/synology-csi](https://github.com/SynologyOpenSource/synology-csi), the driver (Apache-2.0). We modify no driver code unless a fix demands it, and push those fixes upstream ([PR #151](https://github.com/SynologyOpenSource/synology-csi/pull/151)).
- [zebernst/synology-csi-talos](https://github.com/zebernst/synology-csi-talos), the pioneering Talos fork that proved it could work and carried the community for years.

## License

Apache-2.0, same as upstream. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
