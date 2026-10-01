# Operations runbook — Synology CSI driver

> **Last validated**: 2026-10-01, driver v1.4.0 (patched), DSM 7.x, Talos Linux.
> **Audience**: cluster operators who need to upgrade, troubleshoot, or recover the driver.

---

## Driver upgrade

### Upgrade order

The driver has three layers that must be upgraded in sequence:

1. **DSM side** (if applicable): iSCSI Manager firmware, NFS service config. Usually no changes needed for driver upgrades, but check the release notes.
2. **CSI driver** (Helm chart + images): upgraded via `helm upgrade`.
3. **Workloads** (pods using PVCs): restarted after the driver upgrade to pick up new CSI capabilities.

### Upgrade procedure

```bash
# 1. Check current version
helm list -n synology-csi
# NAME          NAMESPACE       REVISION  STATUS    CHART                      APP VERSION
# synology-csi  synology-csi    5         deployed  synology-csi-ng-0.5.0      v1.4.0

# 2. Pull the new chart version
helm repo update synology-csi-ng
helm search repo synology-csi-ng/synology-csi-ng --versions

# 3. Upgrade (controller first, then node DaemonSet — Helm handles this)
helm upgrade synology-csi synology-csi-ng/synology-csi-ng \
  --namespace synology-csi \
  --values my-values.yaml \
  --wait \
  --timeout 10m

# 4. Gate: verify the controller is healthy
kubectl -n synology-csi rollout status statefulset/synology-csi-ng-controller
kubectl -n synology-csi get pods -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=controller
# All pods should be Running, with 4/4 containers ready (provisioner + attacher + resizer + csi-plugin)

# 5. Gate: verify the node DaemonSet rolled out
kubectl -n synology-csi rollout status daemonset/synology-csi-ng-node
kubectl -n synology-csi get pods -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=node
# One pod per node, all Running

# 6. Gate: verify existing PVCs still work
kubectl get pvc -A | grep -v Bound
# Should return nothing (all PVCs Bound)

# 7. Optional: restart workloads to pick up new CSI features
# kubectl rollout restart deployment/my-app -n my-namespace
```

### Rollback

If the upgrade fails the gates above:

```bash
helm rollback synology-csi -n synology-csi
# Then verify the gates again
```

---

## Restart a corrupted node plugin

### Symptom

Pods on a specific node fail to mount with:

```
MountVolume.MountDevice failed for volume "pvc-abc123" :
rpc error: code = Internal desc = Volume not found
```

Or:

```
Unable to attach or mount volumes: unmounted volumes=[data],
unattached volumes=[data]: timed out waiting for the condition
```

The `synology-csi-node` pod on that node is in `CrashLoopBackOff` or `Error` state, or the CSI socket is missing.

### Diagnosis

```bash
# Find the node plugin pod on the affected node
NODE=miracle  # or whatever the node name is
kubectl -n synology-csi get pods -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=node -o wide | grep $NODE

# Check logs
kubectl -n synology-csi logs -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=node --tail=100 | grep -i "error\|panic\|not found"

# Check the CSI socket on the node (Talos has no SSH — use `talosctl ls` / `talosctl read`, or a privileged pod with hostPath `/` mounted at `/host` + `chroot /host`)
# talosctl -n $NODE ls /var/lib/kubelet/plugins/csi.san.synology.com/
# Should show csi.sock
```

### Remedy

**Restart the node plugin pod on the affected node**:

```bash
# Delete the pod — the DaemonSet will recreate it
NODE=miracle
POD=$(kubectl -n synology-csi get pods -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=node -o wide | grep $NODE | awk '{print $1}')
kubectl -n synology-csi delete pod $POD

# Wait for the new pod to be ready
kubectl -n synology-csi rollout status daemonset/synology-csi-ng-node --timeout=5m

# Verify
kubectl -n synology-csi get pods -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=node -o wide | grep $NODE
# Should be Running, 2/2 ready (node-driver-registrar + csi-plugin)
```

If the pod keeps crashing, check the node's kubelet logs and the node plugin logs for the root cause (often a stale iSCSI session or a DSM connectivity issue).

---

## Purge stale iSCSI sessions

### Symptom

A pod fails to mount an iSCSI PVC after being rescheduled to a different node:

```
attachdetach.AttachVolume failed for volume "pvc-abc123": rpc error: code = Internal desc = Failed to remove target path: iscsiadm: session for target "iqn.2000-01.com.synology:Coven-Compass.pvc-abc123" still logged in on the old node, stale record blocks re-attach (VolumeAttachment stuck "Attaching")
```

Or on DSM → iSCSI Manager → Connected Initiators, you see multiple sessions from the same initiator IQN, some stale.

### Cause

When a pod is evicted or a node crashes, the iSCSI session on the old node may not be cleanly logged out. DSM still thinks the old node is connected, and some DSM versions reject new connections from the same IQN until the old session is cleared.

### Procedure (tested 2026-10-01)

Privileged pod + `chroot /host` using the host's `iscsiadm`.

Talos nodes have no SSH and no shell in the rootfs. The `synology-csi` namespace is already privileged, so run a one-shot pod on the affected node with `hostPID: true`, `hostNetwork: true`, and `/` mounted at `/host`. The pod image (alpine is fine) does NOT need `open-iscsi` — `iscsiadm` comes from the host rootfs via `chroot /host`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: iscsi-fix
  namespace: synology-csi
spec:
  nodeName: miracle  # the affected node
  hostNetwork: true
  hostPID: true
  restartPolicy: Never
  containers:
    - name: c
      image: alpine:3.20
      command: ["sleep", "600"]
      securityContext:
        privileged: true
      volumeMounts:
        - name: root
          mountPath: /host
  volumes:
    - name: root
      hostPath:
        path: /
```

```bash
kubectl apply -f iscsi-fix.yaml
kubectl -n synology-csi wait --for=condition=Ready pod/iscsi-fix --timeout=60s

# 1. List sessions (each line is an active iSCSI session on the host)
kubectl exec -n synology-csi iscsi-fix -- chroot /host /usr/local/sbin/iscsiadm -m session

# 2. Identify which PVC-UIDs are orphaned (LUN already deleted on DSM) vs still active.
#    KEEP the session of any PVC still bound to a running pod
#    (e.g. pvc-39cf71a9 = vmsingle — do NOT log this one out).

# 3. Logout ONLY the stale/orphan targets, one by one, by IQN:
kubectl exec -n synology-csi iscsi-fix -- \
  chroot /host /usr/local/sbin/iscsiadm -m node \
  -T iqn.2000-01.com.synology:Coven-Compass.<pvc-uid> --logout
# Expected: "Logout of [sid: N, target: ...] successful."

# 4. Verify
kubectl exec -n synology-csi iscsi-fix -- chroot /host /usr/local/sbin/iscsiadm -m session

# 5. Cleanup
kubectl -n synology-csi delete pod iscsi-fix
```

⚠️ **Do NOT run `iscsiadm -m node --logout` without `-T <IQN>`** — that logs out every session, including volumes still in use.

**Option 3: Disconnect from DSM side**

DSM → iSCSI Manager → Connected Initiators → select the stale session → **Disconnect**.

This is the nuclear option — it disconnects the initiator even if it is still actively using the LUN. Use only when you are sure the session is stale.

---

## NFS diagnostics

### Symptom

NFS mount fails with:

- `mount.nfs: access denied by server`
- `mount.nfs: Connection refused`
- `mount.nfs: No such file or directory`
- `mount.nfs: Operation not permitted`

### Diagnostic checklist

**1. Check the NFS export rule on DSM**

DSM → Shared Folder → select the PVC share → Edit → NFS Permissions. Verify:

- **Enable NFS service** is checked
- **Hostname or IP** matches the node IP (not the pod IP, not the cluster CIDR)
- **Privilege** is Read/Write (or Read-only if that is what you want)
- **Squash** is set correctly (default is `root` — see below)
- **Security flavor** is `sys` (kerberos is not supported by the driver)

**2. Check the mount options**

The driver passes `mountOptions` from the StorageClass through to the mount call (`pkg/driver/nodeserver.go:842`) — it does NOT inject `nolock,vers=3` on its own. Configure them on the StorageClass (e.g. `mountOptions: [nolock, vers=3]`). If you are manually mounting to test:

```bash
# On the node:
mount -t nfs -o nolock,vers=3 synology:/volume1/pvc-abc123 /mnt/test

# For NFSv4.1:
mount -t nfs -o vers=4.1 synology:/volume1/pvc-abc123 /mnt/test
```

**⚠️ Quirk**: NFSv4.1 on DSM may return `No such file` even if the share exists. Stick with NFSv3 (`vers=3`) unless you have a specific reason to use v4.1.

**3. Check root squash**

The driver hardcodes `RootSquash: "root"` in `pkg/driver/nodeserver.go:460`. This means:
- Root on the client (node) is squashed to the anonymous user on DSM
- If the PVC was created with root-owned files, the pod (running as non-root) may not be able to read them

**Fix**: our patch makes `RootSquash` configurable via the `CSI_NFS_ROOT_SQUASH` environment variable (see `patches/v1.4.0/0001-nfs-configurable-root-squash-and-2370-retry.patch`). Set it to `all` or `none` in the node plugin DaemonSet if needed.

**4. Check the share name truncation**

If the share name on DSM is truncated to 32 chars but the driver mounts the full name, the mount fails server-side. NOTE: this is an upstream bug on the mount path, NOT fixed in our builds — see `docs/CODE-REVIEW-v1.4.0.md` (finding m1).

**5. Check DSM logs**

DSM → Log Center → filter by "NFS" or "File Services". Look for:
- `NFS_SHARE_LOAD_FAIL` (error 2370) — concurrent saves lost the rule
- `NFS_SHARE_NOT_FOUND` — the share does not exist (truncation issue)

---

## Controller sizing

The controller StatefulSet (`synology-csi-ng-controller`, 4 containers: provisioner + attacher + resizer + csi-plugin) runs the CSI sidecars + the driver itself; the snapshotter runs in a separate Deployment (`synology-csi-ng-snapshotter`, 2 containers). The node plugin is a DaemonSet (`synology-csi-ng-node`, 2 containers: node-driver-registrar + csi-plugin). The controller is I/O-bound on the DSM API, not CPU-bound.

### Recommended resources

Based on observed usage (01/10/2026, ~50 PVCs, 3 nodes):

```yaml
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    memory: 256Mi
    # No CPU limit — see pemberton-cluster conventions (CFS throttling on N100)
```

### VPA-style sizing

If you want to right-size based on actual usage, deploy a VPA in `Off` mode (recommendations only):

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: synology-csi-controller-vpa
  namespace: synology-csi
spec:
  targetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: synology-csi-ng-controller
  updatePolicy:
    updateMode: "Off"
```

Then check recommendations:

```bash
kubectl -n synology-csi get vpa synology-csi-controller-vpa -o yaml | grep -A 10 "recommendation:"
```

**⚠️ Convention**: we keep VPA in `Off` mode (recommendations only) and manually copy targets into manifests. `Auto` mode rewrites pod requests live and restarts pods, which diverges from git and can evict single-replica apps. See the pemberton-cluster conventions.

### When to scale up

- **>100 PVCs**: increase memory to 256Mi requests, 512Mi limits
- **>500 PVCs**: consider running 2 controller replicas on the StatefulSet (the sidecars use leader election, so only one is active at a time, but the others are ready to take over)
- **Frequent snapshot operations**: increase CPU requests to 100m (snapshotter is CPU-intensive during large snapshot lists)

---

## Emergency contacts

- **DSM unreachable**: check network, then DSM → Control Panel → Terminal & SNMP → Terminal → enable SSH, then SSH in and check `/var/log/messages` for NFS/iSCSI errors
- **Driver pods CrashLoopBackOff**: check logs (`kubectl logs -n synology-csi -l app.kubernetes.io/name=synology-csi-ng,app.kubernetes.io/component=controller --tail=200`), then restart the pod
- **Data loss suspected**: do NOT delete the PVC or PV. Follow `docs/DISASTER-RECOVERY.md` to snapshot/clone the LUN first, then investigate
