# Architecture Roadmap & Industry Gaps

This document tracks the specific architectural shortcuts taken in the prototype and the necessary upgrades required to reach commercial silicon parity.

While highly functional, this processor is designed as a manageable Verilog footprint for study. A future, highly-modularized "A" core would implement the following industry-standard techniques.

### 1. Decoupled Scalar/Vector Datapaths
Separating the integer and vector pipelines entirely after the Dispatch stage to eliminate massive cross-domain routing complexity in the `reg_read_stage` and physical register files.

### 2. Micro-op Cracking (`LMUL > 1`)
Industry cores dynamically support `LMUL=2,4,8` by stalling the decoder and "cracking" the instruction into multiple `LMUL=1` micro-operations. Our core currently only supports `LMUL=1` natively.

### 3. Element-Level Chaining
Our VEU computes all 128 bits in one cycle (or waits for all 128 bits to load from the LSQ) before broadcasting. An industry core starts broadcasting element 0 on cycle 1, and the dependent instruction starts computing element 0 on cycle 2, while the first instruction is still computing element 1. This requires complex Bypass FIFOs.

### 4. Pipelined VEU
Our VEU is a 1-cycle combinational block. At 128 bits, this would severely limit our maximum clock frequency ($F_{max}$) in silicon. Industry VEUs are deeply pipelined (e.g., 4 to 6 stages).

### 5. Masking (`v0.t`)
We skipped the vector mask register and masked execution paths to save cross-lane routing complexity.

### 6. Exceptions & `vstart`
If the LSQ hits a Page Fault on the 3rd element of a vector load, it halts, saves the index to the `vstart` CSR, flushes the pipeline, and later resumes from element 3. We currently assume a flat, physical memory space that never faults mid-vector.

### 7. LSQ Disambiguation Memory (CAMs)
Our LSQ uses standard-cell combinational for-loops to check address overlaps (WAR/RAW/WAW hazards). In physical design, this creates a massive critical path. A production core splits the LSQ into a Load Queue and Store Buffer, utilizing custom Content Addressable Memory (CAM) arrays for 1-cycle associative lookups.

### 8. Frontend Redirects (Early Branch Resolution)
Currently, all jumps (`JAL`/`JALR`) traverse the entire pipeline and rely on the ROB for state recovery. Industry cores feature an Early Branch Resolution Unit in the Decode stage to instantly compute unconditional targets and flush only the Fetch stage, saving cycles on BTB misses.

### 9. RAT Checkpointing (Snapshots)
Currently, branch misprediction recovery waits until the branch reaches the head of the ROB to copy the Arch RAT back to the Spec RAT. Aggressive cores take a physical hardware snapshot of the Spec RAT upon dispatching a branch, allowing instant recovery the moment the Execute stage detects a misprediction.
