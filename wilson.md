# OpenShift Virtualization / platform note: nested KVM and Arista vEOS (MSR failure)

**Audience:** OpenShift Virtualization (KubeVirt) administrators and **platform** engineers—not network image builders.

**Scope:** The Arista **vEOS** router image used in this workshop is **vendor-supplied and used verbatim**; it **already runs** on other clusters with the same topology. When it fails **only on certain OpenShift worker pools**, the evidence points at **how this cluster virtualizes nested guests**, not at “rebuild the vEOS container.”

---

## Captured logs (2026-05-14 incident)

Use these as attachments or diff references against a **known-good** worker:

* [`wilson/docker-logs-clab-routers-rtr2.txt`](wilson/docker-logs-clab-routers-rtr2.txt) — `docker logs clab-routers-rtr2`: **`qemu cmd:`** (`-enable-kvm`, **`-cpu host,level=9`**), **MSR `0x345` / `kvm_buf_set_msrs`** failure, 60× monitor retry, **`QemuBroken`**.
* [`wilson/containerlab-inspect.txt`](wilson/containerlab-inspect.txt) — `containerlab inspect`: both **Arista** nodes **`exited`**, Cisco/Juniper still **running**.
* [`wilson/host-kvm-sanity.txt`](wilson/host-kvm-sanity.txt) — `uname -r`, **`/dev/kvm`** on the lab VM (shows KVM is *present* at L1, not that nested MSRs work for L3).

---

## 1. Minimal lab context (what runs inside the VM)

The failing workload lives on the **containerlab** user VM (RHEL 9 guest under KubeVirt). That VM runs **Docker** (or Podman) and **Containerlab**, which starts **per-router containers**. Each Arista container runs **vrnetlab**: **QEMU + KVM** inside the container emulating vEOS.

High-level placement in this repo’s deployments: see `config/instances.yaml` (VM name **containerlab**, image such as `ansiblebu-containerlab-v2`). Other VMs (AAP **control**, **vscode**) do not run nested QEMU for vEOS.

---

## 2. Nested virtualization stack (why the platform matters)

```text
[L0] OpenShift worker → KVM (host)
       │
[L1] KubeVirt VirtualMachineInstance (“containerlab” RHEL guest) — /dev/kvm, guest kernel
       │
[L2] container engine — runs clab-routers-rtr2 / rtr4
       │
[L3] qemu-system-x86_64 inside the container — -enable-kvm, -cpu host,level=9 → inner vEOS guest
```

**Nested KVM:** L3’s QEMU uses **KVM on L1’s kernel**. Programming **MSRs** for the inner vCPU goes through **L0/L1 nested-virt rules**. If the **worker CPU model**, **VM CPU spec**, **kernel**, or **nested-virt enablement** on **this** cluster differs from a cluster where the **same** image works, you can get **MSR write failures** even though **`/dev/kvm` exists on L1**.

**Why only Arista:** Cisco and Juniper nodes in the same topology use **different QEMU CPU options** than vEOS; they may keep running while **both** Arista nodes show **`exited`** (see inspect log).

---

## 3. Failure signature (for triage)

| Signal | Meaning |
|--------|--------|
| `failed to set MSR 0x345` / `kvm_buf_set_msrs` in **QEMU STDERR** | KVM rejected an MSR in the **nested** path; QEMU exits immediately. |
| Long **`Unable to connect to qemu monitor (port 4000)`** loop | vrnetlab waits on a monitor that never comes up because **QEMU already died**. |
| **`QemuBroken`** at end of container log | Same root cause—not a separate “port 4000” bug. |
| **`containerlab inspect`**: Arista **exited**, others **running** | Confirms **vEOS/QEMU path** on this worker, not generic “lab is down.” |

**Not the fix:** `containerlab destroy` + `deploy` **alone** does not change L0/L1 nested behavior; if MSR errors persist, the problem remains **virtualization policy / worker / CPU model**, not stale topology.

---

## 4. What to tune on OpenShift Virtualization (primary lever)

Because the **vendor image is fixed**, focus on **making nested KVM + MSR behavior match a known-good cluster**.

**Compare against a working cluster**

* Same **OpenShift / KubeVirt / virt-launcher** versions?
* Same **CPU vendor** (Intel vs AMD) and **CPU feature** set on workers?
* Same **`VirtualMachine` / `VirtualMachineInstance` CPU** block (e.g. `host-passthrough` vs `host-model` vs explicit `models` / `features`)?

**Typical platform-side knobs to review**

1. **`VirtualMachine` CPU mode** — Aggressive **host passthrough** to L1 can change which features MSRs L3’s QEMU tries to use. Align with a template that works elsewhere (often **less** passthrough, or explicit **CPU type** compatible with nested guests).
2. **Nested virtualization** — Confirm **nested virt** is intended and consistently **enabled** on workers that run this lab (and not “sometimes” depending on node pool).
3. **Scheduling** — Pin or **prefer** workers where the lab is **known-good**; avoid mixed pools where only some nodes expose the right nested MSR behavior.
4. **Kernel / microcode / firmware** on workers — Large skew vs the working cluster can change KVM MSR handling.
5. **KubeVirt feature gates and defaults** — Any cluster-specific overrides that affect CPU topology or machine type.

**Evidence to collect on a failing worker (in addition to the `wilson/` logs)**

* `VirtualMachine` / `VirtualMachineInstance` YAML for the **containerlab** guest (CPU section, node selector, tolerations).
* Worker labels and **CPU model** (`kubectl get nodes -o wide`, and host-level `/proc/cpuinfo` if you have host access).
* **Kubevirt** and **OpenShift** versions on failing vs passing cluster.

---

## 5. Escalation one-liner (platform ticket)

**Nested KVM on this OpenShift worker: inner QEMU (vendor vEOS vrnetlab, `-cpu host,level=9`) fails `MSR 0x345` / `kvm_buf_set_msrs`; same vendor image works on other clusters—tune VM CPU / nested virt / worker pool to match known-good virtualization behavior.**

Attachments: [`wilson/docker-logs-clab-routers-rtr2.txt`](wilson/docker-logs-clab-routers-rtr2.txt), [`wilson/containerlab-inspect.txt`](wilson/containerlab-inspect.txt), [`wilson/host-kvm-sanity.txt`](wilson/host-kvm-sanity.txt), plus **VMI spec** and **worker** comparison to a **working** site.

---

## 6. Related repo pointers (optional)

* `config/instances.yaml` — lab VM sizing and services (not a substitute for live VMI YAML).
* `README-containerlab.md` — includes a shorter **QEMU / MSR** note for lab operators.

This document is **guidance only**; it does not change cluster configuration.
