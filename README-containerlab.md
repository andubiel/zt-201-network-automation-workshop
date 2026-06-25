# Containerlab by hand (no Ansible)

Use this when you are **SSH’d into the containerlab VM** (e.g. **Containerlab terminal** in Showroom, or direct SSH) and want to **start/stop the network topology yourself** while you figure out **inventory** (IPs, ports, names) before or alongside the Ansible playbooks in `lab-automation/`.

Official docs: [Containerlab documentation](https://containerlab.dev/).

---

## 1. Where the topologies live

On a typical workshop image, lab content is under the lab user’s home, for example:

```bash
ls ~/
```

You may see folders such as:

- `1_multi_vendor_router`
- `2_multi_vendor_vxlan`
- `3_multi_vendor_security`
- `4_optional_other_topologies`

Each folder is usually one **topology**. Inside the one you care about (example: **multi-vendor routers**):

```bash
cd ~/1_multi_vendor_router
ls
```

You should see something like:

- `routers.clab.yml` — topology definition (name may vary; use `ls *.yml`)
- `configs/` — config snippets the lab uses

---

## 2. Check Containerlab is available

```bash
which containerlab || which clab
containerlab version
```

If the command is missing, stop here and fix the VM image or PATH.

Containerlab needs **Docker** or **Podman** with permissions (often **root** or user in the right group). If `deploy` fails with permission errors, use **`sudo`** for the commands below.

---

## 3. Deploy the lab

From the topology directory (where `routers.clab.yml` lives):

```bash
cd ~/1_multi_vendor_router
sudo containerlab deploy --reconfigure
```

- **`--reconfigure`** — if a lab was already deployed, this reapplies the topology (handy when iterating).
- If your file has another name:

  ```bash
  sudo containerlab deploy -t ./your-topology.clab.yml --reconfigure
  ```

**Wait** until the command finishes. Nodes need time to boot (often **1–3+ minutes** depending on size).

### Clean redeploy after VM stop/start or node conflicts

If the lab acts broken after the containerlab VM was **powered off**, **suspended/resumed**, or `deploy --reconfigure` fights **stale containers** (sometimes seen with **Arista vEOS**), tear the topology down fully, then deploy again — same sequence as `lab-automation/playbooks/1_multi_vendor_router_down.yml` plus deploy:

```bash
TOPO_DIR="$(cat /etc/containerlab/last-topology 2>/dev/null || echo /home/lab-user/1_multi_vendor_router)"
cd "$TOPO_DIR"
sudo containerlab destroy
sudo containerlab deploy --reconfigure
```

Use another directory if your topology is not under `1_multi_vendor_router` (the path in `/etc/containerlab/last-topology` is the one the workshop records after a successful deploy).

### Refresh `containerlab-resume` on an older image

New workshop images install a resume helper that runs **`containerlab destroy`** (ignored if nothing exists) **before** `containerlab deploy --reconfigure` on boot. If your VM still has the old helper (deploy only), either:

- **Re-run setup** from a current copy of the repo (overwrites the script):

  ```bash
  curl -fsSL https://github.com/rhpds/zt-network-automation-workshop/archive/refs/heads/main.tar.gz | tar xz -C /tmp
  sudo bash /tmp/zt-network-automation-workshop-main/setup-automation/setup-containerlab.sh
  ```

- **Or** replace `/usr/local/bin/containerlab-resume` manually so it matches [setup-containerlab.sh](https://github.com/rhpds/zt-network-automation-workshop/blob/main/setup-automation/setup-containerlab.sh) (`install_clab_resume_service` heredoc).

---

## 4. See what is running (build inventory hints)

### Inspect (text)

```bash
cd ~/1_multi_vendor_router
sudo containerlab inspect
```

Read the output for:

- **Container/node names** (often match Ansible host names like `rtr1`, `rtr2`, …).
- **Management addresses** — how **you** reach the node from the containerlab host or from outside.
- **Kind** (e.g. `ios`, `ceos`, `vrnetlab`) — tells you which automation plugins to use later.

### Inspect (JSON, if supported)

```bash
sudo containerlab inspect --format json
```

Easier to parse or share in a ticket. If your `containerlab` version does not support `--format json`, use plain `inspect`.

### Topology graph (optional)

```bash
sudo containerlab graph
```

Follow any printed URL to open a browser graph (if enabled in your environment).

---

## 5. SSH / connect to a node

Exact command depends on how the topology defines **mgmt** access. Common patterns:

```bash
# Example only — replace with name from `inspect`
ssh admin@<mgmt-ip-or-name-from-inspect>
```

Credentials are usually defined in the topology or lab guide (often **admin** / a documented password). Use whatever your lab documentation says.

From **outside** the cluster (e.g. from your laptop or from the **control** VM), devices are often reached via a **LoadBalancer** or **FIP** with **different ports per router** (e.g. 2222, 2223, …) — that mapping comes from your **cloud `instances.yaml` / LB**, not from Containerlab alone. Use `inspect` **plus** your platform’s published **external** ports to build Ansible inventory.

---

## 6. Tear the lab down

From the same directory you deployed from:

```bash
cd ~/1_multi_vendor_router
sudo containerlab destroy
```

If you used `-t` to deploy, use the same file:

```bash
sudo containerlab destroy -t ./routers.clab.yml
```

---

## 7. What to write down for inventory (for Ansible / AAP later)

While testing manually, capture:

| Item | Why it matters |
|------|----------------|
| **External IP** (FIP / LB) in front of lab SSH | Same host, different **ports** per router in many RHDP labs. |
| **Port per device** (2222, 2223, …) | Matches `config/instances.yaml` service ports when using LB. |
| **User / password** (or key) | `ansible_user`, `ansible_password`, or vault. |
| **`ansible_network_os` / connection** | e.g. `network_cli` + `cisco.ios.ios`, `arista.eos.eos`, `netconf` for Junos. |
| **Names from `inspect`** | Align with inventory host names (`rtr1`, …). |

You can paste **sanitized** `containerlab inspect` (or JSON) into a note when working through inventory with someone else.

---

## 8. Quick troubleshooting

| Issue | What to try |
|-------|-------------|
| `permission denied` talking to Docker/Podman | Run with **`sudo`** or add user to `docker`/`podman` group (image-dependent). |
| `deploy` fails on bind / bridge | Another topology still running — **`destroy`** first, or fix conflicts in `.clab.yml`. |
| Cannot SSH to router | Check **`inspect`** mgmt IP, lab credentials, and whether you must use **external LB IP:port** instead. |
| Wrong topology file | `ls *.yml` in the lab folder and pass **`-t`** explicitly. |
| **`docker logs`** ends with **`QemuBroken`** / **`Unable to connect to qemu monitor`** (many retries) | Scroll to the **start** of the same log for **`failed to set MSR`** — the monitor errors are a **follow-on** after QEMU crashed. Same fix path as the MSR row above. |

[[qemu-msr-troubleshooting]]
### QEMU / KVM: `failed to set MSR` (Arista vEOS container exits)

**Symptoms:** `ssh rtr2` (or `172.20.20.20`) → **Connection refused**. `docker logs clab-routers-rtr2` shows lines like:

```
qemu-system-x86_64: error: failed to set MSR 0x345 to 0x2000
kvm_buf_set_msrs: Assertion `ret == cpu->kvm_msr_buf->nmsrs' failed.
```

The vrnetlab image starts QEMU with **`-enable-kvm`** and **`-cpu host`** (often **`host,level=9`** in logs). On some **nested** KVM setups (VM inside OpenShift/KubeVirt, or certain cloud metal), passing through **host** CPU MSRs fails and QEMU aborts — so **no SSH listener** ever comes up.

**Reading the logs:** The fatal lines (`failed to set MSR`, `kvm_buf_set_msrs`, STDERR from `qemu-system-x86_64`) usually appear **at the top** of `docker logs` right after launch. The long run of **`Unable to connect to qemu monitor (port 4000)`** is **not** a separate bug — vrnetlab keeps retrying because **QEMU never stayed running**, so nothing is listening on the monitor port. The traceback ends with **`vrnetlab.QemuBroken`**. In **`containerlab inspect`**, expect both **Arista** nodes (**rtr2**, **rtr4**) as **`exited`** with **N/A** mgmt IP while Cisco/Juniper may still show **running** (they use a different QEMU/CPU path).

**Collect evidence (on the containerlab VM):**

```bash
# Confirm the container is restarting or unhealthy
sudo docker ps -a --filter name=rtr2
sudo docker logs clab-routers-rtr2 2>&1 | tail -80

# Host KVM and kernel
ls -la /dev/kvm
lsmod | grep kvm
uname -r

# Recent KVM / QEMU messages from the host
sudo dmesg -T | tail -50
```

**What usually fixes it (OpenShift Virtualization / platform, not students):** The **vendor vEOS container image is used verbatim**; when the **same** image works on other clusters, treat this as **nested KVM / VMI CPU / worker** behavior on **this** cluster—not something students fix by editing the router image. Platform teams typically align **KubeVirt VM CPU mode**, **nested virt** on workers, and **scheduling** with a known-good site; worker **kernel/firmware** updates can also change MSR handling. See [wilson.md](wilson.md) for a concise admin brief, log attachments under `wilson/`, and an escalation one-liner.

**What students can try:** redeploy after a clean **`containerlab destroy`** (rules out stale state). If logs still show **MSR** errors, escalate to whoever owns the **OpenShift cluster / KubeVirt VM** for the **containerlab** guest (attach `docker logs`, `containerlab inspect`, and VMI YAML as in `wilson.md`) — this is not an Ansible or workshop inventory bug.

---

## 9. Hooking up Ansible Automation Platform on another VM (e.g. **control**)

Your deploy output shows addresses like **`172.20.20.10`** for **rtr1**, etc. Those live on a **Docker bridge** on the **containerlab VM only** (`172.20.20.0/24`). They are **not** automatically reachable from a different VM (your **Automation Platform controller / execution** host) unless something in the platform forwards or routes traffic there.

So “hooking up” AAP is really: **give the execution environment a network path to each device’s SSH (or NETCONF) service**, then **point Controller inventory at that path**.

### Pattern A-alt: **Same VLAN / no LB proxy (direct to Clab mgmt IPs)**

If **control** and **containerlab** share a **layer-2 VLAN** (or any routed path where control can reach the containerlab VM’s IP on that network), you often **do not** need to hairpin through a LoadBalancer. You still need a **layer-3 path into `172.20.20.0/24`**, because that subnet is the **Docker bridge on the containerlab host**, not the VLAN itself.

Typical setup:

1. **On control**, add a route so traffic to the lab routers goes **via the containerlab VM** (use that VM’s **IP on the shared VLAN**, not its loopback):

   ```bash
   # Example only — replace CLAB_VLAN_IP with containerlab’s address on your shared network
   sudo ip route add 172.20.20.0/24 via <CLAB_VLAN_IP>
   ```

2. **On containerlab**, **IP forwarding** must be on and **firewall / FORWARD** rules must allow VLAN ↔ Docker bridge (Docker and Containerlab usually add a lot of this; if `ping`/`nc` from control fails, check `sysctl net.ipv4.ip_forward` and `nft`/`iptables` FORWARD).

3. **Inventory on AAP** can then use the **mgmt IPs from `containerlab inspect`** (e.g. **`172.20.20.10`** for rtr1) as **`ansible_host`**, with **normal SSH port `22`** (and NETCONF **830** for Junos if applicable)—**unless** your topology publishes different ports.

4. **Verify from control** before touching Controller:

   ```bash
   ping -c2 <CLAB_VLAN_IP>          # L3 to the hypervisor
   nc -vz 172.20.20.10 22           # SSH to rtr1 mgmt (after route + forwarding work)
   ```

If **`nc` to `172.20.20.x` fails** but ping to containerlab works, the missing piece is almost always **routing** (no static route on control) or **forwarding/filtering** on the containerlab host—not “wrong VLAN.”

**Optional:** add the same static route via **cloud-init** on **control** or a small **setup** playbook so it survives reboot (until you replace it with DHCP hooks or platform automation).

### Pattern A (typical in RHDP / this workshop): **LoadBalancer ports**

In `config/instances.yaml`, the **containerlab** VM has a **LoadBalancer** service (**containerlab-fip**) exposing **2222, 2223, …** on a **single front IP** (or hostname). The platform maps each port to the right **published** SSH port inside the lab (one port per router / service).

From **control**, a job runs in an **execution environment** that opens **TCP to that IP**:

- Same **`ansible_host`** for every router (the LB / external IP or DNS your lab provides).
- Different **`ansible_port`** per device (e.g. **2222** → rtr1, **2223** → rtr2, … — confirm mapping with your lab doc or `kubectl`/OpenShift route details).

That is how **AAP on control** talks to **routers inside Containerlab** without needing direct L2/L3 access to **`172.20.20.0/24`**.

**Inventory shape (conceptual):**

```yaml
rtr1:
  ansible_host: "<LB-or-FIP-DNS>"
  ansible_port: 2222
  ansible_user: admin
  ansible_connection: network_cli
  ansible_network_os: cisco.ios.ios
# rtr2: same ansible_host, ansible_port 2223, eos, etc.
```

Use the real **external** hostname/IP your sandbox prints in **user-info** / Showroom, not `172.20.20.x`.

### Pattern B: **SSH only from the containerlab host**

Containerlab added **`/etc/ssh/ssh_config.d/clab-routers.conf`** and **hosts** entries so that **on the containerlab VM** you can often `ssh` to short names. That helps **you** and **ansible-playbook run from containerlab**; it does **not** by itself make those names work from **control** unless you duplicate that SSH config there or use **ProxyJump** through the containerlab host (possible but less common in workshop automation).

### Pattern C: **Same idea as A-alt, generic wording**

Any design where **control** reaches **`172.20.20.0/24` through the containerlab VM** (static route + forwarding, or a platform-provided route) is the same as **Pattern A-alt**. The LoadBalancer path is only required when **no** such route exists from the execution environment to the Clab Docker network.

### What to verify from **control**

1. **`ping` / `curl`** is not always meaningful for SSH; use **`ssh -p PORT user@LB_IP`** or **`nc -vz LB_IP PORT`** for each published port.
2. In **Controller**, create a small **inventory + machine credential + ad-hoc ping** (or a one-task playbook) against **one** router using **LB IP + port**.
3. Wait until Containerlab shows **health: running** (not only **starting**) before expecting stable automation.

---

## 10. Control ↔ containerlab: SSH / ping “does not work” in the sandbox

If both VMs are up but **ping shows 100% loss** and **SSH hangs**:

1. **ICMP is often blocked** by cluster **NetworkPolicy** (or equivalent). **Do not use ping** as proof that TCP is dead—test with **`nc -vz <host> 22`** or **`ssh -vvv`** instead.

2. **`config/firewall.yaml`** in this repo originally allowed only **router-facing** ports (2222–2228, etc.), **not TCP 22**. Without **egress 22** and **ingress 22**, **SSH between `control` and `containerlab` can be dropped** even when DNS resolves. The repo now includes **TCP 22** in ingress/egress; **redeploy** the lab (or have RHDP apply the same rules) so policies update.

3. **DNS `containerlab....svc.cluster.local`** resolves to a **Kubernetes Service ClusterIP** (e.g. `10.130.x.x`). SSH only works if that Service **forwards TCP 22** to the VM. If it still fails after a firewall refresh, try the **VM pod IP** from OpenShift/KubeVirt (`VirtualMachineInstance` status) instead of the Service hostname.

4. **`secondary` on `control`:** check **`ip addr show eth1`**. If **eth1 has no IPv4**, the **secondary** NAD is not giving you a data address yet—**same-VLAN routing** between VMs is not in place on that NIC until it does.

5. **Users:** `control` is often **`rhel`**; **containerlab** is often **`lab-user`**. Example: `ssh lab-user@<containerlab-ip-or-dns>`.

---

## Related files in this repo

- **`lab-automation/README.md`** — same topology via **Ansible**, plus Controller bootstrap and how that ties to inventory.
- **`config/instances.yaml`** — VM **containerlab** and **LoadBalancer** ports exposed to students (pairs with external IP for router SSH).
- **`config/firewall.yaml`** — allowed TCP ports (includes **22** for inter-VM SSH when the environment applies this file).
