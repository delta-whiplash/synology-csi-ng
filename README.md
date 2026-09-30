# synology-csi-talos-ng

**The official [Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi), made to actually work — on Talos Linux, K3s, OpenShift and plain kubeadm clusters — via a hardened Helm chart.**

No forked images. No patched binaries. This project ships a Helm chart that deploys the **official `synology/synology-csi` images** with the deployment configuration they need to run outside "standard" distributions — and hardens everything we can harden.

> **TL;DR for Talos users** : the driver binary already has everything it needs (`--chroot-dir`, `--iscsiadm-path` flags, since v1.2.1). What's missing is a chart that passes them. Install ours:

```sh
helm install synology-csi oci://ghcr.io/delta-whiplash/charts/synology-csi-talos-ng \
  --namespace synology-csi --create-namespace \
  --set hostTools.iscsiadmPath=/usr/local/sbin/iscsiadm \
  --set clientInfoSecret.create=false
```

## Why this exists

On Talos Linux, every published way to run `synology-csi` v1.2.0+ fails at iSCSI mount time:

```
Failed to login with target iqn [...], err: env: can't execute 'iscsiadm': No such file or directory
```

We reproduced this three times on 2026-09-30 (official v1.3.1, a community fork, and upstream main), and traced it to a single line of deployment config rather than a driver bug:

1. The driver runs host binaries through a **chroot** (`pkg/utils/hostexec/hostexec.go`), controlled by a `--chroot-dir` flag that **defaults to empty** ("empty disables chroot").
2. With chroot disabled, `iscsiadm` is looked up **inside the container** — and the official image does not ship it (it's meant to come from the host).
3. The driver resolves commands through `chroot /host /usr/bin/env -i PATH=… <tool>` — and **Talos ships no `/usr/bin/env`** (verified: `lstat /usr/bin/env: no such file or directory`). So even charts that set `--chroot-dir=/host` (including the official `deploy/helm` chart in upstream main today) still fail on Talos: the `env` half of the resolution cannot run.
4. The fix that works everywhere: map the host tool explicitly with `--iscsiadm-path` — the driver skips the `env` wrapper entirely for mapped paths (they contain `/`), so host `env` is never needed.

With `--chroot-dir=/host` (+ the `/host` hostPath mount every chart already ships) and `--iscsiadm-path=/usr/local/sbin/iscsiadm` on Talos, the **unmodified official image works perfectly** — validated end to end: LUN provisioning, mounting, and cross-node pod rescheduling.

Full debugging story and evidence: see [`docs/TESTING.md`](docs/TESTING.md).

## Community PRs we track

The upstream queue is full of good ideas that have been waiting for years. This project integrates what is integrable at the chart level and tracks the driver-level ones:

| Upstream PR | Idea | Status here |
|---|---|---|
| [#130](https://github.com/SynologyOpenSource/synology-csi/pull/130) | Talos chroot fix (resolve tools when host has no `/usr/bin/env`) | validated diagnosis independently; supported upstream — our `--iscsiadm-path` mapping achieves the same on released images today |
| [#129](https://github.com/SynologyOpenSource/synology-csi/pull/129) | Fully-qualified image refs (CRI-O / OpenShift short-name mode) | ✅ **adopted** (default image is `docker.io/synology/synology-csi`) |
| [#118](https://github.com/SynologyOpenSource/synology-csi/pull/118) / upstream main | Helm chart incl. opt-in inline `client-info` Secret | ✅ **adopted** (`clientInfoSecret.create=true` + `clients[]`, with `tlsCACert` / `insecureSkipVerify` passthrough); BYO-secret remains the default for GitOps |
| [#40](https://github.com/SynologyOpenSource/synology-csi/pull/40) | Community Helm chart | patterns merged (per-component RBAC, snapshot classes) |
| [#148](https://github.com/SynologyOpenSource/synology-csi/pull/148) | Retry DSM login instead of serving with no DSM registered | tracked — resilience fix (boot ordering) |
| [#147](https://github.com/SynologyOpenSource/synology-csi/pull/147) / [#116](https://github.com/SynologyOpenSource/synology-csi/pull/116) | Go toolchain + dependency CVE bumps | tracked — supports any future image rebuild |
| [#142](https://github.com/SynologyOpenSource/synology-csi/pull/142) | `nfsClientAllowlist` StorageClass parameter | tracked — documented in chart values once released in an image |
| [#140](https://github.com/SynologyOpenSource/synology-csi/pull/140) | NFS 2370 retry + provisioning race mutex | tracked |
| [#132](https://github.com/SynologyOpenSource/synology-csi/pull/132) | iSCSI target interface binding | tracked |
| [#127](https://github.com/SynologyOpenSource/synology-csi/pull/127) | `allowMultipleSessions` StorageClass parameter | tracked |
| [#104](https://github.com/SynologyOpenSource/synology-csi/pull/104) | Normalize requested capacity to Synology minimum | tracked |
| [#96](https://github.com/SynologyOpenSource/synology-csi/pull/96) / [#75](https://github.com/SynologyOpenSource/synology-csi/pull/75) / [#48](https://github.com/SynologyOpenSource/synology-csi/pull/48) | PVC-named shares, devAttribs, extra LUN info | tracked |

Driver-level features ship when their PR merges upstream and an image is published — this chart deliberately does not fork images.

## What this chart brings

- **Official images only** — `synology/synology-csi` plus upstream `registry.k8s.io/sig-storage` sidecars, pin-able by tag or digest.
- **Deployment profiles** — `--chroot-dir` / `--iscsiadm-path` / `--multipath-path` wired to values, with sane defaults for Talos and generic distros.
- **Hardening by default** — non-root controller & snapshotter, dropped capabilities where the design allows, seccomp `RuntimeDefault`, read-only root filesystems where possible, documented exceptions for the privileged node plugin (CSI node plugins manage devices/mounts by design).
- **Modern sidecars** — current `sig-storage` sidecar versions instead of the 2023-era ones pinned by older charts.
- **Dual chart distribution** — OCI (`ghcr.io/delta-whiplash/charts`) and classic HTTPS repo (`gh-pages` branch).
- **CI** — `helm lint` + kubeconform on every PR, signed chart releases, Dependabot for base images and actions.

## Compatibility

| Driver version | Images published | Status |
|---|---|---|
| v1.1.3 | ✅ | works, legacy (pre `--chroot-dir` flag era: chart uses PATH-shim profile) |
| v1.2.0 / v1.2.1 | ✅ | ✅ chart profile |
| v1.3.0 / v1.3.1 | ✅ | ✅ chart profile — **recommended** |
| v1.4.0 | ❌ not published to a registry yet | chart profile ready, image pending |

| Platform | Status |
|---|---|
| Talos Linux | ✅ validated (see `docs/TESTING.md`) — set `hostTools.iscsiadmPath=/usr/local/sbin/iscsiadm` |
| k3s / kubeadm (Debian, Ubuntu…) | ✅ profile (`iscsiadm` in the default search path) — requires `open-iscsi` installed on hosts |
| OpenShift | ✅ chart profile (SCC: privileged for the node plugin, as with any CSI driver) |

DSM-side requirements are unchanged from upstream: DSM 7.x, a user account with the Synology CSI permissions, and (for NFS/SMB) Btrfs volumes.

## Install

See `charts/synology-csi-talos-ng/values.yaml` for the full reference. Minimal Talos example:

```yaml
# values-talos.yaml
clientInfoSecret:
  create: false          # bring your own (Secret or SealedSecret), key: client-info.yml
  name: synology-csi-credentials

hostTools:
  chrootDir: /host
  iscsiadmPath: /usr/local/sbin/iscsiadm

storageClasses:
  iscsi-delete:
    reclaimPolicy: Delete
    parameters: {fsType: xfs, location: /volume2}
  iscsi-retain:
    reclaimPolicy: Retain
    parameters: {fsType: xfs, location: /volume2}
```

## Credits

- [SynologyOpenSource/synology-csi](https://github.com/SynologyOpenSource/synology-csi) — the driver (Apache-2.0). This project modifies none of its code.
- [zebernst/synology-csi-talos](https://github.com/zebernst/synology-csi-talos) — the pioneering Talos fork, whose chart this project initially used and whose `/csibin` debugging paved the way.
- The `#89` fix by the upstream team, which this chart completes on the deployment side.

## License

Apache-2.0 (same as upstream). See [LICENSE](LICENSE) and [NOTICE](NOTICE).
