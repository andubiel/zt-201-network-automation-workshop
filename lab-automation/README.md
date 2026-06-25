# Lab automation: containerlab topology + Automation controller

To run **Containerlab only** (CLI on the VM, no Ansible), see [../README-containerlab.md](../README-containerlab.md).

This folder contains Ansible playbooks to:

1. **Deploy** the `1_multi_vendor_router` Containerlab topology on the **containerlab** VM (same idea as [network_workshop_containerlab](https://gitlab.com/redhatautomation/network_workshop_containerlab), with fixes).
2. **Bootstrap** Ansible Automation Platform (Controller) on the **control** VM: wait for the API, optionally use `ansible.platform.token` when Gateway env vars are set, then create/update a **Default** organization and a **git SCM project** via **`ansible.controller`**.
3. **Optionally** run **`gather_facts`** against the virtual routers (Cisco / Arista / Junos) once you know how traffic reaches them from Ansible.
4. **Pre-provision Controller** with a **job template** that turns on **`1_multi_vendor_router`** (see next section).

Use this README to **test manually** before you rely on `setup-automation/setup-control.sh` at boot.

---

## Controller job template: deploy Containerlab topology

### How this is supposed to work (what you described)

1. **Automation controller** (on **control**) runs a **job template**.
2. The job uses an **execution environment** that runs on the **control side** (VM or pod colocated with your lab—still “from control” in practice).
3. Ansible opens an **SSH session to the containerlab host** (inventory: group **`containerlab`**, host like **`containerlab-vm`** → `ansible_host: containerlab`).
4. The playbook **`1_multi_vendor_router_up.yml`** runs **on containerlab**: `containerlab deploy --reconfigure` with **`become`** (sudo).

That is **`workshop_jt_mode: remote`** (now the **default** in `inventory/group_vars/all.yml`). You still attach a **machine credential** in Controller for SSH (and sudo if needed)—even if the password is empty because keys are preloaded into that credential or passwordless sudo is configured.

---

`playbooks/aap_bootstrap.yml` (via `include_tasks: tasks/controller_bootstrap_objects.yml`) creates:

- An initial **SCM project sync** for the workshop git repo (wait up to 20 minutes).
- A **job template** named **`Deploy — 1_multi_vendor_router`** (override with `workshop_jt_deploy_topology_name`).

### Mode `remote` (default) — what you described

`workshop_jt_mode: remote` in `inventory/group_vars/all.yml` (this is the default).

Controller creates:

- Inventory **`Network workshop lab`**, group **`containerlab`**, host **`containerlab-vm`** with `ansible_host: containerlab`, `ansible_user: lab-user`.
- Machine credential **`Workshop containerlab SSH`** (password / private key / become via vars or env `WORKSHOP_CONTAINERLAB_SSH_PASSWORD`, `WORKSHOP_CONTAINERLAB_BECOME_PASSWORD`).
- Job template **`Deploy — 1_multi_vendor_router`** → playbook **`lab-automation/playbooks/1_multi_vendor_router_up.yml`** with **`hosts: containerlab`** and **`become: true`** on that host.

So: **job runs from the control-side execution environment → SSH to containerlab → `containerlab deploy` there.**

After `aap_bootstrap` and a successful project sync: **Templates** → launch that job template.

### Mode `local` — optional (no machine credential in AWX)

`workshop_jt_mode: local` uses inventory **`localhost`** only and playbook **`1_multi_vendor_router_up_local.yml`**, which runs **`ssh lab-user@containerlab …`** inside a task. The EE user still needs key-based SSH to containerlab; use **remote** unless you have a reason to avoid storing a machine credential.

---

## What you need to decide about inventory

Inventory is the part that will vary most per environment. Today the repo ships:

| Group | Purpose | Defaults you may need to change |
|-------|---------|----------------------------------|
| **containerlab** | SSH into the VM where `containerlab` CLI runs | `ansible_host: containerlab`, `ansible_user: lab-user`. Your cluster might use an FQDN, IP, or jump host—edit `inventory/lab.yml` or override with `-e ansible_host=...` / host vars. |
| **aap_controller** | `localhost` on the **control** node | Controller API base URL defaults to `https://127.0.0.1` in `inventory/group_vars/all.yml`. |
| **routers** | Direct automation to **rtr1–rtr4** | Each host uses **different ports** (2222, 2223, …) on the **same front IP** (LoadBalancer / FIP in front of containerlab). Set **`containerlab_fip`** when you run `gather_facts.yml`. |

**SSH from control → containerlab:** If DNS/hosts do not resolve `containerlab`, set `ansible_host` (and `ansible_ssh_private_key_file` / `ansible_ssh_pass` if needed) for `network_workshop` in `inventory/lab.yml` or via `-e`.

**Routers:** Until you know the external IP (or DNS) that fronts ports **2222–2228**, skip `gather_facts.yml` or pass `-e containerlab_fip=<that IP>`.

---

## Prerequisites

- Run these playbooks from the **control** VM (or from your laptop with network access to **control** and **containerlab** as you define in inventory).
- On the machine that runs Ansible:

  ```bash
  cd lab-automation
  ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections
  ```

- **Controller API password:** export **`CONTROLLER_PASSWORD`** (admin or another user with rights to create organizations/projects) before `aap_bootstrap` / `site.yml`. If unset, the bootstrap play ends early and **skips** Controller tasks (containerlab deploy still runs in `site.yml`).

- **Optional Gateway / `ansible.platform.token`:** set `use_aap_gateway_token: true` in `group_vars` (or `-e`) and env vars `GATEWAY_HOSTNAME`, `GATEWAY_USERNAME`, `GATEWAY_PASSWORD`. Only needed if you use that flow; classic Controller-only labs can ignore it.

---

## Test sequence (recommended)

### 1. Only Containerlab (no Controller API)

```bash
cd lab-automation
ansible-playbook -i inventory/lab.yml playbooks/1_multi_vendor_router_up.yml
```

- Runs `containerlab deploy --reconfigure` under `/home/lab-user/1_multi_vendor_router` on the **containerlab** host (override with `-e clab_topology_dir=...` if needed).
- Waits **`clab_deploy_wait_seconds`** (default **120**; was 300 in the original GitLab playbook).
- Prints full `containerlab inspect` output (no fragile fixed line numbers).

Tear down:

```bash
ansible-playbook -i inventory/lab.yml playbooks/1_multi_vendor_router_down.yml
```

### 2. Only Automation controller bootstrap

On the **control** node, after Controller is up:

```bash
export CONTROLLER_PASSWORD='your-admin-password'
cd lab-automation
ansible-playbook -i inventory/lab.yml playbooks/aap_bootstrap.yml
```

This will:

- Poll **`/api/v2/ping/`** until the API responds.
- Optionally create a **Gateway token** if `use_aap_gateway_token` and Gateway env are set.
- Ensure **Default** organization exists.
- Ensure SCM project **`Network automation workshop`** (name configurable in `group_vars/all.yml`) points at **`workshop_git_url`** / **`workshop_scm_branch`**.

Adjust **`controller_endpoint`**, **`controller_username`**, **`workshop_git_url`**, etc. in `inventory/group_vars/all.yml` or with `-e`.

### 3. Full sequence (what `site.yml` does)

```bash
export CONTROLLER_PASSWORD='your-admin-password'   # optional but needed for step 2 inside site
cd lab-automation
ansible-playbook -i inventory/lab.yml playbooks/site.yml
```

Order: **containerlab up** → **aap_bootstrap**.

### 4. Check automation to the *routers* (optional)

After topology is up and you know the **IP (or name)** that exposes **2222, 2223, …** to the lab:

```bash
cd lab-automation
ansible-playbook -i inventory/lab.yml playbooks/gather_facts.yml -e containerlab_fip=203.0.113.50
```

Replace with your real FIP/LB IP. Requires **cisco.ios**, **arista.eos**, **junipernetworks.junos** (and **ansible.netcommon** where needed) in the environment running the playbook—typically an execution environment or control node with those collections installed.

**This is not the same as “AAP talking to routers.”** This playbook runs **from your Ansible controller (CLI)** using the **routers** inventory group. To have **Job Templates in AAP** hit those devices, you will add **inventories, credentials, and job templates** in Controller (next step after SCM project sync)—often using the same host/port/password ideas as `inventory/lab.yml` under **routers**.

---

## Boot-time integration (reference)

`setup-automation/setup-control.sh` tries to run:

```text
lab-automation/playbooks/site.yml
```

if it finds `lab-automation/` under:

- `/home/rhel/zt-network-automation-workshop`
- `/home/rhel/workshop`
- `$WORKSHOP_REPO_ROOT`

Logs: **`/tmp/lab-automation-site.log`**, **`/tmp/lab-automation-collections.log`**.  
Env passed through: **`CONTROLLER_PASSWORD`**, **`GATEWAY_HOSTNAME`**, **`GATEWAY_USERNAME`**, **`GATEWAY_PASSWORD`**.

For a first test, run the playbooks **manually** (sections above) until inventory and passwords are correct; then rely on boot integration.

---

## Troubleshooting

| Symptom | Things to check |
|--------|------------------|
| SSH to containerlab fails | `ansible_host`, user `lab-user`, key/password, firewall from control to containerlab. |
| `containerlab deploy` fails | On containerlab VM: `sudo`, Podman/Docker, path `clab_topology_dir`, contents of `routers.clab.yml`. |
| Controller tasks skipped | `CONTROLLER_PASSWORD` unset; set it and re-run `aap_bootstrap.yml`. |
| `uri` ping never succeeds | `controller_endpoint` (https, correct hostname/IP), TLS (`controller_verify_ssl`), clock, Controller not finished installing. |
| `ansible.controller.*` errors | Collection version vs Controller version; user role must create org/project. |
| `gather_facts` fails | `containerlab_fip` wrong; ports blocked; device credentials; collections missing. |

---

## Files quick reference

| File | Role |
|------|------|
| `playbooks/1_multi_vendor_router_up.yml` | Deploy topology on containerlab |
| `playbooks/1_multi_vendor_router_down.yml` | Destroy topology |
| `playbooks/aap_bootstrap.yml` | Controller API: ping, optional platform token, org + project |
| `playbooks/site.yml` | Up + bootstrap |
| `playbooks/gather_facts.yml` | Optional router reachability (needs `containerlab_fip`) |
| `inventory/lab.yml` | Host groups—**edit when you know real names/IPs** |
| `inventory/group_vars/all.yml` | Controller URL, topology path, git URL, feature flags |

When your inventory story is clear, you can replace or extend `inventory/lab.yml` with generated inventory (dynamic inventory plugin, `add_host` play, or RHDP-injected vars) without changing the playbooks, as long as group names **`containerlab`**, **`aap_controller`**, and **`routers`** (for gather_facts) remain consistent—or adjust `hosts:` in each playbook to match your groups.
