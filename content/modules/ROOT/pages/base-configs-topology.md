# Base Configuration — Spine-Leaf Fabric Foundation

## Fabric Topology

```mermaid
graph TD
    subgraph Spines [<b>Spine Layer</b>]
        S1["<b>spine1</b> — Arista EOS<br>Lo0: 10.0.255.101/32"]
        S2["<b>spine2</b> — Arista EOS<br>Lo0: 10.0.255.102/32"]
    end

    subgraph Leafs [<b>Leaf Layer</b>]
        L1["<b>leaf1</b> — Arista EOS<br>Lo0: 10.0.250.11/32"]
        L2["<b>leaf2</b> — Arista EOS<br>Lo0: 10.0.250.12/32"]
        L3["<b>leaf3</b> — Cisco NX-OS<br>Lo0: 10.0.250.13/32"]
        L4["<b>leaf4</b> — Cisco NX-OS<br>Lo0: 10.0.250.14/32"]
    end

    subgraph Hosts [<b>Hosts</b>]
        H1["host1<br>VLAN 50"]
        H2["host2<br>VLAN 50"]
        H3["host3<br>VLAN 40"]
        H4["host4<br>VLAN 60"]
    end

    S1 ---|"Eth1 ↔ Eth11<br>10.0.1.0/31"| L1
    S1 ---|"Eth2 ↔ Eth11<br>10.0.1.2/31"| L2
    S1 ---|"Eth3 ↔ Eth1/11<br>10.0.1.4/31"| L3
    S1 ---|"Eth4 ↔ Eth1/11<br>10.0.1.6/31"| L4

    S2 ---|"Eth1 ↔ Eth12<br>10.0.20.0/31"| L1
    S2 ---|"Eth2 ↔ Eth12<br>10.0.20.2/31"| L2
    S2 ---|"Eth3 ↔ Eth1/12<br>10.0.20.4/31"| L3
    S2 ---|"Eth4 ↔ Eth1/12<br>10.0.20.6/31"| L4

    L1 ---|"Eth7"| H1
    L2 ---|"Eth7"| H2
    L3 ---|"Eth1/7"| H3
    L4 ---|"Eth1/7"| H4

    classDef spine fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef leaf fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef host fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class S1,S2 spine
    class L1,L2,L3,L4 leaf
    class H1,H2,H3,H4 host
```

## VLANs (Configured on All Leafs)

| VLAN | Name           | Purpose                              |
|------|----------------|--------------------------------------|
| 40   | Data_VLAN_40   | Host data (leaf1, leaf3)             |
| 50   | Data_VLAN_50   | Host data (leaf2)                    |
| 60   | Data_VLAN_60   | Host data (leaf4)                    |
| 101  | L3VNI_Transit  | VXLAN L3 VNI transit (used by overlay) |

## Workflow: Backup → Deploy → Test

```mermaid
flowchart LR
    subgraph Workflow [<b>1-4 Base Configs Workflow</b>]
        B["1. Backup<br>Snapshot to Git branch"]
        D["2. Deploy<br>Push base config<br>via resource modules"]
        T["3. Test<br>Ping, interface,<br>hostname checks"]
        R{"Tests<br>Pass?"}
        RESTORE["Restore<br>from Git branch"]
        DONE["Ready for<br>Underlay"]
    end

    B --> D --> T --> R
    R -->|Yes| DONE
    R -->|No| RESTORE --> D

    classDef action fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef decision fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef restore fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef done fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    class B,D,T action
    class R decision
    class RESTORE restore
    class DONE done
```

## Base Fabric Role — Dispatch Pattern

```mermaid
flowchart TD
    PLAY["deploy_fabric.yml"] --> ROLE["roles/base_fabric/main.yml"]
    ROLE -->|"ansible_network_os = arista.eos.eos"| EOS["eos.yml"]
    ROLE -->|"ansible_network_os = cisco.nxos.nxos"| NXOS["nxos.yml"]

    EOS --> E1["1. Set Hostname<br><code>eos_hostname</code>"]
    EOS --> E2["2. Configure VLANs<br><code>eos_vlans</code>"]
    EOS --> E3["3. Enable Interfaces<br><code>eos_interfaces</code>"]
    EOS --> E4["4. L2 Switchports<br><code>eos_l2_interfaces</code>"]
    EOS --> E5["5. L3 IP Addresses<br><code>eos_l3_interfaces</code>"]
    EOS --> E6["6. Enable IP Routing"]

    NXOS --> N1["1. Set Hostname<br><code>nxos_hostname</code>"]
    NXOS --> N2["2. Configure VLANs<br><code>nxos_vlans</code>"]
    NXOS --> N3["3. Enable Interfaces<br><code>nxos_interfaces</code>"]
    NXOS --> N4["4. L2 Switchports<br><code>nxos_l2_interfaces</code>"]
    NXOS --> N5["5. L3 IP Addresses<br><code>nxos_l3_interfaces</code>"]

    classDef play fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef role fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef vendor fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef task fill:#17becf,stroke:#333,stroke-width:1px,color:#000
    class PLAY play
    class ROLE role
    class EOS,NXOS vendor
    class E1,E2,E3,E4,E5,E6,N1,N2,N3,N4,N5 task
```

## Point-to-Point Link Addressing

### Spine1 Links (10.0.1.x/31)

| Spine1 Interface | Spine1 IP  | Leaf Interface | Leaf IP   | Leaf   |
|------------------|-----------|----------------|-----------|--------|
| Ethernet1        | 10.0.1.0  | Eth11          | 10.0.1.1  | leaf1  |
| Ethernet2        | 10.0.1.2  | Eth11          | 10.0.1.3  | leaf2  |
| Ethernet3        | 10.0.1.4  | Eth1/11        | 10.0.1.5  | leaf3  |
| Ethernet4        | 10.0.1.6  | Eth1/11        | 10.0.1.7  | leaf4  |

### Spine2 Links (10.0.20.x/31)

| Spine2 Interface | Spine2 IP  | Leaf Interface | Leaf IP    | Leaf   |
|------------------|-----------|----------------|------------|--------|
| Ethernet1        | 10.0.20.0 | Eth12          | 10.0.20.1  | leaf1  |
| Ethernet2        | 10.0.20.2 | Eth12          | 10.0.20.3  | leaf2  |
| Ethernet3        | 10.0.20.4 | Eth1/12        | 10.0.20.5  | leaf3  |
| Ethernet4        | 10.0.20.6 | Eth1/12        | 10.0.20.7  | leaf4  |
