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
# synology-csi  synology-csi    5         deployed  synology-csi-ng-1.4.0      v1.4.0

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
kubectl -n synology-csi rollout status deployment/synology-csi-controller
kubectl -n synology-csi get pods -l app=synology-csi-controller
# All pods should be Running, with 6/6 or 7/7 containers ready (depending on version)

# 5. Gate: verify the node DaemonSet rolled out
kubectl -n synology-csi rollout status daemonset/synology-csi-node
kubectl -n synology-csi get pods -l app=synology-csi-node
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
kubectl -n synology-csi get pods -l app=synology-csi-node -o wide | grep $NODE

# Check logs
kubectl -n synology-csi logs -l app=synology-csi-node --tail=100 | grep -i "error\|panic\|not found"

# Check the CSI socket on the node (if you have SSH access)
# talosctl ssh -n $NODE
# ls -la /var/lib/kubelet/plugins/csi.synology.com/
# Should show csi.sock
```

### Remedy

**Restart the node plugin pod on the affected node**:

```bash
# Delete the pod — the DaemonSet will recreate it
NODE=miracle
POD=$(kubectl -n synology-csi get pods -l app=synology-csi-node -o wide | grep $NODE | awk '{print $1}')
kubectl -n synology-csi delete pod $POD

# Wait for the new pod to be ready
kubectl -n synology-csi rollout status daemonset/synology-csi-node --timeout=5m

# Verify
kubectl -n synology-csi get pods -l app=synology-csi-node -o wide | grep $NODE
# Should be Running, 3/3 ready
```

If the pod keeps crashing, check the node's kubelet logs and the node plugin logs for the root cause (often a stale iSCSI session or a DSM connectivity issue).

---

## Purge stale iSCSI sessions

### Symptom

A pod fails to mount an iSCSI PVC after being rescheduled to a different node:

```
MountVolume.Attach failed: rpc error: code = Internal desc = Failed to login to iSCSI target: iscsiadm: Login failed (exit code 24)
```

Or on DSM → iSCSI Manager → Connected Initiators, you see multiple sessions from the same initiator IQN, some stale.

### Cause

When a pod is evicted or a node crashes, the iSCSI session on the old node may not be cleanly logged out. DSM still thinks the old node is connected, and some DSM versions reject new connections from the same IQN until the old session is cleared.

### Procedure (tested 2026-10-01)

**Option 1: Log out from the old node (if reachable)**

```bash
# SSH to the old node (or use talosctl ssh)
# List active iSCSI sessions
iscsiadm -m session

# Log out all sessions (or specify the target)
iscsiadm -m node --logout

# Verify
iscsiadm -m session
# Should be empty or show only active sessions
```

**Option 2: Purge via a privileged debug pod (if the node is unreachable)**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: iscsi-cleanup
  namespace: synology-csi
spec:
  nodeName: miracle  # the affected node
  hostPID: true
  hostNetwork: true
  containers:
    - name: iscsiadm
      image: alpine:3.20
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        privileged: true
      volumeMounts:
        - name: iscsi-dir
          mountPath: /etc/iscsi
        - name: sys
          mountPath: /sys
  volumes:
    - name: iscsi-dir
      hostPath:
        path: /etc/iscsi
        type: DirectoryOrCreate
    - name: sys
      hostPath:
        path: /sys
```

```bash
kubectl apply -f iscsi-cleanup.yaml
kubectl -n synology-csi exec -it iscsi-cleanup -- sh

# Inside the pod:
apk add open-iscsi
iscsiadm -m session
iscsiadm -m node --logout

# Verify, then exit and delete the pod
exit
kubectl -n synology-csi delete pod iscsi-cleanup
```

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

The driver uses `nolock,vers=3` by default for NFSv3. If you are manually mounting to test:

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

If the share name on DSM is truncated to 32 chars but the driver tries to mount the full name, the mount fails. See `docs/DISASTER-RECOVERY.md` — this is patched in our builds.

**5. Check DSM logs**

DSM → Log Center → filter by "NFS" or "File Services". Look for:
- `NFS_SHARE_LOAD_FAIL` (error 2370) — concurrent saves lost the rule
- `NFS_SHARE_NOT_FOUND` — the share does not exist (truncation issue)

---

## Controller sizing

The controller deployment (`synology-csi-controller`) runs the CSI sidecars (provisioner, attacher, resizer, snapshotter) + the driver itself. It talks to DSM for every PVC operation, so it is I/O-bound on the DSM API, not CPU-bound.

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
    kind: Deployment
    name: synology-csi-controller
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
- **>500 PVCs**: consider running 2 controller replicas (the sidecars use leader election, so only one is active at a time, but the others are ready to take over)
- **Frequent snapshot operations**: increase CPU requests to 100m (snapshotter is CPU-intensive during large snapshot lists)

---

## Emergency contacts

- **DSM unreachable**: check network, then DSM → Control Panel → Terminal & SNMP → Terminal → enable SSH, then SSH in and check `/var/log/messages` for NFS/iSCSI errors
- **Driver pods CrashLoopBackOff**: check logs (`kubectl logs -n synology-csi -l app=synology-csi-controller --tail=200`), then restart the pod
- **Data loss suspected**: do NOT delete the PVC or PV. Follow `docs/DISASTER-RECOVERY.md` to snapshot/clone the LUN first, then investigate
