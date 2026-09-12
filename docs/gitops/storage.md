# Storage (planned GitOps app)

**Where this fits:** After the current [GitOps catalog](./README.md) (ingress, cert-manager, TLS, Kyverno). Storage labs can use any Day 0 cluster; they are **not implemented in Git yet**.

**Repo status:** Notes only. No OpenEBS/NFS manifests in `gitops/` at time of writing. When you add them, follow [growing.md](./growing.md).

---

## Overview

Kubernetes storage generally falls into two categories:

1. **Block Storage** – Storage presented as a dedicated disk.
2. **File Storage** – Storage presented as a shared filesystem.

---

# Block Storage

## What is it?

Block storage presents storage as a disk device to an application.

```text
Application
    ↓
Virtual Disk
    ↓
Storage Backend
```

Examples:

- AWS EBS
- Azure Managed Disk
- Google Persistent Disk
- Ceph RBD

---

## Typical Access Mode

```yaml
accessModes:
  - ReadWriteOnce
```

(RWO)

This means the volume is typically mounted for read/write by a single node at a time.

---

## Common Use Cases

- PostgreSQL
- MySQL
- MongoDB
- Kafka
- Stateful applications

---

## Mental Model

> Block Storage = Giving a pod its own hard drive.

---

# File Storage

## What is it?

File storage presents a shared filesystem that multiple pods can access simultaneously.

```text
Pod A ─┐
Pod B ─┼── Shared Filesystem
Pod C ─┘
```

Examples:

- NFS
- AWS EFS
- Azure Files
- CephFS

---

## Typical Access Mode

```yaml
accessModes:
  - ReadWriteMany
```

(RWX)

Multiple pods can read and write at the same time.

---

## Common Use Cases

- User uploads
- Shared website assets
- Shared reports/documents
- Shared ML model files
- Legacy applications requiring shared folders

---

## Mental Model

> File Storage = Giving multiple pods access to the same network drive.

---

# RWO vs RWX

## ReadWriteOnce (RWO)

```yaml
accessModes:
  - ReadWriteOnce
```

Typical pattern:

```text
One Volume
     ↓
 One Pod/Node
```

Usually backed by block storage.

---

## ReadWriteMany (RWX)

```yaml
accessModes:
  - ReadWriteMany
```

Typical pattern:

```text
           Shared Filesystem
                 ↑
      ┌──────────┼──────────┐
      ↓          ↓          ↓
    Pod A      Pod B      Pod C
```

Usually backed by file storage.

---

# Is RWX Always File Storage?

Not always, but almost always.

Most RWX implementations use:

- NFS
- EFS
- Azure Files
- CephFS

Some enterprise storage solutions support RWX using shared block devices and clustered filesystems, but these are uncommon.

### Practical Rule

> If you see RWX, assume shared file storage unless proven otherwise.

---

# Choosing the Right Storage

| Workload | Recommended Storage |
|-----------|-------------------|
| PostgreSQL | Block Storage |
| MySQL | Block Storage |
| MongoDB | Block Storage |
| Kafka | Block Storage |
| User Uploads | File Storage |
| Shared Documents | File Storage |
| Shared Website Assets | File Storage |
| Shared ML Models | File Storage |

---

# Learning Kubernetes storage (Kind is enough; any cluster works)

## Goal 1: Learn Block Storage

Create:

```text
PV
 ↓
PVC (RWO)
 ↓
Pod
```

Using:

```yaml
hostPath:
  path: /tmp/block-storage
```

Concepts learned:

- PersistentVolume (PV)
- PersistentVolumeClaim (PVC)
- Persistent data
- Stateful workloads

---

## Goal 2: Learn File Storage

Run an NFS server and create an RWX PVC.

Architecture:

```text
NFS Server
     ↓
 RWX PVC
     ↓
 ┌─────────┐
 │         │
 ↓         ↓
Pod A   Pod B
```

Experiment:

### Pod A

```bash
echo hello > /shared/file.txt
```

### Pod B

```bash
cat /shared/file.txt
```

Expected result:

```text
hello
```

Concepts learned:

- Shared filesystem
- Multi-pod access
- RWX behavior

---

# Hands-on path (after current GitOps core apps)

Track progress in [gitops/README.md](./README.md) when you complete each lab.

## Lab 1

Learn PV/PVC basics using:

```text
hostPath
```

---

## Lab 2

Learn shared storage using:

```text
NFS + RWX PVC
```

---

## Lab 3

Deploy:

```text
StatefulSet + PVC
```

Examples:

- PostgreSQL
- MySQL

---

## Lab 4

Install OpenEBS (candidate for a future Day 2 Application under `gitops/`)

Learn:

- CSI Drivers
- StorageClasses
- Dynamic Provisioning
- Production-like storage workflows

---

# Final Takeaway

## Block Storage

```text
Dedicated Disk
      ↓
Usually RWO
      ↓
Databases
```

Examples:

- PostgreSQL
- MySQL
- Kafka

---

## File Storage

```text
Shared Filesystem
       ↓
Usually RWX
       ↓
Shared Application Data
```

Examples:

- User uploads
- Shared documents
- Shared ML models

---

# Quick Rule of Thumb

If your application needs:

### A dedicated disk

Use:

```text
Block Storage
```

### Multiple pods sharing the same files

Use:

```text
File Storage
```