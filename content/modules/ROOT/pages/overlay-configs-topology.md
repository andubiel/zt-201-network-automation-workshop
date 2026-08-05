# Overlay Configuration — EVPN VXLAN Fabric

## EVPN BGP Overlay Topology

```mermaid
graph TD
    subgraph Spines ["<b>Spine Layer — AS 65000</b>"]
        S1["<b>spine1</b> — Arista EOS<br>Lo0: 10.0.255.101/32<br>EVPN Relay — 4 leaf peers<br>next-hop-unchanged"]
        S2["<b>spine2</b> — Arista EOS<br>Lo0: 10.0.255.102/32<br>EVPN Relay — 4 leaf peers<br>next-hop-unchanged"]
    end

    subgraph Leafs ["<b>Leaf / VTEP Layer — AS 65001</b>"]
        L1["<b>leaf1</b> — Arista EOS<br>Lo0: 10.0.250.11<br>VTEP: Vxlan1<br>allowas-in 3"]
        L2["<b>leaf2</b> — Arista EOS<br>Lo0: 10.0.250.12<br>VTEP: Vxlan1<br>allowas-in 3"]
        L3["<b>leaf3</b> — Cisco NX-OS<br>Lo0: 10.0.250.13<br>VTEP: nve1<br>allowas-in 3"]
        L4["<b>leaf4</b> — Cisco NX-OS<br>Lo0: 10.0.250.14<br>VTEP: nve1<br>allowas-in 3"]
    end

    subgraph Hosts ["<b>Hosts</b>"]
        H1["<b>host1</b><br>10.50.50.51/24<br>VLAN 50 · gw .50.1"]
        H2["<b>host2</b><br>10.50.50.52/24<br>VLAN 50 · gw .50.1"]
        H3["<b>host3</b><br>10.40.40.43/24<br>VLAN 40 · gw .40.1"]
        H4["<b>host4</b><br>10.60.60.64/24<br>VLAN 60 · gw .60.1"]
    end

    S1 ---|"eBGP EVPN"| L1
    S1 ---|"eBGP EVPN"| L2
    S1 ---|"eBGP EVPN"| L3
    S1 ---|"eBGP EVPN"| L4

    S2 ---|"eBGP EVPN"| L1
    S2 ---|"eBGP EVPN"| L2
    S2 ---|"eBGP EVPN"| L3
    S2 ---|"eBGP EVPN"| L4

    L1 ---|"Eth7 · VLAN 50"| H1
    L2 ---|"Eth7 · VLAN 50"| H2
    L3 ---|"Eth1/7 · VLAN 40"| H3
    L4 ---|"Eth1/7 · VLAN 60"| H4

    classDef spine fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef leaf fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef host fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class S1,S2 spine
    class L1,L2,L3,L4 leaf
    class H1,H2,H3,H4 host
```

## VXLAN Tunnel Mesh

```mermaid
graph LR
    subgraph VTEPs ["<b>VXLAN Tunnel Mesh — Full Mesh via EVPN</b>"]
        L1["<b>leaf1</b><br>Vxlan1<br>10.0.250.11"]
        L2["<b>leaf2</b><br>Vxlan1<br>10.0.250.12"]
        L3["<b>leaf3</b><br>nve1<br>10.0.250.13"]
        L4["<b>leaf4</b><br>nve1<br>10.0.250.14"]
    end

    L1 <-->|"VNI 100050"| L2
    L1 <-->|"VNI 100040<br>VNI 100001"| L3
    L1 <-->|"VNI 100060<br>VNI 100001"| L4
    L2 <-->|"VNI 100040<br>VNI 100001"| L3
    L2 <-->|"VNI 100060<br>VNI 100001"| L4
    L3 <-->|"VNI 100001"| L4

    classDef eos fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef nxos fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    class L1,L2 eos
    class L3,L4 nxos
```

## VRF and Tenant Design

```mermaid
graph TD
    VRF["<b>VRF gold</b><br>L3 VNI: 100001<br>Transit VLAN: 101"]

    V40["<b>VLAN 40</b><br>Data_VLAN_40<br>L2 VNI: 100040<br>SVI: 10.40.40.1/24"]
    V50["<b>VLAN 50</b><br>Data_VLAN_50<br>L2 VNI: 100050<br>SVI: 10.50.50.1/24"]
    V60["<b>VLAN 60</b><br>Data_VLAN_60<br>L2 VNI: 100060<br>SVI: 10.60.60.1/24"]
    V101["<b>VLAN 101</b><br>L3VNI_Transit<br>VNI: 100001<br>Symmetric IRB"]

    VRF --> V40
    VRF --> V50
    VRF --> V60
    VRF --> V101

    classDef vrf fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef data fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef transit fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    class VRF vrf
    class V40,V50,V60 data
    class V101 transit
```

## Anycast Gateway

```mermaid
graph TD
    MAC["<b>Shared Anycast MAC</b><br>00:11:22:33:44:55"]

    MAC --> SVI40["<b>Vlan40</b><br>Virtual IP: 10.40.40.1/24"]
    MAC --> SVI50["<b>Vlan50</b><br>Virtual IP: 10.50.50.1/24"]
    MAC --> SVI60["<b>Vlan60</b><br>Virtual IP: 10.60.60.1/24"]

    SVI40 --> L1_40["leaf1 — 10.40.40.2/24<br>ip virtual-router"]
    SVI40 --> L2_40["leaf2 — 10.40.40.2/24<br>ip virtual-router"]
    SVI40 --> L3_40["leaf3 — 10.40.40.1/24<br>anycast-gateway"]
    SVI40 --> L4_40["leaf4 — 10.40.40.1/24<br>anycast-gateway"]

    classDef mac fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef svi fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef eos fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef nxos fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class MAC mac
    class SVI40,SVI50,SVI60 svi
    class L1_40,L2_40 eos
    class L3_40,L4_40 nxos
```

## Overlay Test Scenarios

```mermaid
flowchart LR
    subgraph Scenario1 ["<b>L2 Stretch — Same VLAN, Same Vendor</b>"]
        H1a["host1<br>10.50.50.51<br>VLAN 50"]
        H2a["host2<br>10.50.50.52<br>VLAN 50"]
        H1a <-->|"VNI 100050<br>Type-2 MAC/IP<br>No routing needed"| H2a
    end

    subgraph Scenario2 ["<b>Inter-VLAN IRB — Same Vendor (NX-OS)</b>"]
        H3a["host3<br>10.40.40.43<br>VLAN 40"]
        H4a["host4<br>10.60.60.64<br>VLAN 60"]
        H3a <-->|"Symmetric IRB<br>L3VNI 100001<br>VRF gold"| H4a
    end

    subgraph Scenario3 ["<b>Cross-Platform Inter-VLAN</b>"]
        H1b["host1<br>10.50.50.51<br>VLAN 50<br>EOS leaf1"]
        H3b["host3<br>10.40.40.43<br>VLAN 40<br>NX-OS leaf3"]
        H1b <-->|"Symmetric IRB<br>L3VNI 100001<br>EOS ↔ NX-OS"| H3b
    end

    classDef vlan50 fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef vlan40 fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef vlan60 fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef eos fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef nxos fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    class H1a,H2a vlan50
    class H3a,H3b vlan40
    class H4a vlan60
    class H1b eos
```

## Symmetric IRB Packet Walk (host1 → host3)

```mermaid
flowchart LR
    H1["<b>host1</b><br>10.50.50.51<br>dst: 10.40.40.43"]
    L1["<b>leaf1 (EOS)</b><br>Ingress VTEP"]
    S["<b>Spine</b><br>IP Forward"]
    L3["<b>leaf3 (NX-OS)</b><br>Egress VTEP"]
    H3["<b>host3</b><br>10.40.40.43"]

    H1 -->|"1. Frame to<br>gw 10.50.50.1"| L1
    L1 -->|"2. Route in VRF gold<br>VLAN 50 SVI → L3VNI<br>Encap VNI 100001<br>dst VTEP 10.0.250.13"| S
    S -->|"3. IP forward<br>to leaf3 Lo0"| L3
    L3 -->|"4. Decap L3VNI<br>Route → VLAN 40 SVI<br>Forward to host3"| H3

    classDef host fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef eos fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef nxos fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef spine fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    class H1,H3 host
    class L1 eos
    class L3 nxos
    class S spine
```

## Platform Comparison — EOS vs NX-OS

```mermaid
graph TD
    subgraph EOS ["<b>Arista EOS (leaf1, leaf2)</b>"]
        E1["VXLAN Interface: <b>Vxlan1</b>"]
        E2["VRF: <code>vrf instance gold</code><br><code>ip routing vrf gold</code>"]
        E3["Anycast GW:<br><code>ip virtual-router mac-address</code><br><code>ip virtual-router address</code> per SVI"]
        E4["EVPN: VLAN-aware bundles<br>RD: loopback:vlan_id"]
        E5["BUM: flood vtep learned<br>data-plane"]
    end

    subgraph NXOS ["<b>Cisco NX-OS (leaf3, leaf4)</b>"]
        N1["VXLAN Interface: <b>nve1</b>"]
        N2["VRF: <code>vrf context gold</code><br><code>vni 100001</code> inside VRF"]
        N3["Anycast GW:<br><code>fabric forwarding anycast-gateway-mac</code><br><code>fabric forwarding mode anycast-gateway</code>"]
        N4["EVPN: global <code>evpn</code> context<br>RD: auto"]
        N5["BUM: ingress-replication<br>protocol bgp + suppress-arp"]
    end

    classDef eos fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef nxos fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    class E1,E2,E3,E4,E5 eos
    class N1,N2,N3,N4,N5 nxos
```

## VLAN-to-VNI Mapping

| VLAN | Name           | L2 VNI  | RT (Import/Export) | Purpose                     |
|------|----------------|---------|--------------------|-----------------------------|
| 40   | Data_VLAN_40   | 100040  | 1:100040           | Host data connectivity      |
| 50   | Data_VLAN_50   | 100050  | 1:100050           | Host data connectivity      |
| 60   | Data_VLAN_60   | 100060  | 1:100060           | Host data connectivity      |
| 101  | L3VNI_Transit  | 100001  | 1:100001           | Symmetric IRB (VRF `gold`)  |

## VTEP Addressing

| Device | Platform   | Loopback0 (VTEP Source) | VXLAN Interface | UDP Port |
|--------|------------|-------------------------|-----------------|----------|
| leaf1  | Arista EOS | 10.0.250.11/32          | Vxlan1          | 4789     |
| leaf2  | Arista EOS | 10.0.250.12/32          | Vxlan1          | 4789     |
| leaf3  | Cisco NX-OS| 10.0.250.13/32          | nve1            | 4789     |
| leaf4  | Cisco NX-OS| 10.0.250.14/32          | nve1            | 4789     |

## Anycast Gateway Addresses

| SVI    | Virtual Gateway IP | Anycast MAC        |
|--------|--------------------|--------------------|
| Vlan40 | 10.40.40.1/24      | 00:11:22:33:44:55  |
| Vlan50 | 10.50.50.1/24      | 00:11:22:33:44:55  |
| Vlan60 | 10.60.60.1/24      | 00:11:22:33:44:55  |

## Host-to-Leaf Connectivity

| Host  | Leaf          | Interface | VLAN | Host IP        | Default Gateway |
|-------|---------------|-----------|------|----------------|-----------------|
| host1 | leaf1 (EOS)   | Eth7      | 50   | 10.50.50.51/24 | 10.50.50.1      |
| host2 | leaf2 (EOS)   | Eth7      | 50   | 10.50.50.52/24 | 10.50.50.1      |
| host3 | leaf3 (NX-OS) | Eth1/7    | 40   | 10.40.40.43/24 | 10.40.40.1      |
| host4 | leaf4 (NX-OS) | Eth1/7    | 60   | 10.60.60.64/24 | 10.60.60.1      |

## PIM Multicast

| Setting            | Value                              |
|--------------------|------------------------------------|
| RP Address         | 10.0.255.254 (anycast)             |
| NX-OS Anycast RP   | Peers: 10.0.250.13, 10.0.250.14   |
| EOS PIM Interfaces | Ethernet11, Ethernet12             |
| NX-OS PIM Interfaces | Eth1/11, Eth1/12, Lo0, Vlan101  |
