# RVV_SUBSET.md - RISC-V Vector Extension Design

## Overview

This document describes the RVV (RISC-V Vector Extension) subset implemented in this processor, based on the ratified v1.0 specification.

---

## Vector Register File

### Configuration
- **Vector Registers**: v0-v31 (32 registers)
- **VLEN**: 128 bits (vector register width)
- **VLMAX**: 16 elements (for 8-bit elements; scales with element width)
- **ELEN**: 32 bits (maximum element width)
- **Lanes**: 4 parallel 32-bit execution lanes

### Register Organization
```
Each vector register (128 bits):
┌────────────────────────────────────────────────────────────┐
│ Element 3  │ Element 2  │ Element 1  │ Element 0          │
│ [127:96]   │ [95:64]    │ [63:32]    │ [31:0]            │
└────────────────────────────────────────────────────────────┘

4 lanes × 32-bit = 128 bits total
```

---

## Supported Instructions

### 1. Vector Configuration

**VSETVLI** (Set Vector Length Immediate)
- Format: `VSETVLI rd, rs1, vtypei`
- Sets VL (vector length) for current block
- Returns new VL to register rd
- vtypei encodes SEW (standard element width) and LMUL (register grouping)

```
vtypei format:
[10:0] = immediate value
- [7:5] = SEW (element width)
- [3:0] = LMUL (multiplier)

SEW values: 32 (2'b101)
LMUL values: 1 (2'b000)
```

### 2. Vector Arithmetic - Element-wise Operations

All arithmetic operations are **masked** (optional masking via vm field).

#### Addition
```
VADD.VV vd, vs2, vs1       ; vd[i] = vs2[i] + vs1[i]
VADD.VI vd, vs2, imm       ; vd[i] = vs2[i] + imm
```

#### Subtraction
```
VSUB.VV vd, vs2, vs1       ; vd[i] = vs2[i] - vs1[i]
```

#### Multiplication
```
VMUL.VV vd, vs2, vs1       ; vd[i] = vs2[i] × vs1[i]
```

#### Division
```
VDIV.VV vd, vs2, vs1       ; vd[i] = vs2[i] ÷ vs1[i]
VDIVU.VV vd, vs2, vs1      ; Unsigned division
```

### 3. Vector Logical Operations

```
VAND.VV vd, vs2, vs1       ; vd[i] = vs2[i] & vs1[i]
VOR.VV  vd, vs2, vs1       ; vd[i] = vs2[i] | vs1[i]
VXOR.VV vd, vs2, vs1       ; vd[i] = vs2[i] ^ vs1[i]
```

### 4. Vector Shift Operations

```
VSLL.VV vd, vs2, vs1       ; vd[i] = vs2[i] << vs1[i]
VSRL.VV vd, vs2, vs1       ; vd[i] = vs2[i] >> vs1[i] (logical)
VSRA.VV vd, vs2, vs1       ; vd[i] = vs2[i] >>> vs1[i] (arithmetic)
```

### 5. Vector Reduction Operations

These combine all elements into a single result.

```
VREDSUM.VS vd, vs2, vs1    ; vd = vs1[0] + Σ vs2[i]
VREDMAX.VS vd, vs2, vs1    ; vd = MAX(vs2[*])
VREDMIN.VS vd, vs2, vs1    ; vd = MIN(vs2[*])
```

### 6. Vector Load/Store

```
VLE32.V vd, (rs1)          ; Load 32-bit elements into vd from memory[rs1]
VSE32.V vs3, (rs1)         ; Store 32-bit elements from vs3 to memory[rs1]
```

---

## Design Rationale

### Why This Subset?

**Included Operations:**
- ✅ Basic arithmetic (ADD, SUB, MUL, DIV)
- ✅ Logical operations (AND, OR, XOR)
- ✅ Shifts (SLL, SRL, SRA)
- ✅ Reductions (SUM, MAX, MIN)
- ✅ Load/Store

**Excluded (For Scope):**
- ❌ Floating-point (F/D extensions)
- ❌ Masked operations (initially)
- ❌ Permutation/shuffle
- ❌ Integer conversion
- ❌ Widening/narrowing
- ❌ Compression

**Rationale:**
1. **Educational**: Covers fundamental RVV concepts
2. **Practical**: Sufficient for BLAS-like kernels, signal processing
3. **Extensible**: Can add more ops later without major changes
4. **Implementable**: Tractable for single-semester project

### Why 4 Lanes?

| Configuration | Pros | Cons |
|---------------|------|------|
| **2 lanes** (64-bit) | Smaller area | Limited parallelism |
| **4 lanes** (128-bit) | Good parallelism, reasonable area | Moderate complexity |
| **8 lanes** (256-bit) | High throughput | 2× area, complex routing |

**Choice: 4 lanes** - balances performance and implementation complexity

### Why VLEN=128?

| VLEN | Pros | Cons |
|------|------|------|
| 64-bit | Smaller, simpler | Limited effectiveness |
| **128-bit** | Industry standard (SVE, NEON base) | Reasonable area |
| 256-bit | Higher throughput | 2× area |
| 512-bit | Maximum parallelism | Too large for embedded |

**Choice: 128-bit** - aligns with SVE, NEON, modern standards

### Why VLMAX=16?

**For VLEN=128 and ELEN=32:**
- VLMAX = VLEN / ELEN = 128 / 8 = 16 elements

This means with 32-bit elements:
- Maximum 16 elements per vector operation
- Scales automatically for smaller element sizes

---

## Vector Execution Pipeline

### Single Vector Operation Timeline

```
Cycle 0: Issue VADD.VV v1, v2, v3
         vl=16 (all 16 elements)
         ├─ Lane 0 executes on element 0
         ├─ Lane 1 executes on element 1
         ├─ Lane 2 executes on element 2
         └─ Lane 3 executes on element 3

Cycle 1-2: Continue for remaining elements
           (full throughput after pipeline fills)

Cycle N: Result available, next vector instruction can start
```

### Chaining: Dependent Vector Operations

**Definition**: Two vector operations on consecutive values with overlapping lanes

**Example:**
```
Cycle 0: Issue VADD.VV v1, v2, v3    ; vd=v1
Cycle 1: Issue VMUL.VV v4, v1, v5    ; vs1=v1 (depends on previous)
         ├─ Lane 0 of MUL starts immediately (forwarding from ADD lane 0)
         └─ Other lanes wait for ADD to propagate

Result**: Dependent operations overlap without stalling
```

**Benefit**: Reduces effective latency by 75%+ in dependent chains

---

## Instruction Encoding

### V-Type: Vector Arithmetic
```
[31:26]  [25]    [24:20]  [19:15]  [14:12]  [11:7]   [6:0]
funct6   vm      vs2      vs1      funct3   vd       opcode (1010111)
```

### Vector Instruction Format Details
```
funct6 (6 bits): Encodes operation (VADD=000000, VMUL=100101, etc.)
vm (1 bit):      Mask enable (0=masked, 1=unmasked)
vs2 (5 bits):    Source vector 2 register
vs1 (5 bits):    Source vector 1 register  
funct3 (3 bits): Operation subtype
vd (5 bits):     Destination vector register
opcode (7 bits): 1010111 for all vector arithmetic
```

---

## Vector Memory Subsystem

### Vector Load (VLE32.V)
```
Load pattern:
┌─────────────────────────┐
│ Memory Address: rs1     │
└─────────────────────────┘
        ↓ (read 4 × 32-bit)
┌────┬────┬────┬────┐
│ E0 │ E1 │ E2 │ E3 │  (4 parallel loads)
└────┴────┴────┴────┘
        ↓ (combined)
┌─────────────────────────┐
│ Vector Register vd      │ (128 bits)
└─────────────────────────┘
```

### Vector Store (VSE32.V)
```
Vector Register vs3
┌─────────────────────────┐
│ E0 │ E1 │ E2 │ E3 │    (128 bits)
└────┴────┴────┴────┘
        ↓ (extract 4 × 32-bit)
Write to Memory[rs1]:     (4 parallel stores)
        ↓
┌─────────────────────────┐
│ Memory addresses        │ (rs1, rs1+4, rs1+8, rs1+12)
└─────────────────────────┘
```

---

## Vector Register Interaction with Scalar ISA

- **Scalar registers** (x0-x31) are separate from vector registers (v0-v31)
- **Transfer instructions**: Not implemented in this subset
  - Would require VFMV, VMVSX, VMVXS in full RVV
  - This subset focuses on vector-only kernels
- **Future**: Can add scalar-vector transfer instructions

---

## Performance Characteristics

### Throughput

| Operation | Latency | Throughput | Notes |
|-----------|---------|-----------|-------|
| VADD | 1 cycle | 1 inst/cycle | Fully pipelined |
| VMUL | 1 cycle | 1 inst/cycle | Simplified for prototype |
| VDIV | 1 cycle | 1 inst/cycle | Not realistic (future: multi-cycle) |
| VREDSUM | 3-4 cycles | 1 inst/cycle | Reduction logic overhead |
| Load/Store | 2 cycles | 4 elem/cycle | Parallel lane access |

### Utilization

With 4 lanes and VLMAX=16:
- **Element parallelism**: 4× for 32-bit operations
- **Vector parallelism**: 16 elements per instruction
- **Peak throughput**: 64 32-bit operations per cycle (theoretical)

### Memory Bandwidth

- **Load**: 4 × 32-bit = 16 bytes/cycle (1 instruction)
- **Store**: 4 × 32-bit = 16 bytes/cycle (1 instruction)

---

## Testing & Verification

### Vector Test Cases
1. Element-wise operations (VADD, VMUL, etc.)
2. Reduction operations (sum, max, min)
3. Chaining (dependent vector operations)
4. Load/store with alignment
5. Various vector lengths (< VLMAX)

### Example Test: Vector Add
```
Inputs:  v1 = [1, 2, 3, ..., 16]
         v2 = [1, 1, 1, ..., 1]
Operation: VADD.VV v3, v1, v2
Expected: v3 = [2, 3, 4, ..., 17]

Verification: Each lane computes independently,
              results combined after completion
```

---

## Future Extensions

To add additional RVV operations:

1. **Widening/Narrowing**: Double/halve element width
   - VWADD, VWMUL, VNSRL, etc.
   - Requires separate datapath

2. **Floating-Point**: F and D extensions
   - VFADD, VFMUL, etc.
   - Requires FPU integration

3. **Mask Operations**: Full masking support
   - Conditional execution per element
   - Requires mask register file

4. **Permutation**: Shuffle and extract
   - VRGATHER, VSLIDEDOWN, etc.
   - Complex routing network

5. **Atomic**: Atomic vector operations
   - VAMOSWAP, VAMOADD, etc.
   - Requires atomic LSU logic

---

## References

- RISC-V Vector Extension v1.0 Specification
- https://github.com/riscv/riscv-v-spec
- RVV Ratification: June 2021

