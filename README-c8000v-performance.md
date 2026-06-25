# Cisco C8000v Boot Performance Issue

## Problem

The Cisco C8000v (IOS-XE 17.13.01a) virtual router takes **25-30 minutes** to fully boot in the containerlab topology, compared to **2-3 minutes** for Arista vEOS and Juniper vSRX on the same host. During boot, the router's SSH port is open but rejects all authentication, causing Ansible playbooks and manual SSH attempts to fail with:

```
ssh connection failed: Failed to authenticate public key: Access denied for 'publickey'.
Authentication that can continue: publickey,keyboard-interactive,password
```

This affects both AAP job templates and student CLI exercises from the VS Code terminal.

## Root Cause

**Primary: premature `end` in startup-config.cfg.** The rtr1 startup config on the containerlab image has an extra `end` keyword before the `line vty`, `netconf`, and `restconf` blocks. When vrnetlab replays the config via serial console, `end` drops IOS out of config mode back to enable mode. All subsequent lines (`line vty 0 4`, `netconf detailed-error`, etc.) are interpreted as exec commands, triggering DNS lookups, login prompts, and timeouts that add **7+ minutes** to boot. With the corrected config, boot time drops from ~12 minutes to **~5 minutes**.

**Secondary: single vCPU.** The vrnetlab container image launches QEMU with **`-smp 1`** (single vCPU). The C8000v boot process is CPU-intensive — it generates crypto keys, starts NETCONF/RESTCONF/IOX services, and applies the startup config via serial console. Each operation queues behind the others on a single core.

## Evidence (collected 2026-05-07)

**Host specs:** 12 vCPUs, AMD EPYC 7642 48-Core, 32 GB RAM

**Container resource usage during boot:**

| Container | CPU % | Memory |
|-----------|-------|--------|
| clab-routers-rtr1 (C8000v) | **101.75%** | 4.0 GiB |
| clab-routers-rtr3 (vSRX) | 110.09% | 4.0 GiB |
| clab-routers-rtr2 (vEOS) | 14.33% | 2.0 GiB |
| clab-routers-rtr4 (vEOS) | 15.53% | 2.0 GiB |

**IOS-XE internal load reports** (from `docker logs clab-routers-rtr1`):

```
%PLATFORM-4-ELEMENT_WARNING: RP/0: 5-Minute Load Average value 8.52 exceeds warning level 8.00
%PLATFORM-3-ELEMENT_CRITICAL: RP/0: 5-Minute Load Average value 12.04 exceeds critical level 12.00
```

A load average of 12 on a 1-vCPU VM means 12 processes are waiting for CPU at any given time.

**Config application timing via vrnetlab serial console:**

Individual IOS CLI commands that normally complete in under 1 second were taking **5+ minutes** each:

```
14:04:50 → ip ssh server algorithm mac hmac-sha2-512
14:09:16 → response received                          (4 min 26 sec)

14:09:16 → ip ssh maxstartups 128
14:14:23 → response received                          (5 min 7 sec)
```

The full startup config application took over 20 minutes.

**Host load during this time was only 2.90** — the 12 host CPUs are not saturated. The bottleneck is entirely the single QEMU vCPU.

## Recommended Fix: Topology + Startup Config Changes

The fastest fix (no image rebuild required) is to apply these changes on the containerlab VM at `/home/lab-user/1_multi_vendor_router/`.

### 1. Fix the premature `end` in rtr1 startup config (biggest win — 12 min → 5 min)

The baked-in `/home/lab-user/1_multi_vendor_router/configs/rtr1/startup-config.cfg` has an `end` before the `line vty`, `netconf-yang`, and `restconf` blocks. The `end` drops IOS out of config mode, and vrnetlab then sends the remaining config lines as exec commands, causing DNS lookup timeouts and login prompts.

**Remove the premature `end`** so the config flows correctly. The `end` should only appear once, at the very end of the file after all config blocks:

```
! ... (earlier config) ...
mgcp profile default
!
!
netconf-yang
restconf
!                        ← DO NOT put 'end' here
!
line con 0
 stopbits 1
line aux 0
line vty 0 4
 login local
 length 0
 transport input ssh
line vty 5 20
 login
 length 0
 transport input ssh
!
!
netconf detailed-error
netconf max-sessions 16
!
!
!
!
!
netconf-yang
restconf
end                      ← only 'end' goes here, at the very bottom
```

To push this fix automatically before topology deploy, add an `ansible.builtin.copy` task in the deploy playbook that replaces the startup config before `containerlab deploy --reconfigure`.

### 2. Disable PnP/ZTP in the rtr1 startup config

Add this line to `configs/rtr1/startup-config.cfg` after `no aaa new-model`. The Cisco PnP agent runs a discovery loop at boot when no PnP server exists:

```
no pnp profile pnp-zero-touch
```

### 3. Give the C8000v more CPU and RAM in `routers.clab.yml`

Add `cpu: 4` and `memory: 8192` to the `cisco_c8000v` kind definition, and set `ALREADY_CONFIGURED` to skip vrnetlab's slow serial console config replay:

```yaml
name: routers
topology:
  kinds:
    arista_veos:
      image: registry.gitlab.com/redhatautomation/veos-ee:4.32.0F
    cisco_c8000v:
      image: registry.gitlab.com/redhatautomation/cat8:17.13.01a
      cpu: 4
      memory: 8192
    juniper_vsrx:
      image: registry.gitlab.com/redhatautomation/juniper-ee:23.2R2.21

  nodes:
    rtr1:
      kind: cisco_c8000v
      startup-config: configs/rtr1/startup-config.cfg
      mgmt-ipv4: 172.20.20.10
      env:
        ALREADY_CONFIGURED: "true"
      ports:
        - "2222:22"

    rtr2:
      kind: arista_veos
      startup-config: configs/rtr2/startup-config.cfg
      mgmt-ipv4: 172.20.20.20
      ports:
        - "2223:22"

    rtr3:
      kind: juniper_vsrx
      startup-config: configs/rtr3/startup-config.cfg
      mgmt-ipv4: 172.20.20.30
      ports:
        - "2224:830"
        - "2225:22"

    rtr4:
      kind: arista_veos
      startup-config: configs/rtr4/startup-config.cfg
      mgmt-ipv4: 172.20.20.40
      ports:
        - "2226:22"

  links:
    - endpoints: ["rtr1:eth1", "rtr2:eth1"]
    - endpoints: ["rtr1:eth2", "rtr3:ge-0/0/0"]
    - endpoints: ["rtr4:eth1", "rtr2:eth2"]
```

### 2. Disable PnP/ZTP in the rtr1 startup config

Add this line to `configs/rtr1/startup-config.cfg`. The Cisco PnP agent runs a ~10-minute discovery loop at boot when no PnP server exists, which is wasted time in a lab environment:

```
no pnp profile pnp-zero-touch
```

Place it after the `no aaa new-model` line or near the end of the global config section.

### 3. (Optional) Rebuild the vrnetlab image with `-smp 2`

If the `cpu: 4` topology-level override doesn't propagate into the QEMU `-smp` flag (depends on how the vrnetlab `launch.py` is written), the image itself needs to be rebuilt. Look for `-smp 1` in the QEMU command line inside the container image `registry.gitlab.com/redhatautomation/cat8:17.13.01a`:

```
qemu-system-x86_64 -enable-kvm ... -smp 1 -m 4096 ...
```

Change to:

```
qemu-system-x86_64 -enable-kvm ... -smp 2 -m 4096 ...
```

### Other complementary mitigations

1. **Increase the topology deploy wait time.** The `1_multi_vendor_router_up.yml` playbook waits 120 seconds after `containerlab deploy`. With the current single-vCPU image, this should be **600 seconds** (10 minutes) minimum. This doesn't fix the root cause but prevents students from hitting half-booted routers.

2. **Pre-boot the topology before students access the lab.** Deploy the containerlab topology as part of the provisioning pipeline (e.g., in `setup-containerlab.sh`) rather than as a separate AAP job, and add a health-check gate that waits for all nodes to reach `(healthy)` before marking the lab as ready.

## How to Verify the Fix

After applying the changes, redeploy the topology and time the boot:

```bash
cd /home/lab-user/1_multi_vendor_router
sudo containerlab deploy --reconfigure

# Poll until healthy (should be well under 10 min with cpu: 4 + PnP disabled)
while true; do
  status=$(sudo containerlab inspect 2>/dev/null | grep rtr1 | grep -o '(healthy)')
  if [[ -n "$status" ]]; then
    echo "rtr1 is healthy"
    break
  fi
  echo "Waiting for rtr1..."
  sleep 30
done

# Verify SSH works
sshpass -p 'admin@123' ssh -o StrictHostKeyChecking=no admin@172.20.20.10 "show version"
```
