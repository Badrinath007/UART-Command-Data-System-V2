# UART-based Command and Data Communication System (V2)📌 

## Project Overview
This project implements a "Production-Grade" UART communication system in Verilog/SystemVerilog. Unlike basic bit-shifters, this system includes a Control Finite State Machine (FSM) that acts as a protocol parser, enabling secure and reliable Command and Data exchange between a PC (or MCU) and an FPGA.

## V2 Key Upgrades
Buffered Communication: 
- Integrated 16-deep Synchronous FIFOs to manage data bursts and prevent data loss during high-speed transmission.Data Integrity:
- Hardware-level Checksum validation blocks corrupt packets from affecting internal registers.
- Advanced Verification: A self-checking testbench with a Shadow-Register Sentry to ensure 100% RTL-to-Simulation matching.

## Specifications:
- Baud Rate: 115,200 bps (Configurable).
- Clock Frequency: 50 MHz.
- Oversampling: 16x oversampling for robust edge detection.
- Protocol Frame: [Sync Byte: 0x55] [Command] [Data] [Checksum].
- Logic Footprint: 108 ALMs.
- Internal Memory: 256 Block bits (mapped to M10K/M20K).

## Architecture:
The system follows a modular architecture divided into the Physical Layer (UART), the Buffer Layer (FIFO), and the Protocol Layer (FSM).UART PHY: Handles 16x oversampling and bit-level synchronization.
- FIFO Buffers: Acts as the bridge between the asynchronous UART clock domain and the synchronous FSM processing.
- Register File: A dedicated 8-bit register (reg_file) that only updates upon a valid packet reception.

## Microarchitecture (Protocol FSM):
The "Internal Brain" is a 4-state Moore Machine that ensures strictly ordered processing:
- ST_IDLE (00): Waits for the Sync Byte (0x55).ST_CMD (01): Captures the command byte and stores it in a temporary hold register.
- ST_DATA (10): Captures the payload data.
- ST_CHKSUM (11): Calculates CMD + DATA and compares it to the incoming checksum.If Match: The reg_file is updated, and FSM returns to IDLE.If Mismatch: The error_led triggers, and the packet is discarded.

## Hardware Resource Utilization (Synthesis Report)
- ResourceUsageLogic Utilization (ALMs):108
- Dedicated Logic Registers150
- Total Block Memory Bits256
- Maximum Fan-out Nodeclk~input (166)

## Verification & Results:
The design was verified using a SystemVerilog testbench.
Test Case: Checksum RejectionWhen a packet with an invalid checksum is sent, the error_led goes high, but the reg_file remains locked at its previous value (e.g., A5), preventing corruption.
## How to RunSynthesis: 
Open the Quartus Project and run "Analysis & Synthesis.
"Simulation: * Launch ModelSim.Compile files in /RTL.Load /TB/uart_fifo_tb.sv.
Run the simulation for 3ms to see the full test suite results.

## Initial Design and testing phase and tools used:
- Used WSL ubuntu 20.04LTS with icarus verilog+gtkwave+yosys to code rtl,simulate and synthesis.
- Used shell script to automate compilation and waveform generation.

## Industry Standard tool usage and testing phase:

- Used quatrus prime 18.1 Lite edition along with modelsim.
- Used VS code for implementing verification such as functional verification,assertion based verification and formal verification.

# Note:
Check modelsim.txt file for simulation-related commands.
