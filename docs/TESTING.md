# Testing protocol

This is the functional validation protocol used to certify a chart/driver
combination against a real cluster. It catches the failure modes that pure
linting cannot see (host tool resolution, node affinity, volume lifecycle).

Prerequisites:
- A test StorageClass on your iSCSI-enabled Synology volume
- Three (or at least two) nodes

## 1. Provision + write

```sh
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: csi-test, namespace: default}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: <your-test-class>
  resources: {requests: {storage: 2Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: csi-test, namespace: default}
spec:
  restartPolicy: Never
  containers:
  - name: t
    image: alpine:3.20
    command: ["sh","-c","echo ok-$(hostname) > /data/ok.txt && sleep 3600"]
    volumeMounts: [{name: d, mountPath: /data}]
    resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 128Mi}}
  volumes:
  - name: d
    persistentVolumeClaim: {claimName: csi-test}
EOF
# Expect: phase=Running and the marker echoed back
kubectl wait --for=condition=Ready pod/csi-test --timeout=180s
kubectl exec csi-test -- cat /data/ok.txt
```

## 2. Cross-node move (the Talos killer)

```sh
kubectl delete pod csi-test --wait=true
# wait for full volume detach before rescheduling, racing it produces
# Multi-Attach noise that is NOT a driver bug
while kubectl get volumeattachments | grep -q csi-test; do sleep 4; done
# reschedule on a different node
kubectl patch pod ... # or recreate the pod with nodeName set to another node
kubectl logs csi-test   # expect: ok-<first-hostname>
```

## 3. Known non-issues (do not file bugs for these)

- `env: can't execute 'iscsiadm'`, the chart's `--chroot-dir` /
  `--iscsiadm-path` flags are missing or wrong. This is a deployment
  config failure, not a driver bug.
- First PVC creation takes 20-40 s (DSM API LUN creation + iSCSI attach
  + mkfs). A pod created in the same `kubectl apply` may exhaust its
  mount retries while the PVC is still binding. Delete the pod and
  recreate it once the PVC is Bound.
- A container running as non-root (uid != 0) cannot write to the root
  of a freshly formatted XFS volume. That is a filesystem permission
  topic, not storage provisioning.
- One scrape/mount failure during a driver rollout is transient; the
  next attempt succeeds once the new plugin pods are Ready.

## 4. Cleanup

```sh
kubectl delete pod csi-test pvc/csi-test
# reclaimPolicy Delete: the LUN is destroyed on the DSM. Verify in
# DSM Storage Manager if you want to be thorough.
```
