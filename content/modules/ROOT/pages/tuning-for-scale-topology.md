# Tuning for Scale — Forks, Serial, max_fail_percentage

## How the Controls Layer Together

```mermaid
flowchart TD
    INV["<b>Inventory</b><br>6 hosts"]
    SERIAL["<b>serial</b><br>Splits inventory into batches"]
    FORKS["<b>forks</b><br>Parallelism within each batch"]
    MFP["<b>max_fail_percentage</b><br>Abort threshold per batch"]
    THROTTLE["<b>throttle</b><br>Per-task concurrency cap"]

    INV --> SERIAL
    SERIAL -->|"Batch 1"| FORKS
    SERIAL -->|"Batch 2"| FORKS
    SERIAL -->|"Batch N"| FORKS
    FORKS --> MFP
    MFP -->|"Under threshold"| NEXT["Next batch"]
    MFP -->|"Over threshold"| ABORT["ABORT remaining batches"]
    FORKS --> THROTTLE

    classDef control fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef action fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef danger fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef inv fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class SERIAL,FORKS,MFP,THROTTLE control
    class NEXT action
    class ABORT danger
    class INV inv
```

## What Each Setting Controls

```mermaid
flowchart LR
    subgraph serial ["<b>serial — Batch Size</b>"]
        direction TB
        S1["Splits inventory into groups"]
        S2["Runs ALL tasks per batch<br>before moving to next"]
        S3["Accepts counts, %, or lists<br>serial: [1, '50%', '100%']"]
    end

    subgraph forks ["<b>forks — Parallelism</b>"]
        direction TB
        F1["SSH connections open<br>simultaneously per task"]
        F2["Default: 5"]
        F3["Set on Job Template in AAP"]
    end

    subgraph mfp ["<b>max_fail_percentage — Safety Net</b>"]
        direction TB
        M1["Max % of hosts that can<br>fail before aborting"]
        M2["0 = any failure stops all"]
        M3["Works with serial batches"]
    end

    subgraph throttle ["<b>throttle — Task Limiter</b>"]
        direction TB
        T1["Per-task concurrency cap"]
        T2["Overrides forks for<br>one specific task"]
        T3["Use for shared resources<br>Git, APIs, license servers"]
    end

    classDef box fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    class S1,S2,S3,F1,F2,F3,M1,M2,M3,T1,T2,T3 box
```

## Forks — Parallel Execution Within a Batch

```mermaid
flowchart TD
    subgraph Batch ["<b>Batch of 6 hosts · forks = 3</b>"]
        direction TB
        subgraph Wave1 ["<b>Wave 1 — 3 forks</b>"]
            H1["host1<br>SSH"]
            H2["host2<br>SSH"]
            H3["host3<br>SSH"]
        end
        subgraph Wave2 ["<b>Wave 2 — 3 forks</b>"]
            H4["host4<br>SSH"]
            H5["host5<br>SSH"]
            H6["host6<br>SSH"]
        end
        Wave1 -->|"Wait for all 3<br>to finish task"| Wave2
    end

    classDef active fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef queued fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class H1,H2,H3 active
    class H4,H5,H6 queued
```

## Serial — Canary Deployment Pattern

```mermaid
flowchart LR
    subgraph B1 ["<b>Batch 1 — serial: 1</b><br>Canary"]
        L1["leaf1"]
    end

    subgraph B2 ["<b>Batch 2 — serial: 50%</b><br>3 of 6 hosts"]
        L2["leaf2"]
        L3["leaf3"]
        L4["leaf4"]
    end

    subgraph B3 ["<b>Batch 3 — serial: 100%</b><br>Remainder"]
        SP1["spine1"]
        SP2["spine2"]
    end

    B1 -->|"All tasks pass"| B2
    B2 -->|"All tasks pass"| B3
    B3 --> DONE["All 6 configured"]

    classDef canary fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef expand fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef final fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef done fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    class L1 canary
    class L2,L3,L4 expand
    class SP1,SP2 final
    class DONE done
```

## Run 1 — No Error (max_fail: 0)

```mermaid
flowchart LR
    subgraph B1 ["<b>Batch 1 — Canary</b>"]
        L1["leaf1 ✓<br>SNMP configured"]
    end

    subgraph B2 ["<b>Batch 2 — 50%</b>"]
        L2["leaf2 ✓<br>SNMP configured"]
        L3["leaf3 ✓<br>SNMP configured"]
        L4["leaf4 ✓<br>SNMP configured"]
    end

    subgraph B3 ["<b>Batch 3 — 100%</b>"]
        SP1["spine1 ✓<br>SNMP configured"]
        SP2["spine2 ✓<br>SNMP configured"]
    end

    B1 -->|"Pass"| B2
    B2 -->|"Pass"| B3
    B3 --> RESULT["<b>6/6 configured</b>"]

    classDef pass fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef result fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    class L1,L2,L3,L4,SP1,SP2 pass
    class RESULT result
```

## Run 2 — Error + max_fail_percentage: 0 (Zero Tolerance)

```mermaid
flowchart LR
    subgraph B1 ["<b>Batch 1 — Canary</b>"]
        L1["leaf1 (EOS) ✓<br>SNMP configured"]
    end

    subgraph B2 ["<b>Batch 2 — 50%</b>"]
        L2["leaf2 (EOS)<br>Skipped error task<br>but ABORTED before SNMP"]
        L3["leaf3 (NX-OS) ✗<br>FAILED"]
        L4["leaf4 (NX-OS) ✗<br>FAILED"]
    end

    subgraph B3 ["<b>Batch 3 — 100%</b>"]
        SP1["spine1<br>NEVER RUN"]
        SP2["spine2<br>NEVER RUN"]
    end

    B1 -->|"Pass"| B2
    B2 -->|"67% failed > 0%<br>ABORT"| STOP["PLAY ABORTED"]
    STOP -.->|"Batch 3 skipped"| B3

    classDef pass fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef fail fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef collateral fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef protected fill:#7f7f7f,stroke:#fff,stroke-width:2px,color:#fff
    classDef abort fill:#d62728,stroke:#fff,stroke-width:3px,color:#fff
    class L1 pass
    class L3,L4 fail
    class L2 collateral
    class SP1,SP2 protected
    class STOP abort
```

## Run 3 — Error + max_fail_percentage: 50 (Tolerant)

```mermaid
flowchart LR
    subgraph B1 ["<b>Batch 1 — 50%</b>"]
        L1["leaf1 (EOS) ✓<br>SNMP ok (already done)"]
        L2["leaf2 (EOS) ✓<br>SNMP configured"]
        L3["leaf3 (NX-OS) ✗<br>FAILED"]
    end

    subgraph B2 ["<b>Batch 2 — 100%</b>"]
        L4["leaf4 (NX-OS) ✗<br>FAILED"]
        SP1["spine1 (EOS) ✓<br>SNMP configured"]
        SP2["spine2 (EOS) ✓<br>SNMP configured"]
    end

    B1 -->|"33% failed < 50%<br>CONTINUE"| B2
    B2 --> RESULT["<b>4/6 configured</b><br>Only NX-OS failed"]

    classDef pass fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef fail fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef result fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    class L1,L2,SP1,SP2 pass
    class L3,L4 fail
    class RESULT result
```

## Impact Comparison — 0% vs 50% Tolerance

```mermaid
flowchart TD
    subgraph Zero ["<b>max_fail_percentage: 0</b><br>Zero Tolerance"]
        direction LR
        Z_OK["leaf1<br>Configured"]
        Z_FAIL["leaf3, leaf4<br>Failed"]
        Z_COLLATERAL["leaf2<br>Collateral damage"]
        Z_SKIP["spine1, spine2<br>Never attempted"]
    end

    subgraph Fifty ["<b>max_fail_percentage: 50</b><br>Tolerant"]
        direction LR
        F_OK["leaf1, leaf2<br>spine1, spine2<br>Configured"]
        F_FAIL["leaf3, leaf4<br>Failed"]
    end

    RESULT_Z["<b>1/6</b> configured<br>3 protected, 2 failed"]
    RESULT_F["<b>4/6</b> configured<br>0 protected, 2 failed"]

    Zero --> RESULT_Z
    Fifty --> RESULT_F

    classDef pass fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef fail fill:#d62728,stroke:#fff,stroke-width:2px,color:#fff
    classDef collateral fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef skip fill:#7f7f7f,stroke:#fff,stroke-width:2px,color:#fff
    classDef result fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    class Z_OK,F_OK pass
    class Z_FAIL,F_FAIL fail
    class Z_COLLATERAL collateral
    class Z_SKIP skip
    class RESULT_Z,RESULT_F result
```

## Throttle — Protecting Shared Resources

```mermaid
flowchart TD
    subgraph Batch ["<b>Batch — forks: 50</b>"]
        H1["host1"]
        H2["host2"]
        H3["host3"]
        HD["..."]
        H50["host50"]
    end

    subgraph Task1 ["<b>Task: Configure SNMP</b><br>No throttle — all 50 forks"]
        T1_1["host1"]
        T1_2["host2"]
        T1_D["..."]
        T1_50["host50"]
    end

    subgraph Task2 ["<b>Task: Commit to Git</b><br>throttle: 1"]
        T2_1["host1"]
        T2_QUEUE["host2...50<br>queued"]
    end

    Batch --> Task1
    Task1 --> Task2

    classDef parallel fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef throttled fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    classDef batch fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef queued fill:#7f7f7f,stroke:#fff,stroke-width:2px,color:#fff
    class H1,H2,H3,HD,H50 batch
    class T1_1,T1_2,T1_D,T1_50 parallel
    class T2_1 throttled
    class T2_QUEUE queued
```

## Production Example — Layered Controls

```mermaid
flowchart TD
    JT["<b>Job Template</b><br>forks: 25"]
    PLAY["<b>Play</b><br>serial: '25%'<br>max_fail_percentage: 10"]

    subgraph B1 ["<b>Batch 1 — 25% of inventory</b>"]
        direction LR
        TASK_A["Task: Deploy Config<br>25 forks — full speed"]
        TASK_B["Task: Git Commit<br>throttle: 1"]
        TASK_A --> TASK_B
    end

    subgraph B2 ["<b>Batch 2 — 25%</b>"]
        B2T["Same tasks..."]
    end

    subgraph B3 ["<b>Batch 3 — 25%</b>"]
        B3T["Same tasks..."]
    end

    subgraph B4 ["<b>Batch 4 — 25%</b>"]
        B4T["Same tasks..."]
    end

    JT --> PLAY --> B1
    B1 -->|"< 10% failed"| B2
    B2 -->|"< 10% failed"| B3
    B3 -->|"< 10% failed"| B4
    B4 --> DONE["All batches complete"]

    classDef jt fill:#9467bd,stroke:#fff,stroke-width:2px,color:#fff
    classDef play fill:#1f77b4,stroke:#fff,stroke-width:2px,color:#fff
    classDef task fill:#2ca02c,stroke:#fff,stroke-width:2px,color:#fff
    classDef done fill:#ff7f0e,stroke:#fff,stroke-width:2px,color:#fff
    class JT jt
    class PLAY play
    class TASK_A,TASK_B,B2T,B3T,B4T task
    class DONE done
```
