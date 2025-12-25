# 4-Bit CPU on Shrike Lite

This project implements a custom **4-bit Soft-Core CPU** on the Vicharak **Shrike Lite** board. 

Originally designed by **Noah Gaertner** for SystemVerilog simulation, this core has been ported to the **Renesas SLG47910 FPGA** to work as a hardware accelerator for the RP2040.

Instead of using physical buttons and LEDs, this CPU is controlled entirely via **SPI**. The RP2040 acts as the "Front Panel," sending instructions, loading memory, and single-stepping the clock.

---

## 🏗 System Architecture

The system is a hybrid design:
* **RP2040 (Master):** Handles the high-level logic, user interface (USB/WiFi), and controls the CPU execution.
* **FPGA (Slave):** Contains the CPU core, memory (RAM/ROM), and ALU.

### Specifications
| Feature | Detail |
| :--- | :--- |
| **Data Width** | 4-bit (Nibble) |
| **Address Space** | 16 lines of Program Memory, 16 slots of Data Memory |
| **Clocking** | Manual Stepping via SPI (Synchronous to FPGA System Clock) |
| **Interface** | 8-bit SPI Packet (Command + Payload) |

---

## 🔌 The SPI Interface

To interact with the CPU, the RP2040 sends **8-bit packets** over SPI. The FPGA replies simultaneously with the current CPU state.

### Input Packet (RP2040 -> FPGA)
| Bit [7:4] | Bit [3:2] | Bit [1] | Bit [0] |
| :---: | :---: | :---: | :---: |
| **DATA Payload** | **INSTRUCTION** | **RESET** | **STEP** |
| 4-bit Value | Mode Selector | 1 = Reset CPU | 1 = Execute Cycle |

* **DATA Payload:** The number to be loaded into memory or the PC.
* **INSTRUCTION:**
    * `00` **LOADPROG**: Write payload to Program Memory at current PC.
    * `01` **LOADDATA**: Write payload to Data Memory at current PC.
    * `10` **SETRUNPT**: Set the Program Counter (PC) to the payload value.
    * `11` **RUNPROG**: Normal execution mode.
* **RESET:** Active High. Clears PC, Registers, and Memory.
* **STEP:** Rising-edge trigger. The CPU executes **one cycle** per packet where this bit is `1`.

### Output Packet (FPGA -> RP2040)
| Bit [7:4] | Bit [3:0] |
| :---: | :---: |
| **REGVAL** | **PC** |
| Current Accumulator Value | Current Program Counter |

---

## 📜 Instruction Set Architecture (ISA)

The CPU supports 16 operations. These opcodes are stored in the **Program Memory**.

| Opcode | Name | Description |
| :--- | :--- | :--- |
| `0` | **LOAD** | `Reg = Data[PC]` (Immediate Load) |
| `1` | **STORE** | `Data[Address] = Reg` (Indirect Store) |
| `2` | **ADD** | `Reg = Reg + Data[PC]` |
| `3` | **MUL** | `Reg = Reg * Data[PC]` |
| `4` | **SUB** | `Reg = Reg - Data[PC]` |
| `5` | **SHIFTL** | Left Shift |
| `6` | **SHIFTR** | Right Shift |
| `7` | **JUMPTOIF**| Jump to `Data[PC]` if the MSB of Input (Bit 7) is High |
| `8` | **LOGICAND**| Logical AND (`&&`) |
| `9` | **LOGICOR** | Logical OR (`||`) |
| `10`| **EQUALS** | `Reg = (Reg == Data[PC])` |
| `11`| **NEQ** | `Reg = (Reg != Data[PC])` |
| `12`| **BITAND** | Bitwise AND (`&`) |
| `13`| **BITOR** | Bitwise OR (`|`) |
| `14`| **LOGICNOT**| Logical NOT (`!`) |
| `15`| **BITNOT** | Bitwise NOT (`~`) |

---

## 🚀 How to Run

### 1. Hardware Setup
Flash the FPGA bitstream containing `top.v`, `cpu_core.v`, and `spi_target.v`.

### 2. RP2040 Controller Code (Python Example)
Use this logic in your MicroPython/C code to drive the CPU.

```python
import machine
import time

# SPI Setup (Adjust pins for Shrike Lite)
spi = machine.SPI(0, baudrate=1000000, polarity=0, phase=0)
cs = machine.Pin(17, machine.Pin.OUT)

def send_packet(data, instr, reset, step):
    # Construct the byte: [Data 4b] [Instr 2b] [Rst 1b] [Step 1b]
    byte = (data << 4) | (instr << 2) | (reset << 1) | step
    cs.value(0)
    response = spi.read(1, byte)
    cs.value(1)
    
    # Parse Response
    val = response[0]
    reg = val >> 4
    pc = val & 0x0F
    return reg, pc

# --- Example Sequence: Add 2 + 3 ---

# 1. Reset CPU
send_packet(0, 0, 1, 0) 

# 2. Load Program: "ADD 3" (Opcode 2) at Address 0
# Opcode 2 (ADD) -> Data Payload = 2
# Instruction 0 (LOADPROG) -> Instr = 0
send_packet(2, 0, 0, 1) # Step to write

# 3. Load Data: Value "3" at Address 0 (Since ADD uses Data[PC])
# Value 3 -> Data Payload = 3
# Instruction 1 (LOADDATA) -> Instr = 1
send_packet(3, 1, 0, 1) # Step to write

# 4. Set Register to 2 (Manually, or via LOAD command). 
# Let's assume Reg starts at 0. We need to load 2 first. 
# (Simplification: Just running the ADD instruction with Reg=0 will result in 0+3=3)

# 5. Run Program
# Instruction 3 (RUNPROG)
reg, pc = send_packet(0, 3, 0, 1) # Execute Step 1
print(f"Result: {reg}")
