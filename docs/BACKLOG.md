# Upstream issue backlog — triage

The official repository carries 63 open issues (2021→2026). Each one is triaged here:
what it is, whether **this chart already fixes it**, whether it needs a driver-level
patch (applied to our builds and pushed upstream), or whether it is tracked.

Legend: ✅ fixed here · 🔧 driver patch (our builds) · 📋 tracked upstream · ❓ needs repro · 📚 docs · 💬 commented upstream with evidence

## Packaging & publication

| Issue | Summary | Status |
|---|---|---|
| [#149](https://github.com/SynologyOpenSource/synology-csi/issues/149) | Where is the v1.4.0 image? | 💬 **Commented 2026-10-01**: confirmed 404 on Docker Hub (registry API), explained UBI9 RHEL entitlement blocker from the Dockerfile comment, announced our unmodified v1.4.0 builds on GHCR with public CI |
| [#136](https://github.com/SynologyOpenSource/synology-csi/issues/136) | Build fails: missing `synocli` dir | 🔧 handled in our Dockerfile (COPY synocli from context) |
| [#128](https://github.com/SynologyOpenSource/synology-csi/issues/128) | CRI-O short-name mode (registry refs) | ✅ fully-qualified refs by default (+#129) |
| [#112](https://github.com/SynologyOpenSource/synology-csi/issues/112) | Publish chart as OCI artifact | ✅ OCI + HTTPS, both |
| [#40](https://github.com/SynologyOpenSource/synology-csi/pull/40) / [#118](https://github.com/SynologyOpenSource/synology-csi/pull/118) / [#76](https://github.com/SynologyOpenSource/synology-csi/pull/76) | Community chart PRs | ✅ superseded by this chart (patterns merged) |

## Talos & host compatibility

| Issue | Summary | Status |
|---|---|---|
| [#130](https://github.com/SynologyOpenSource/synology-csi/pull/130) | Talos chroot fix (no `/usr/bin/env` on host) | 🔧 **Patched** in `0003` (chart flags `--chroot-dir` + `--iscsiadm-path` already unblock released images) |
| [#104](https://github.com/SynologyOpenSource/synology-csi/pull/104) | Minimum capacity configurable / normalization | 🔧 **Patched** in `0003` |
| [#134](https://github.com/SynologyOpenSource/synology-csi/issues/134) | Bad description for digits-only namespaces | 🔧 **Patched** in `0003` (validation fix, accept digits-only namespace names) |
| [#103](https://github.com/SynologyOpenSource/synology-csi/issues/103) | `Volume[UUID] is not found` | ❓ reproduced & diagnosed here (stale per-node state); repro doc in `docs/TESTING.md`, operational fix in `docs/OPERATIONS.md` |
| [#111](https://github.com/SynologyOpenSource/synology-csi/issues/111) | Mount failure after upgrading to 1.2.1 | 🔧 related to #89-era changes; covered by our validated builds |
| [#97](https://github.com/SynologyOpenSource/synology-csi/issues/97) / [#65](https://github.com/SynologyOpenSource/synology-csi/issues/65) | "Couldn't find any host available" | 📋 tracked (node registration diagnostics) |
| [#72](https://github.com/SynologyOpenSource/synology-csi/issues/72) | csi.sock missing / still connecting | 📋 tracked |
| [#67](https://github.com/SynologyOpenSource/synology-csi/issues/67) | Alpine not supported (old image era) | 📋 historical |
| [#11](https://github.com/SynologyOpenSource/synology-csi/issues/11) | microk8s driver registration | 📋 tracked |

## NFS

| Issue | Summary | Status |
|---|---|---|
| [#139](https://github.com/SynologyOpenSource/synology-csi/issues/139) | CreateVolume "succeeds" while NFS privilege save failed (DSM 2370) | 💬 **Commented 2026-10-01** with reproduction evidence (driver creates share + export rule, save returns 2370, rules not loaded) + 🔧 **Patched** in `0001-nfs-configurable-root-squash-and-2370-retry.patch` (retry on 2370, cap 5 attempts). Analysis cites `pkg/dsm/webapi/share.go:494-530` (upstream retry loop) and `backoff.Permanent(err)` at line 505 which does not cover the first-save-2370 case |
| [#91](https://github.com/SynologyOpenSource/synology-csi/issues/91) / [#105-adjacent] | Failed to set NFS privilege rule | 🔧 same family as #139 — covered by the 2370 retry in `0001` |
| [#113](https://github.com/SynologyOpenSource/synology-csi/issues/113) | NFS privilege breaks NAT-ed networks | 🔧 PR #142 (configurable allowlist) applies |
| [#131](https://github.com/SynologyOpenSource/synology-csi/issues/131) | NodeGetVolumeStats / expand for static NFS PVs | 📋 tracked |
| [#95](https://github.com/SynologyOpenSource/synology-csi/issues/95) | NFS export world-readable | 💬 **Commented 2026-10-01** with evidence: `mountPermissions` parameter exists natively (`pkg/driver/nodeserver.go:845`, default `0750`), configurable per StorageClass (lines 852-857). **No patch needed** — upstream already supports it, documented for operators. `0001` also contributes configurable `RootSquash` via `CSI_NFS_ROOT_SQUASH` env var |
| **32-char truncation** (undocumented upstream) | DSM truncates share names at 32 chars; driver creates the share truncated (GenShareName already truncates correctly since v1.1.0) but the MOUNT path still uses the full name → every NFS PVC fails to publish | 📋 **Upstream bug, mount-side; NOT fixed in our builds** (diagnosis in `docs/CODE-REVIEW-v1.4.0.md`). The naming side is fine — only the mount call needs the same truncation. Workaround: manually rename the share on DSM to the truncated name |

## Security

| Issue | Summary | Status |
|---|---|---|
| [#47](https://github.com/SynologyOpenSource/synology-csi/issues/47) | Node ClusterRole can read ALL secrets | ✅ fixed (node RBAC pruned, secrets removed) — the chart leaves the node ClusterRole with only `nodes [get,list,watch]` |
| [#30](https://github.com/SynologyOpenSource/synology-csi/issues/30) | securityContext support | ✅ every container in the chart (driver + provisioner/attacher/resizer/snapshotter/registrar) is hardened: drop ALL caps, readOnlyRootFilesystem, seccomp RuntimeDefault; non-root (65534) on controller/snapshotter, root only where hostPath requires it (node-driver-registrar, node plugin) |
| [#35](https://github.com/SynologyOpenSource/synology-csi/issues/35) | Don't require DSM admin account | 📋 tracked (needs DSM privilege scoping docs + validation) |
| [#82](https://github.com/SynologyOpenSource/synology-csi/issues/82) / [#63](https://github.com/SynologyOpenSource/synology-csi/issues/63) | iSCSI targets created with no auth / CHAP support | 🔧 **in PR (pending) — patch `0004-chap-and-min-capacity.patch` in review** (CHAP via StorageClass secrets, `auth_type` configurable; not merged into any release yet) |
| [#78](https://github.com/SynologyOpenSource/synology-csi/issues/78) | Make minimum volume capacity configurable | 🔧 **in PR (pending) — patch `0004-chap-and-min-capacity.patch` in review** (exposes the existing 1 GiB clamp of `0003` as a StorageClass-tunable parameter; not merged into any release yet) |
| [#100](https://github.com/SynologyOpenSource/synology-csi/issues/100) | Security recommendations | 🔧 **Patched** in `0002-critical-stability-security.patch` (password in query string → POST form, debug log redaction, HTTP timeouts, panic recovery on hot paths) |

## Features

| Issue | Summary | Status |
|---|---|---|
| [#121](https://github.com/SynologyOpenSource/synology-csi/issues/121) / [#92](https://github.com/SynologyOpenSource/synology-csi/issues/92) / [#96](https://github.com/SynologyOpenSource/synology-csi/issues/96) | Share naming / prefix control | 📋 tracked (driver: share name generation) — interacts with the 32-char truncation fix |
| [#36](https://github.com/SynologyOpenSource/synology-csi/issues/36) | Prometheus metrics | 📋 tracked |
| [#93](https://github.com/SynologyOpenSource/synology-csi/issues/93) | Raw block volumes | 📋 tracked |
| [#99](https://github.com/SynologyOpenSource/synology-csi/issues/99) | RWX behaviour on iSCSI | 📋 tracked (docs + validation) |
| [#48](https://github.com/SynologyOpenSource/synology-csi/pull/48) / [#75](https://github.com/SynologyOpenSource/synology-csi/pull/75) | Extra LUN info / devAttribs | 🔧 applies to our builds |

## Bugs (driver-level)

| Issue | Summary | Status |
|---|---|---|
| [#138](https://github.com/SynologyOpenSource/synology-csi/issues/138) | Stale iSCSI node records after rapid clone+delete | 🔧 **Patched** in `0002-critical-stability-security.patch` (session cleanup, idempotent logout) |
| [#119](https://github.com/SynologyOpenSource/synology-csi/issues/119) / [#84](https://github.com/SynologyOpenSource/synology-csi/issues/84) | Snapshot failures | 📋 tracked |
| [#52](https://github.com/SynologyOpenSource/synology-csi/issues/52) / [#59](https://github.com/SynologyOpenSource/synology-csi/issues/59) | SMB: already-exists / permission errors | 📋 tracked (SMB untested here) |
| [#23](https://github.com/SynologyOpenSource/synology-csi/issues/23) / [#73](https://github.com/SynologyOpenSource/synology-csi/issues/73) / [#37](https://github.com/SynologyOpenSource/synology-csi/issues/37) / [#22](https://github.com/SynologyOpenSource/synology-csi/issues/22) / [#33](https://github.com/SynologyOpenSource/synology-csi/issues/33) / [#90](https://github.com/SynologyOpenSource/synology-csi/issues/90) / [#87](https://github.com/SynologyOpenSource/synology-csi/issues/87) / [#98](https://github.com/SynologyOpenSource/synology-csi/issues/98) / [#120](https://github.com/SynologyOpenSource/synology-csi/issues/120) / [#81](https://github.com/SynologyOpenSource/synology-csi/issues/81) | Assorted iSCSI/SMB/arch questions & bugs | 📋 triaged as they are picked up |

## Documentation

| Issue | Summary | Status |
|---|---|---|
| [#94](https://github.com/SynologyOpenSource/synology-csi/issues/94) / [#41](https://github.com/SynologyOpenSource/synology-csi/issues/41) / [#120](https://github.com/SynologyOpenSource/synology-csi/issues/120) | Missing docs / DR / MPIO | 📚 **Covered**: `docs/DISASTER-RECOVERY.md`, `docs/OPERATIONS.md`, `docs/TESTING.md` |
| [#64](https://github.com/SynologyOpenSource/synology-csi/issues/64) | Migration to an organization | 📚 upstream governance |

## Fork-specific (zebernst/synology-csi-talos)

| Issue | Summary | Status |
|---|---|---|
| [#28](https://github.com/zebernst/synology-csi-talos/issues/28) | Rebase on upstream v1.3.0+ | ✅ **this project is that rebase** |
| [#27](https://github.com/zebernst/synology-csi-talos/issues/27) | Default tag points to a non-existent image | ✅ fixed here (pinned, verified tags) |
| [#21](https://github.com/zebernst/synology-csi-talos/issues/21) | Is NFS supported? | 💬 **Commented 2026-10-01** with reproduction evidence: provisioning OK (share + auto-export), mount blocked ("access denied by server") on driver-created shares whereas manual share (`/volume1/Multimedia`) mounts with same options (`nolock,vers=3`) from same node, NFSv4.1 returns "No such file", error 2370 on rule re-writes. Points to `docs/CODE-REVIEW-v1.4.0.md` (finding **M6** — hardcoded NFS rule parameters at `nodeserver.go:455-467`) and invites comparison of NFS rule parameters (squash/privilege) between driver-created and manual share in DSM. 🔧 `0001` also contributes configurable `RootSquash` via `CSI_NFS_ROOT_SQUASH` env var |

---

## How to upstream

We contribute fixes back to the upstream Synology CSI driver. The process:

### 1 issue = 1 branch = 1 PR

Each upstream issue gets its own branch and PR. Do not bundle multiple fixes into one PR — it makes review harder and blocks independent merges.

**Example workflow**:

```bash
# Start from main (which tracks upstream v1.4.0)
git checkout -b fix/139-nfs-2370-retry main

# Apply the patch (plain diff — use `git apply`, not `git am`; patches are not in mbox format)
git apply patches/v1.4.0/0001-nfs-configurable-root-squash-and-2370-retry.patch

# Commit
git commit -m "fix: retry NFS privilege save on DSM error 2370

The ShareNfsPrivilegeSave function retries when rules do not take effect,
but treats DSM error 2370 (NFS_SHARE_LOAD_FAIL) as permanent. In practice,
2370 is transient — concurrent saves can fail to load but succeed on retry.

Add 2370 to the retriable error list with a cap of 5 attempts.

Fixes: https://github.com/SynologyOpenSource/synology-csi/issues/139
Signed-off-by: Your Name <your.email@example.com>"

# Push and open PR
git push origin fix/139-nfs-2370-retry
gh pr create --repo SynologyOpenSource/synology-csi \
  --title "fix: retry NFS privilege save on DSM error 2370" \
  --body "Fixes #139. See patch in patches/v1.4.0/0001-nfs-configurable-root-squash-and-2370-retry.patch"
```

### Transferrable patches

The patches in `patches/v1.4.0/` are designed to be **transferrable** to upstream:

- They apply cleanly to the upstream v1.4.0 tag (`git apply patches/v1.4.0/*.patch`)
- They do not depend on chart-specific changes
- They include tests (when applicable)
- They follow the upstream code style

To contribute a patch upstream:

1. Open a PR to `SynologyOpenSource/synology-csi` with the patch applied
2. Reference the issue it fixes in the commit message (`Fixes: #NNN`)
3. Link to the patch file in this repo for context: `patches/v1.4.0/NNNN-*.patch`
4. Be ready to iterate on feedback — upstream may request changes to the approach

### What we upstream vs what stays here

**Upstream** (driver-level fixes):
- NFS privilege save retry (#139)
- Configurable root squash (#95, #21)
- 32-char share name truncation
- iSCSI session cleanup (#138)
- CHAP support (#82, #63)
- Configurable minimum volume capacity (#78)
- Panic fixes (C4 from `docs/CODE-REVIEW-v1.4.0.md`)
- Data race fixes (C1)
- Password leak fixes (C2)
- Talos chroot fix (#130)
- Min capacity normalization (#104)
- Digits-only namespace validation (#134)

**Stays here** (chart-level or platform-specific):
- Helm chart hardening (securityContext, RBAC, sidecar versions)
- Platform profiles (Talos, OpenShift, k3s)
- Unmodified image builds (we build what upstream does not publish)

### Tracking

When an upstream PR is merged, update this backlog:
- Change status from 🔧 to ✅ (if it is now in a release)
- Or 📋 tracked (if it is open but not yet merged)
- Add a note: "Upstream PR #NNN merged on YYYY-MM-DD"

When we drop a patch (because upstream fixed it differently), remove it from `patches/v1.4.0/` and note the upstream commit hash.
