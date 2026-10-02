# Code review, driver v1.4.0 (upstream tag, audited 2026-10-01)

Sweep sécurité / performance / stabilité sur le tag upstream v1.4.0, préalable aux
fix-branches de ce projet. Chaque finding cite `fichier:ligne`. Les findings
marqués **↔ #NN** confirment la cause racine d'une issue upstream ouverte.

## CRITIQUE

**C1. Data race généralisée sur `DSM.Sid` et la map `dsms`, zéro mutex dans `pkg/`**
`webapi/dsmwebapi.go:235` (écriture `Sid` au login), `:140-143` (lecture cookie),
`:95-102` (re-login concurrent depuis n'importe quel handler gRPC) ;
`service/dsm.go:24-26,59` (map `dsms` sans lock) ; `main.go:81` (`Logout` mute `Sid`
serveur tournant). Aucun `sync.Mutex` dans `pkg/` hormis le WaitGroup de `grpc.go:50`.
Effet : data race (-race la détecte), tempêtes de re-login qui s'invalident mutuellement.
Fix : RWMutex par DSM + singleflight sur le login + lock sur la map.

**C2. Mot de passe DSM en query string GET + loggué en clair en debug**
`dsmwebapi.go:211-217` (passwd en params de GET), `:130-132` (`log.Debugln(RawQuery)`
= mot de passe dans les logs debug). La redaction `:225-227` ne couvre que le chemin
d'erreur du Login. **↔ #100, #35**. Fix : POST form + redaction systématique.

**C3. Aucun timeout HTTP vers le DSM**
`dsmwebapi.go:59` (`&http.Client{}`) et `:87-90`, pas de Timeout ni de contexte ;
`sendRequest` peut bloquer indéfiniment → handler gRPC gelé + chaînes de backoff
bloquées. **↔ #105, #73** (logins qui « hang »). Fix : `http.Client{Timeout}` ou
contexte par requête.

**C4. Panics non récupérés dans les hot paths** (le seul interceptor gRPC est un
logger, `grpc.go:94-96`, un panic = crash du driver entier)
- `multipath.go:167-176` : garde `len(columns) < 5` mais accès `columns[5]`/`[6]` ;
  split sur `" "` simple au lieu de whitespace.
- `initiator.go:88` : `strings.Split(e[3], ":")[1]` panique sur un IQN sans `:`
  (formats `eui.*`/`naa.*`).
Fix : bornes + `strings.Fields` + guard.

## MAJEUR

**M1. NVMe non idempotent : `SubsystemGet("")` après AlreadyExist**:
`namespace_volume.go:45-57` + `nvmeof.go:339-341` : UUID vide → CreateVolume échoue
en boucle et le rollback supprime le namespace créé. Fix : résoudre par nom/NQN
(comme `createMappingTarget`, `dsm.go:200`).

**M2. `hasNVMeSession` ne peut jamais retourner true**, `nvme_connector.go:133-138`
lit `/sys/class/nvme-fabrics/ctl` (un FICHIER) avec `os.ReadDir` → erreur → false →
re-connect à chaque Publish/Stage. Fix : itérer `/sys/class/nvme/`.

**M3. iscsiadm/nvme exécutés sans timeout**, `initiator.go:112-208`,
`nvme_connector.go:40-75` : `CombinedOutput()` sans contexte ; seul multipath a un
timeout. Une découverte sendtargets qui traîne gèle le gRPC.

**M4. DeleteVolume iSCSI : succès déclaré sur toute erreur TargetGet**:
`dsm.go:772-777` : target potentiellement orpheline sur le DSM après un flap réseau.
Fix : restreindre au code « no such target » (à ajouter dans `webapi/iscsi.go`).

**M5. Idempotence snapshots : erreurs de listing avalées**, `dsm.go:904-912`,
`:1061-1069`, `:1071-1075`, `:1149-1156` : nil retourné sans distinguer
« inexistant » d'« erreur » → doublons de snapshots ou suppressions fantômes.

**M6. Règles NFS : `Insecure: true` + `Crossmnt: true` codés en dur**:
`nodeserver.go:455-467`, en plus du `RootSquash: "root"` non configurable (`:460`).
Fix : configurable par StorageClass, défaut durci.

**M7. Targets iSCSI sans CHAP, code mort**, `webapi/iscsi.go:301`
(`auth_type: "0"` duré), `initiator.go:33-37` + `utils.go:74-77` (chapUser/chapPassword
vides, jamais alimentés). **↔ #82, #63.** Fix : CHAP via secrets de StorageClass.

**M8. Mot de passe SMB non échappé dans les options de mount**:
`nodeserver.go:677` : `username=%s,password=%s`, un mot de passe avec `,`, ` ` ou `=`
casse le parsing mount(8). **↔ #59** (erreurs SMB inexpliquées). Fix : fichier
`credentials=` ou échappement.

**M9. PERF : `NodeGetVolumeStats` (poll kubelet) = listing cross-protocole complet
du DSM**, `nodeserver.go:1038` → `GetVolume` → un `LunGet` par mapping
(`dsm.go:800-816` alors que `LunList` existe) + subsystem par namespace + shares.
Fix : cache TTL ou résolution directe par UUID.

**M10. PERF : idempotence snapshots = tempête N+1**, `controllerserver.go:457` →
`ListAllSnapshots` (`dsm.go:1137-1147`) : re-liste tous les volumes puis un appel
snapshot par volume. Idem CreateVolume par clone et DeleteSnapshot.

**M11. PERF : nouveau `http.Client` + `Transport.Clone()` par requête**:
`dsmwebapi.go:108` : zéro réutilisation de connexion, handshake TLS par appel.
Fix : un client par DSM.

## MINEUR

**m1. Troncature de nom : collisions → faux « AlreadyExists » et réutilisation du
share d'autrui**, `models/dsm.go:46-52` (`GenShareName`, coupe à 32) ;
`dsm.go:851-859` (`GetVolumeByName` retourne le volume de l'AUTRE PVC).
**↔ #52** (« Already existing volume name with different capacity »), **↔ #96**
(demande de contrôle du nommage). Fix : suffixe hash court au lieu d'une coupe brute.

**m2. Erreur DNS jetée dans `LookupIPv4`**, `utils.go:68` (`ips, _ := net.LookupIP`).
Fix : propager + backoff.

**m3. `getNodeAddress` liste tous les nœuds à chaque stage NFS / mount échoué**:
`nodeserver.go:692,888` (via `:408-428`). Fix : cache.

**m4. `lsblk` court-circuite hostexec (bypass chroot) ; regex recompilée à chaque
appel**, `multipath.go:145-146`, `:39-51`. Fix : `t.executor` + cache.

**m5. Appels DSM séquentiels parallélisables**, `systeminfo.go:31-51` (3 appels au
login) ; `webapi/utils.go:47-79` (GetAnotherController, heuristique IPv4 fragile).

**m6. Le driver démarre sans aucun DSM joignable**, `main.go:75-80` : échec AddDsm
seulement loggué → toutes les requêtes serviront « dsm does not exist ».
Fix : fail-fast ou reconnexion périodique.

**m7. Nom de snapshot reconstruit depuis `Desc` éditable**, `dsm.go:1202` →
`GetSnapshotByName` rate l'idempotence → doublons. Fix : stocker le nom réel.

**m8. `isNfsVersionSupport` modifie la config du DSM** (effet de bord :
`NfsSet(true)`), `dsm.go:599-602`, appelé depuis CreateVolume (`:694-698`).
Fix : séparer check lecture seule et activation.

**m9. `MappedLuns[0]` sans garde**, `nodeserver.go:293,318,1131` : panic possible
sur un volume fraîchement créé. **↔ #22, #4** (corruptions/comportements erratiques).
Fix : garde `len > 0`.

## Conforme (vérifié, pas de finding)

- TLS : `InsecureSkipVerify` opt-in + warning, `tlsCACert` prioritaire
  (`dsmwebapi.go:68-85`).
- Secrets gRPC : `protosanitizer.StripSecrets` (`grpc.go:121-131`).
- Saves NFS concurrents : atténués (verify + retry borné, `share.go:494-530`) ;
  skip-save si règles présentes (`nodeserver.go:481-491`).
- Confirmed : `/usr/bin/env` hardcodé (`hostexec.go:67`), seules les commandes non
  résolues par `cmdMap` le subissent (iscsiadm/nvme/multipathd).
