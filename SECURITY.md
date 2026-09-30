# Security Policy

## Reporting a vulnerability

Open a [GitHub security advisory](https://github.com/delta-whiplash/synology-csi-talos-ng/security/advisories/new) rather than a public issue.

This repository ships a **Helm chart** and deployment configuration for the
official [Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi).
Vulnerabilities in the driver binary itself belong in the upstream tracker;
vulnerabilities in chart defaults, RBAC, privilege configuration, or CI
belong here.

## Security posture

- **No forked images**: the chart deploys the official `synology/synology-csi`
  and `registry.k8s.io/sig-storage` images. Pin `driver.digest` in production.
- **Controller & snapshotter**: non-root (65534), all capabilities dropped,
  `allowPrivilegeEscalation: false`, seccomp `RuntimeDefault`,
  read-only root filesystem.
- **Node plugin**: runs `privileged: true`. This is inherent to CSI node
  plugins (device management, filesystem mounts, chroot into the host root).
  It is identical to the upstream deployment and to every iSCSI CSI driver.
  Do not attempt to run it unprivileged.
- **RBAC**: least privilege per component, transcribed from upstream and
  reviewable in `templates/serviceaccount-rbac.yaml`.
- **Credentials**: the `client-info` Secret (DSM credentials) is never created
  by the chart by default; bring your own (e.g. sealed secret). DSM traffic
  over HTTPS + `tlsCACert` is supported by the driver since v1.3.1.
