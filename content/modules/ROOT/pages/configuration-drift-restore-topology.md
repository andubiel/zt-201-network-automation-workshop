# Configuration Drift and Restore — Intended Config Diff

## Intended Config Diff — How It Works

```mermaid
flowchart TD
    OP["<b>Operator</b><br>Launches Job Template<br>1-2-Backups_as_Code-Git-Intent"]
    SURVEY["<b>Survey Prompt</b><br>Select branch name<br>e.g. vxlan_configs"]

    OP --> SURVEY

    subgraph Part1 ["<b>Part 1 — Clone Intended Config</b>"]
        GITEA["<b>Gitea</b><br>Git repository<br>Branch: vxlan_configs"]
        CLONE["<b>ansible.scm.git_retrieve</b><br>Clone branch to /tmp/<br>run_once: true"]
        FILES["<b>Intended Config Files</b><br>/tmp/.../hostname/hostname.cfg"]

        GITEA --> CLONE --> FILES
    end

    subgraph Part2 ["<b>Part 2 — Diff Against Running Config</b>"]
        direction TB
        subgraph EOS_DIFF ["<b>EOS Devices</b>"]
            EOS_RUN["Running config<br>via arista.eos.eos_config"]
            EOS_INT["Intended config<br>from Git file"]
            EOS_CMP["diff_against: intended<br>(read-only)"]
            EOS_RUN --> EOS_CMP
            EOS_INT --> EOS_CMP
        end
        subgraph NXOS_DIFF ["<b>NX-OS Devices</b>"]
            NXOS_RUN["Running config<br>via cisco.nxos.config"]
            NXOS_INT["Intended config<br>from Git file"]
            NXOS_CMP["diff_against: intended<br>(read-only)"]
            NXOS_RUN --> NXOS_CMP
            NXOS_INT --> NXOS_CMP
        end
    end

    SURVEY --> Part1
    FILES --> EOS_INT
    FILES --> NXOS_INT

    EOS_CMP --> REPORT["<b>Diff Report</b><br>Lines added / removed / changed<br>per device"]
    NXOS_CMP --> REPORT

    classDef operator fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef git fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef ansible fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef file fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef report fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    class OP,SURVEY operator
    class GITEA git
    class CLONE,EOS_CMP,NXOS_CMP ansible
    class FILES,EOS_INT,NXOS_INT,EOS_RUN,NXOS_RUN file
    class REPORT report
```

## Drift Detection — SNMP Example

```mermaid
flowchart LR
    subgraph GIT ["<b>Intended Config (Git)</b><br>vxlan_configs branch"]
        G_CFG["hostname spine1<br>spanning-tree mode mstp<br>...<br><i>No SNMP line</i>"]
    end

    subgraph DEVICE ["<b>Running Config (Device)</b>"]
        D_CFG["hostname spine1<br><b>snmp-server community vxlan ro</b><br>spanning-tree mode mstp<br>..."]
    end

    subgraph DIFF ["<b>Diff Output</b>"]
        D_OUT["--- before (running)<br>+++ after (intended)<br><br> hostname spine1<br><b>- snmp-server community vxlan ro</b><br> spanning-tree mode mstp"]
    end

    GIT --> DIFF
    DEVICE --> DIFF

    classDef git fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef device fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef diff fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    class G_CFG git
    class D_CFG device
    class D_OUT diff
```

## Drift Per Device — Lab Results

```mermaid
flowchart TD
    subgraph Fabric ["<b>All 6 Devices — Drift Detected</b>"]
        direction LR
        subgraph EOS ["<b>EOS Devices</b>"]
            S1["spine1<br>snmp-server community<br>vxlan ro"]
            S2["spine2<br>snmp-server community<br>vxlan ro"]
            L1["leaf1<br>snmp-server community<br>vxlan ro"]
            L2["leaf2<br>snmp-server community<br>vxlan ro"]
        end
        subgraph NXOS ["<b>NX-OS Devices</b>"]
            L3["leaf3<br>snmp-server community<br>vxlan group network-operator"]
            L4["leaf4<br>snmp-server community<br>vxlan group network-operator"]
        end
    end

    CAUSE["<b>Root Cause</b><br>1-7 Tuning for Scale SNMP playbook<br>added community string to all devices<br>but never committed to vxlan_configs branch"]

    Fabric --> CAUSE

    classDef eos fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef nxos fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef cause fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class S1,S2,L1,L2 eos
    class L3,L4 nxos
    class CAUSE cause
```

## Remediation Options

```mermaid
flowchart TD
    DRIFT["<b>Drift Detected</b><br>Running config ≠ Intended config"]

    DRIFT --> OPT1
    DRIFT --> OPT2

    subgraph OPT1 ["<b>Option 1 — Restore to Intended</b>"]
        R1["Run restore workflow<br>1-2-Backups_as_Code-Restore"]
        R2["Select branch: vxlan_configs"]
        R3["Devices rolled back<br>SNMP community removed"]
        R1 --> R2 --> R3
    end

    subgraph OPT2 ["<b>Option 2 — Accept Current State</b>"]
        A1["Run backup workflow<br>1-2-Backups_as_Code-Backup-GIT"]
        A2["Commit to vxlan_configs<br>or new branch"]
        A3["Git updated<br>SNMP becomes intended"]
        A1 --> A2 --> A3
    end

    classDef drift fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef restore fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef accept fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    class DRIFT drift
    class R1,R2,R3 restore
    class A1,A2,A3 accept
```

## Full Backup-Restore Lifecycle

```mermaid
flowchart LR
    subgraph Lifecycle ["<b>Backups as Code — Configuration Lifecycle</b>"]
        BACKUP["<b>1. Backup</b><br>Capture running config<br>to named Git branch"]
        DEPLOY["<b>2. Deploy</b><br>Push config changes<br>via Ansible"]
        TEST["<b>3. Test</b><br>Validate with<br>automated checks"]
        DETECT["<b>4. Detect Drift</b><br>diff_against: intended<br>Compare Git vs running"]
        DECIDE{"Drift<br>found?"}
        RESTORE["<b>5a. Restore</b><br>Roll back to<br>any Git branch"]
        ACCEPT["<b>5b. Accept</b><br>Backup current state<br>as new baseline"]
        OK["Config matches<br>intended state"]
    end

    BACKUP --> DEPLOY --> TEST --> DETECT --> DECIDE
    DECIDE -->|"Yes"| RESTORE
    DECIDE -->|"Yes"| ACCEPT
    DECIDE -->|"No"| OK
    RESTORE --> TEST
    ACCEPT --> OK

    classDef action fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef detect fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef decision fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef restore fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef accept fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef ok fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    class BACKUP,DEPLOY,TEST action
    class DETECT detect
    class DECIDE decision
    class RESTORE restore
    class ACCEPT accept
    class OK ok
```

## Git Branch Timeline

```mermaid
gitGraph
    commit id: "initial_config" tag: "Baseline"
    branch vxlan_configs
    commit id: "base_configs" type: HIGHLIGHT
    commit id: "underlay_configs"
    commit id: "overlay_configs"
    branch final_configs
    commit id: "final + SNMP" type: HIGHLIGHT tag: "Current"
```

## Restore Scenarios — Lab Walkthrough

```mermaid
flowchart TD
    subgraph Current ["<b>Current State</b><br>Final configs + SNMP"]
        C1["All devices have<br>full EVPN VXLAN config<br>+ SNMP community"]
    end

    Current --> R1
    Current --> R2

    subgraph R1 ["<b>Restore → initial_config</b>"]
        R1_RESULT["All EVPN VXLAN config removed<br>VLANs, loopbacks, OSPF,<br>BGP, VXLAN, SNMP — all gone<br>Devices return to factory baseline"]
    end

    subgraph R2 ["<b>Restore → final_configs</b>"]
        R2_RESULT["Full EVPN VXLAN restored<br>including SNMP community<br>Devices return to completed<br>fabric state"]
    end

    classDef current fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef initial fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef final fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    class C1 current
    class R1_RESULT initial
    class R2_RESULT final
```
