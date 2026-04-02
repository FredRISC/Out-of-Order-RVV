## Out-of-Order RV32IMV Processor Prototype

This is a single-issue, speculatively-renamed, Out-of-Order RISC-V processor prototype. It supports the `RV32IM` base integer extensions alongside a tightly-coupled Vector Coprocessor implementing a stripped-down subset of the `Zve32x` Vector Extension.

This project serves as a comprehensive architectural study, utilizing a **Unified Scalar/Vector Datapath** and a modern, ARF-less **Register Alias Table (RAT) + Physical Register File (PRF)** architecture (inspired by the MIPS R10000) to achieve precise out-of-order execution.

### Core Architecture

* **7-Stage Pipeline:** Fetch, Decode, Dispatch/Rename, Issue, RegRead, Execute, Commit (via ROB).
* **Hardware Renaming (RAT+PRF):** The design completely eliminates the traditional Architectural Register File (ARF). Speculative data lives entirely in the PRF. The ROB handles in-order retirement by updating the Commit RAT, dynamically shifting architectural pointers without copying data.
* **Unified Issue & Payload Datapath:** To minimize code footprint, the processor utilizes highly parameterized, generic tag-based Reservation Stations. Scalar and vector instructions share the same issue logic and `reg_read_stage` routers.
* **Issue Scheduling:** A calendar-based Writeback Scheduler pre-reserves cycles on the Common Data Bus (CDB) to prevent structural hazards, arbitrating superscalar wakeups efficiently.
* **Dynamic Branch Prediction:** Features a 2-bit Branch History Table (BHT) and Branch Target Buffer (BTB) integrated into the Fetch stage, with delayed precise state recovery handled by the ROB.
* **Superscalar-Capable Backend:** While the frontend is strictly scalar (1-wide fetch/dispatch), the backend is fully superscalar, capable of issuing and executing up to 5 disjoint instruction types (ALU, MEM, MUL, DIV, VEC) simultaneously.
* **Vector Coprocessor (`VLEN=128`):** A 4-lane Vector Execution Unit processes 128-bit blocks in a single cycle. `vl` and `vtype` are dynamically tracked as physical dependencies.
* **Vector-Aware Load/Store Queue (LSQ):** Features combinational memory disambiguation and store-to-load forwarding. An embedded FSM automatically bridges the 128-bit Vector datapath with a standard 32-bit memory interface, supporting dynamic unit-strides and strided loads (SEW=32).

---

### Verification & Physical Design Strategy


---

### Next-Gen Roadmap

While functional, this prototype takes deliberate shortcuts to fit within a manageable Verilog footprint. A future, highly-modularized "V2" core will implement the following industry-standard techniques:

1. **Decoupled Scalar/Vector Datapaths:** Separating the integer and vector pipelines after Dispatch to eliminate massive cross-domain routing complexity.
2. **Superscalar Frontend:** Expanding the Fetch, Decode, and RAT structures to handle 2+ instructions per cycle.
3. **Micro-op Cracking (`LMUL > 1`):** Industry cores dynamically support `LMUL=2,4,8` by stalling the decoder and "cracking" the instruction into multiple `LMUL=1` micro-operations. Our core currently only supports `LMUL=1`.
4. **Element-Level Chaining & Pipelined VEU:** Our VEU currently computes 128 bits in one cycle. An industry core deeply pipelines the VEU and uses Bypass FIFOs to broadcast elements cycle-by-cycle, allowing dependent instructions to chain immediately.
5. **Masking (`v0.t`) & Precise Exceptions (`vstart`):** Adding the vector mask register network, and robust page-fault handling. If an industry LSQ hits a Page Fault mid-vector, it halts, saves the index to the `vstart` CSR, flushes, and resumes later.