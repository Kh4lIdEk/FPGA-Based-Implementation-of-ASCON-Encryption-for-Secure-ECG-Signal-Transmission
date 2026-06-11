# 🔐 ASCON-128 on FPGA (PynqZ2) — Secure ECG Acquisition

> Hardware-accelerated authenticated encryption (ASCON-128 AEAD) for real-time, secure ECG signal acquisition and analysis.

[![FPGA](https://img.shields.io/badge/FPGA-PynqZ2-purple)]()
[![HDL](https://img.shields.io/badge/HDL-SystemVerilog-blue)]()
[![Crypto](https://img.shields.io/badge/Crypto-ASCON--128%20(NIST%202023)-green)]()
[![Python](https://img.shields.io/badge/Python-3.10%2B-yellow)]()

**École des Mines de Saint-Étienne — Institut Mines-Télécom — 2025/2026**
Project by **Ali Ahnani** & **Khalid Elkoussami**, supervised by **Jean-Baptiste Rigaud** & **Raphaël Viera**.

---

## 📋 Overview

ECG signals are sensitive medical data, and a raw serial link between an acquisition device and a host PC is vulnerable to eavesdropping and tampering. This project implements **ASCON-128**, the NIST-standardized lightweight AEAD cipher, **entirely in hardware** on a **PynqZ2 FPGA**, to encrypt and authenticate ECG frames in real time before they are sent over UART.

A companion Python application drives the board, decrypts and verifies the data, and runs a full ECG analysis pipeline (heart rate, HRV metrics, PQRST detection) using **NeuroKit2**.

### Functional chain

```
ECG sensor → PC / Python (IACQ) ──UART──► FPGA / ASCON-128 ──► PC decryption
                                                                    │
                                                                    ▼
                                                  ECG analysis (NeuroKit2): BPM, SDNN, PQRST...
```

### Why ASCON-128?

- 🏆 NIST Lightweight Cryptography standard (2023 / SP 800-232)
- 🔒 Single-pass **encryption + authentication** (AEAD)
- 📉 Very small hardware footprint — ideal for embedded / IoT / biomedical devices

### ASCON-128 parameters

| Key | Nonce | Associated Data | Tag | Frame size | UART baud |
|-----|-------|------------------|-----|------------|-----------|
| 128 bits | 128 bits | 64 bits | 128 bits | 181 bytes | 115 200 |

---

## 🏗️ Architecture

### Hardware (FPGA PynqZ2)

The `ascon_top` module is the top-level design integrating UART, BRAM, the ASCON-128 core and three FSMs:

```
ascon_top
├── uart_core      → UART RX/TX physical layer
├── fsm_uart       → UART command decoder (7-command protocol, ~60 states)
├── BRAM (dual-port)
│     ├── addr 0–22   : ECG waveform (23 × 64-bit words)
│     ├── addr 32–54  : ciphertext (23 × 64-bit words)
│     └── addr 55–56  : authentication tag (128 bits)
├── drive_ascon    → 4-phase ASCON sequencer (init / assoc. data / cipher / finalization)
└── ascon          → ASCON-128 core (fsm_moore + Permutation datapath, p¹² / p⁶ rounds)
```

| Signal | Description |
|---|---|
| `clock_i` | System clock |
| `reset_i` | Synchronous reset |
| `Rx_i` / `Tx_o` | UART RX / TX |
| `Baud_i[2:0]` / `Baud_o[2:0]` | Baud rate selection |
| `RTS_o` | Ready To Send |

### Software (PC side)

```
project/
├── main.py              # Entry point: orchestration, plotting, NeuroKit2 reporting
├── iacq.py               # IACQ class: UART/serial interface, ASCON encryption cycle
├── fpga_emulator.py       # Software FPGA emulator (no hardware required)
├── ascon_pcsn.py          # Pure-Python reference implementation of ASCON-128 AEAD
├── visualization.py       # Real-time plotting + PQRST/HRV analysis (NeuroKit2)
├── demo_ascon.py          # Standalone ASCON encrypt/decrypt demo
├── utils.py               # Logger configuration
├── exceptions.py          # Custom exception hierarchy
├── requirements.txt
└── data/
    └── xNorm.csv          # Sample ECG frames
```

---

## ⚙️ UART Protocol — 7 Commands

Every command is acknowledged by the FPGA with `OK\n` (`4F 4B 0A`).

| Cmd | Hex | Size | Role |
|-----|-----|------|------|
| `K` | `0x4B` | 16 bytes | Secret ASCON-128 key |
| `N` | `0x4E` | 16 bytes | Nonce (unique per frame) |
| `A` | `0x41` | 8 bytes | Associated data (`b"A to B"` + padding) |
| `W` | `0x57` | 184 bytes | ECG frame (181 bytes + padding `0x800000`) |
| `G` | `0x47` | – | Trigger encryption |
| `C` | `0x43` | 187 bytes | Read ciphertext |
| `T` | `0x54` | 19 bytes | Read authentication tag |

**Frame flow:** `K → N → A → W → G → T → C` then `decrypted == original` validation on the host.

---

## 🚀 Getting Started

### Prerequisites

- PynqZ2 board flashed with the ASCON-128 bitstream, connected via USB/UART
- Python 3.10+
- Vivado 2025.x (only needed to regenerate/program the bitstream)
- Decompressed project archive (all `.py` files + `data/xNorm.csv`)

### 1. Set up the Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

| Package | Min. version | Purpose |
|---|---|---|
| numpy | 1.26 | Numerical computation (RR statistics) |
| pandas | 2.0 | CSV loading and data handling |
| scipy | 1.11 | Butterworth HPF/LPF filters |
| neurokit2 | 0.2.10 | ECG analysis (PQRST, HRV) |
| matplotlib | 3.7 | Real-time visualization |
| pytest | 7.0 | Unit tests |

> If you use real hardware, also install `pyserial`:
> ```bash
> pip install pyserial
> ```

Verify the install:

```bash
python -c "import numpy, pandas, scipy, neurokit2, matplotlib; print('OK')"
```

### 2. Program the FPGA

1. Open the Vivado project (`.xpr`) in Vivado 2025.x. If no bitstream exists, generate it via **Flow → Generate Bitstream**.
2. Connect the PynqZ2 board (USB-UART + power).
3. In Vivado: **Open Hardware Manager → Open Target → Auto Connect → Program Device** and select the `.bit` file.
4. After programming, the **DONE** LED turns on. Default UART baud rate is **115 200**, configurable via the on-board buttons. Keep reset inactive for the whole session.

### 3. Identify the serial port

```bash
# Linux
ls /dev/ttyUSB*
# macOS
ls /dev/tty.usb*
# Windows: Device Manager → Ports (COM & LPT)
```

---

## ▶️ Running the Project

### Emulator mode (no FPGA required)

```bash
python main.py --emulator
```

### Real FPGA mode

```bash
python main.py --port COM4              # Windows
python main.py --port /dev/ttyUSB0      # Linux
python main.py --port /dev/tty.usbserial-XXXX  # macOS
```

### CLI options

| Option | Default | Description |
|---|---|---|
| `--port` | `COM4` | FPGA serial port |
| `--baud` | `115200` | UART baud rate |
| `--timeout` | `2` | Read timeout (seconds) |
| `--emulator` | – | Run with the software emulator, no hardware needed |
| `--trame-file` | `data/xNorm.csv` | CSV file containing ECG frames |
| `--no-plot` | – | Disable real-time plotting |

**Expected output:** for each frame, the terminal prints `[OK]` with the tag and BPM, while a live plot shows three curves: original (green), decrypted + PQRST (blue), and ciphertext (red).

---

## 📊 Results

- ✅ Bit-exact validation: `decrypted == original`
- ✅ ASCON-128 authentication tag verified (128 bits)
- ✅ ECG signal perfectly recovered after the round trip
- ✅ Example: **BPM = 69.0** (normal sinus rhythm), SDNN = 24.1 ms, RMSSD = 23.0 ms
- ✅ Encrypted signal is visually random — no information extractable without the key
- ✅ 7-command UART protocol validated by self-checking testbenches (0 failures)

---

## 🐛 Debugging Notes

A few hard-won lessons from FPGA simulation/integration:

| Issue | Symptom | Fix |
|---|---|---|
| `real`-typed UART delays under XSim | `Rx_i` appears stuck, `RXRdy_s = 0` | Use integer constants (e.g. `BIT_NS = 8960`) |
| Testbench clock at 50 MHz instead of 125 MHz | MMCM never locks, design frozen | Drive `clock_i` at 125 MHz in the TB |
| Stimulation before PLL lock | First commands lost | Wait 2000+ cycles after reset |
| Wrong waveform zoom level | False "Rx_i stuck" diagnosis | Zoom on console timestamps |
| BRAM output-register latency | Cipher/tag shifted by one word | Add one extra wait cycle in the FSM |

**Method:** correlate `$display` console output with the waveform viewer — the console shows what the testbench *believes* is happening, the waveform shows what the DUT *actually* does.

---

## 🔭 Roadmap / Future Work

- 🔌 Integration on the PynqZ2 with a physical ECG sensor
- ⚡ Pipelined ASCON datapath for higher throughput
- 📡 Continuous multi-frame transmission
- 🛡️ Side-channel security testing (DPA / SCA)
- ❤️ Extension to other biomedical sensors

---

## 📚 References

- C. Dobraunig, M. Eichlseder, F. Mendel, M. Schläffer, *Ascon v1.2 — Submission to NIST LWC*, 2021. ([ascon.iaik.tugraz.at](https://ascon.iaik.tugraz.at/))
- NIST SP 800-232, *Ascon-Based Lightweight Cryptography Standards for Constrained Devices*, Aug. 2025.
- NIST, *Lightweight Cryptography Standardization — Selection of Ascon*, Feb. 2023.
- TUL, *PYNQ-Z2 Reference Manual*, 2019.
- AMD/Xilinx, *Vivado Design Suite User Guides* (UG900, UG908), *Block Memory Generator* (PG058).
- D. Makowski et al., *NeuroKit2: A Python Toolbox for Neurophysiological Signal Processing*, Behavior Research Methods, 2021. ([GitHub](https://github.com/neuropsychology/NeuroKit))
- *pyserial* documentation — [pyserial.readthedocs.io](https://pyserial.readthedocs.io/)

---

## 👥 Authors

**Ali Ahnani** & **Khalid Elkoussami**
Supervisors: Jean-Baptiste Rigaud & Raphaël Viera
École des Mines de Saint-Étienne — Institut Mines-Télécom, 2025–2026
