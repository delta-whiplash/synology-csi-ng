# Upstream issue backlog — triage

The official repository carries 63 open issues (2021→2026). Each one is triaged here:
what it is, whether **this chart already fixes it**, whether it needs a driver-level
patch (applied to our builds and pushed upstream), or whether it is tracked.

Legend: ✅ fixed here · 🔧 driver patch (our builds) · 📋 tracked upstream · ❓ needs repro · 📚 docs

## Packaging & publication

| Issue | Summary | Status |
|---|---|---|
| [#149](https://github.com/SynologyOpenSource/synology-csi/issues/149) | Where is the v1.4.0 image? | ✅ we build it (unmodified upstream tag → our GHCR) |
| [#136](https://github.com/SynologyOpenSource/synology-csi/issues/136) | Build fails: missing `synocli` dir | 🔧 handled in our Dockerfile (COPY synocli from context) |
| [#128](https://github.com/SynologyOpenSource/synology-csi/issues/128) | CRI-O short-name mode (registry refs) | ✅ fully-qualified refs by default (+#129) |
| [#112](https://github.com/SynologyOpenSource/synology-csi/issues/112) | Publish chart as OCI artifact | ✅ OCI + HTTPS, both |
| [#40](https://github.com/SynologyOpenSource/synology-csi/pull/40) / [#118](https://github.com/SynologyOpenSource/synology-csi/pull/118) / [#76](https://github.com/SynologyOpenSource/synology-csi/pull/76) | Community chart PRs | ✅ superseded by this chart (patterns merged) |

## Talos & host compatibility

| Issue | Summary | Status |
|---|---|---|
| [#130](https://github.com/SynologyOpenSource/synology-csi/pull/130) | Talos chroot fix (no `/usr/bin/env` on host) | 🔧 candidate for our builds; chart flags already unblock released images |
| [#103](https://github.com/SynologyOpenSource/synology-csi/issues/103) | `Volume[UUID] is not found` | ❓ reproduced & diagnosed here (stale per-node state); repro doc in TESTING.md |
| [#111](https://github.com/SynologyOpenSource/synology-csi/issues/111) | Mount failure after upgrading to 1.2.1 | 🔧 related to #89-era changes; covered by our validated builds |
| [#97](https://github.com/SynologyOpenSource/synology-csi/issues/97) / [#65](https://github.com/SynologyOpenSource/synology-csi/issues/65) | "Couldn't find any host available" | 📋 tracked (node registration diagnostics) |
| [#72](https://github.com/SynologyOpenSource/synology-csi/issues/72) | csi.sock missing / still connecting | 📋 tracked |
| [#67](https://github.com/SynologyOpenSource/synology-csi/issues/67) | Alpine not supported (old image era) | 📋 historical |
| [#11](https://github.com/SynologyOpenSource/synology-csi/issues/11) | microk8s driver registration | 📋 tracked |

## NFS

| Issue | Summary | Status |
|---|---|---|
| [#139](https://github.com/SynologyOpenSource/synology-csi/issues/139) | CreateVolume "succeeds" while NFS privilege save failed (DSM 2370) | ✅ **shipped** — driver retries 2370 at the `ShareNfsPrivilegeSave` level (cap 5 attempts, 2s constant backoff) on top of the per-request retry in `nfsPrivilegeRequest`; patch `patches/v1.4.0/0001-nfs-configurable-root-squash-and-2370-retry.patch` |
| [#91](https://github.com/SynologyOpenSource/synology-csi/issues/91) / [#105-adjacent] | Failed to set NFS privilege rule | ✅ same fix family as #139 (shipped) |
| [#113](https://github.com/SynologyOpenSource/synology-csi/issues/113) | NFS privilege breaks NAT-ed networks | 🔧 PR #142 (configurable allowlist) applies |
| [#131](https://github.com/SynologyOpenSource/synology-csi/issues/131) | NodeGetVolumeStats / expand for static NFS PVs | 📋 tracked |
| [#95](https://github.com/SynologyOpenSource/synology-csi/issues/95) | NFS export world-readable | ✅ **shipped** — `CSI_NFS_ROOT_SQUASH` env (chart value `hostTools.nfsRootSquash`, default `""` = no squash) lets operators override the upstream hardcoded `"root"` per call |
| **32-char truncation** (undocumented upstream) | DSM truncates share names at 32 chars; driver mounts the full name → every NFS PVC fails to publish | 🔧 **our own finding** — patch designed (consistent truncated naming), PR upstream planned |

## Security

| Issue | Summary | Status |
|---|---|---|
| [#47](https://github.com/SynologyOpenSource/synology-csi/issues/47) | Node ClusterRole can read ALL secrets | ✅ réellement corrigé (RBAC node émondé, secrets retirés) — la chart ne laisse au ClusterRole node que nodes [get,list,watch] |
| [#30](https://github.com/SynologyOpenSource/synology-csi/issues/30) | securityContext support | ✅ tous les conteneurs du chart (driver + provisioner/attacher/resizer/snapshotter/registrar) sont durcis : drop ALL caps, readOnlyRootFilesystem, seccomp RuntimeDefault ; non-root (65534) sur controller/snapshotter, root uniquement là où le hostPath l'impose (node-driver-registrar, node plugin) |
| [#35](https://github.com/SynologyOpenSource/synology-csi/issues/35) | Don't require DSM admin account | 📋 tracked (needs DSM privilege scoping docs + validation) |
| [#82](https://github.com/SynologyOpenSource/synology-csi/issues/82) / [#63](https://github.com/SynologyOpenSource/synology-csi/issues/63) | iSCSI targets created with no auth / CHAP support | 📋 tracked (driver feature) |
| [#100](https://github.com/SynologyOpenSource/synology-csi/issues/100) | Security recommendations | 📋 tracked |

## Features

| Issue | Summary | Status |
|---|---|---|
| [#121](https://github.com/SynologyOpenSource/synology-csi/issues/121) / [#92](https://github.com/SynologyOpenSource/synology-csi/issues/92) / [#96](https://github.com/SynologyOpenSource/synology-csi/issues/96) | Share naming / prefix control | 📋 tracked (driver: share name generation) — interacts with the 32-char truncation fix |
| [#78](https://github.com/SynologyOpenSource/synology-csi/issues/78) / [#104](https://github.com/SynologyOpenSource/synology-csi/pull/104) | Minimum capacity configurable / normalization | 🔧 PR #104 applies |
| [#36](https://github.com/SynologyOpenSource/synology-csi/issues/36) | Prometheus metrics | 📋 tracked |
| [#93](https://github.com/SynologyOpenSource/synology-csi/issues/93) | Raw block volumes | 📋 tracked |
| [#99](https://github.com/SynologyOpenSource/synology-csi/issues/99) | RWX behaviour on iSCSI | 📋 tracked (docs + validation) |
| [#48](https://github.com/SynologyOpenSource/synology-csi/pull/48) / [#75](https://github.com/SynologyOpenSource/synology-csi/pull/75) | Extra LUN info / devAttribs | 🔧 applies to our builds |

## Bugs (driver-level)

| Issue | Summary | Status |
|---|---|---|
| [#138](https://github.com/SynologyOpenSource/synology-csi/issues/138) | Stale iSCSI node records after rapid clone+delete | 🔧 reproduced-class (matches our multi-node diagnostics); needs upstream fix |
| [#119](https://github.com/SynologyOpenSource/synology-csi/issues/119) / [#84](https://github.com/SynologyOpenSource/synology-csi/issues/84) | Snapshot failures | 📋 tracked |
| [#52](https://github.com/SynologyOpenSource/synology-csi/issues/52) / [#59](https://github.com/SynologyOpenSource/synology-csi/issues/59) | SMB: already-exists / permission errors | 📋 tracked (SMB untested here) |
| [#134](https://github.com/SynologyOpenSource/synology-csi/issues/134) | Bad description for digits-only namespaces | 🔧 validation fix candidate |
| [#23](https://github.com/SynologyOpenSource/synology-csi/issues/23) / [#73](https://github.com/SynologyOpenSource/synology-csi/issues/73) / [#37](https://github.com/SynologyOpenSource/synology-csi/issues/37) / [#22](https://github.com/SynologyOpenSource/synology-csi/issues/22) / [#33](https://github.com/SynologyOpenSource/synology-csi/issues/33) / [#90](https://github.com/SynologyOpenSource/synology-csi/issues/90) / [#87](https://github.com/SynologyOpenSource/synology-csi/issues/87) / [#98](https://github.com/SynologyOpenSource/synology-csi/issues/98) / [#120](https://github.com/SynologyOpenSource/synology-csi/issues/120) / [#81](https://github.com/SynologyOpenSource/synology-csi/issues/81) | Assorted iSCSI/SMB/arch questions & bugs | 📋 triaged as they are picked up |

## Documentation

| Issue | Summary | Status |
|---|---|---|
| [#94](https://github.com/SynologyOpenSource/synology-csi/issues/94) / [#41](https://github.com/SynologyOpenSource/synology-csi/issues/41) / [#120](https://github.com/SynologyOpenSource/synology-csi/issues/120) | Missing docs / DR / MPIO | 📚 this repo's docs cover the deployment half; driver docs tracked upstream |
| [#64](https://github.com/SynologyOpenSource/synology-csi/issues/64) | Migration to an organization | 📚 upstream governance |

## Fork-specific (zebernst/synology-csi-talos)

| Issue | Summary | Status |
|---|---|---|
| [#28](https://github.com/zebernst/synology-csi-talos/issues/28) | Rebase on upstream v1.3.0+ | ✅ **this project is that rebase** |
| [#27](https://github.com/zebernst/synology-csi-talos/issues/27) | Default tag points to a non-existent image | ✅ fixed here (pinned, verified tags) |
| [#21](https://github.com/zebernst/synology-csi-talos/issues/21) | Is NFS supported? | ⚠️ provisioning yes, mount blocked upstream (see NFS section) |
