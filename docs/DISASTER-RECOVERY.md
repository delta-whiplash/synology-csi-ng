# Disaster recovery, Synology CSI PVCs

> **Scope**: backup and restore of PVCs backed by the Synology CSI driver (iSCSI LUNs, NFS shares, SMB shares).
>
> **Validation status**: only the iSCSI session purge procedure in `docs/OPERATIONS.md` has been executed end-to-end (marked `tested 2026-10-01`). The snapshot/restore, LUN-clone, and manual PV re-attach paths below are **untested, validate before relying on them** in a real disaster.

## Mental model: LUN vs share

Before planning DR, understand what the driver actually creates on DSM:

| Protocol | What the driver creates on DSM | What Kubernetes sees | Backup implication |
|---|---|---|---|
| **iSCSI** | A **LUN** (block device) inside an existing volume group | A block PV, formatted with a filesystem (ext4/xfs) by the node | **Block-level**, you back up the LUN (snapshot, clone, or replication). The filesystem inside is opaque to DSM. |
| **NFS** | A **shared folder** on a volume, with NFS export rules | A filesystem PV (the folder itself) | **File-level**, you back up the share contents (rsync, Synology Hyper Backup, etc.). DSM sees the files. |
| **SMB** | A **shared folder** with SMB/CIFS sharing enabled | A filesystem PV | **File-level**, same as NFS. |

**The LUN is block, the share is files.** This determines your backup strategy.

---

## iSCSI PVCs: LUN snapshots + Velero

### Option 1: CSI snapshots (recommended)

The Synology CSI driver supports `VolumeSnapshot` via the DSM API. This creates a point-in-time snapshot of the LUN on the NAS.

**Prerequisites**:
- `VolumeSnapshotClass` configured, rendered from `charts/synology-csi-ng/templates/storageclasses.yaml:20-29` when `volumeSnapshotClasses` is non-empty in values (empty by default)
- Snapshotter sidecar running in the controller (default in our chart)

**Backup**:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-pvc-snapshot-20261001
  namespace: my-app
spec:
  volumeSnapshotClassName: synology-snapshotclass
  source:
    persistentVolumeClaimName: my-pvc
```

**Restore**:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc-restored
  namespace: my-app
spec:
  storageClassName: synology-iscsi-storage
  dataSource:
    name: my-pvc-snapshot-20261001
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi  # must be >= original PVC size
```

**Velero integration**:

Velero ≥ v1.15 ships CSI snapshot support built-in (the dedicated `velero-plugin-for-csi` repo is archived and returns 404). On our cluster (Velero v1.18.1) no extra plugin or `--features=EnableCSI` flag is needed, Velero discovers `VolumeSnapshotClass` resources natively. Configure the backup storage location and Velero will include CSI snapshots automatically:

```bash
velero install \
  --provider <your-provider> \
  --bucket <your-bucket> \
  # ... other provider-specific flags
```

Then a scheduled backup includes all PVCs + their snapshots:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-synology-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
      - my-app
    defaultVolumesToRestic: false  # use CSI snapshots, not restic
    csiSnapshotTimeout: 10m
```

### Option 2: DSM-side LUN clone

If you prefer to manage backups at the NAS level (or need to restore without Kubernetes):

1. **DSM Control Panel** → **iSCSI Manager** → **LUN** → select the LUN → **Actions** → **Clone**
2. The clone is a new LUN with the same data at the point in time
3. To restore: delete the original PVC/PV, create a new PVC pointing to the cloned LUN (using `volumeHandle` in the PV spec, see "Manual PV re-attachment" below)

**Pros**: works even if Kubernetes is down. **Cons**: manual, no automation.

---

## NFS / SMB PVCs: rsync the share

NFS and SMB shares are folders on DSM volumes. The driver creates the folder and configures sharing, but the contents are regular files visible in DSM File Station.

### Backup with rsync

From a backup host (or a CronJob with a sidecar):

```bash
# NFS share mounted on DSM at /volume1/kubernetes/pvc-abc123
# Back up to a remote host:
rsync -avz --delete \
  user@synology:/volume1/kubernetes/pvc-abc123/ \
  /backup/nfs/pvc-abc123/

# Or from the node if the share is mounted:
rsync -avz --delete \
  /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~csi/pvc-abc123/mount/ \
  /backup/nfs/pvc-abc123/
```

**⚠️ Quirk**: the share name on DSM is truncated to 32 chars (see `docs/CODE-REVIEW-v1.4.0.md` finding **m1**). The driver mounts the full (untruncated) name, which does not exist on DSM. If you are backing up manually from DSM, use the truncated name.

### Backup with Synology Hyper Backup

DSM's built-in Hyper Backup can back up shared folders to external targets (S3, another NAS, etc.). Point it at `/volume1/kubernetes/` (or wherever your PVC shares live).

**Restore**: restore the folder to DSM, then re-attach the PVC (see below).

---

## Recovery order

When restoring a cluster from scratch (new Kubernetes, same DSM data), follow this order:

1. **Driver first**: deploy the Synology CSI driver (Helm chart). The driver must be running before any PVCs are created or re-attached, it registers the CSI endpoint that kubelet talks to.

   ```bash
   helm upgrade --install synology-csi ./charts/synology-csi-ng \
     --namespace synology-csi --create-namespace \
     --values my-values.yaml
   ```

2. **StorageClass**: the chart renders `StorageClass` objects from `values.storageClasses` (empty by default). Provide your own values file with the classes you need (e.g. `synology-iscsi-storage`, `synology-nfs-storage`) and reinstall/upgrade, there are no StorageClasses until you configure them.

3. **VolumeSnapshotClass**: same model, rendered from `values.volumeSnapshotClasses` (empty by default). Only required if you use CSI snapshots.

4. **PV re-attachment**: for **static PVs** (where you manually specify `volumeHandle`), the PV object must be recreated pointing to the existing LUN/share on DSM. For **dynamic PVCs** (where the driver created the LUN/share), Kubernetes will re-attach the existing PVC to the existing LUN/share automatically, the `volumeHandle` in the PV spec is the LUN UUID or share path, which does not change.

   **Manual PV re-attachment** (if needed):

   ```yaml
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: pvc-abc123-restored
   spec:
     capacity:
       storage: 10Gi
     csi:
       driver: csi.san.synology.com
       volumeHandle: pvc-abc123  # must match the LUN UUID or share name on DSM
       volumeAttributes:
         protocol: iscsi
     accessModes:
       - ReadWriteOnce
     persistentVolumeReclaimPolicy: Retain
     storageClassName: synology-iscsi-storage
   ```

5. **Workloads last**: once the PVCs are bound (check with `kubectl get pvc`), deploy the workloads (Deployments, StatefulSets). They will mount the restored data.

---

## Known pitfalls

### Stale iSCSI sessions on cross-node remount

**Symptom**: a pod is evicted from node A, rescheduled to node B, and fails to mount with `iscsiadm: login failed`. The LUN is still mapped to node A's iSCSI initiator on DSM.

**Cause**: the iSCSI session on node A was not cleanly logged out (pod deletion timeout, node crash, etc.). DSM still thinks node A is connected, and some DSM versions reject new connections from the same IQN until the old session is cleared.

**Fix**: see `docs/TESTING.md`, purge the stale session on DSM (iSCSI Manager → Connected Initiators → disconnect the old session) or log out from the old node if it is still reachable:

```bash
# On the old node (if reachable):
iscsiadm -m node --logout

# On DSM (via SSH or iSCSI Manager UI):
# iSCSI Manager → Connected Initiators → select the stale session → Disconnect
```

**Prevention**: consider setting `reclaimPolicy: Retain` on your StorageClasses (the chart default follows the upstream `reclaimPolicy: Delete` convention, see `values.yaml`). Retain keeps the PV/LUN alive after the PVC is deleted, which avoids the race where the driver deletes the LUN while the old session is still active.

### 32-char share name truncation

**Symptom**: NFS PVC provisioning succeeds, but the pod fails to mount with `mount.nfs: Connection refused` or `No such file or directory`.

**Cause**: DSM truncates share names to 32 characters. The driver generates names like `pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890` (48 chars), creates the share with the truncated name, but then tries to mount the **full** (untruncated) name, which does not exist on DSM.

**Fix**: this is an upstream bug on the mount path (the GenShareName create side has truncated correctly since v1.1.0; only the mount call still uses the untruncated name). See diagnosis in `docs/CODE-REVIEW-v1.4.0.md`. No patch in our builds fixes this yet.

**Workaround**: manually rename the share on DSM to match the truncated name, or patch the driver's mount path to truncate symmetrically.

### DSM export table losing entries

**Symptom**: NFS mount fails with `access denied by server`, but the export rule appears to exist in DSM → Shared Folder → NFS Permissions.

**Cause**: concurrent NFS privilege saves (multiple nodes staging the same PVC simultaneously) can cause DSM to report success without actually applying the rules. The export table becomes inconsistent.

**Fix**: the v1.4.0 driver includes a retry-with-verification loop (`ShareNfsPrivilegeSave` in `pkg/dsm/webapi/share.go:494-530`) that reads back the rules after saving and retries if they did not take effect. Our patch extends this to handle error 2370 (`NFS_SHARE_LOAD_FAIL`) as retriable.

**Workaround**: manually re-apply the NFS rule in DSM (uncheck and recheck "Enable NFS service" for the share, or edit the rule and save again).

---

## Testing your DR plan

Do not wait for a disaster to test recovery. Suggested drill:

1. **Monthly**: restore a non-production PVC from the latest snapshot to a test namespace. Verify the data is intact.
2. **Quarterly**: simulate a full cluster restore (new Kubernetes cluster, restore from Velero backup + DSM snapshots). Verify the recovery order and PV re-attachment.
3. **After driver upgrades**: re-test the DR procedure. Driver changes can affect `volumeHandle` format or snapshot behavior.

Document the results in your runbook (see `docs/OPERATIONS.md`).
