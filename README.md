# 🔐 Access Control System Using AVR Assembly on ATmega328P

[![AVR Assembly](https://img.shields.io/badge/AVR-Assembly-orange.svg)](https://www.microchip.com/en-us/products/microcontrollers-and-microprocessors/8-bit-mcus/avr-mcus)
[![Microcontroller](https://img.shields.io/badge/ATmega328P-16MHz-blue.svg)](https://ww1.microchip.com/downloads/en/DeviceDoc/Atmel-7810-Automotive-Microcontrollers-ATmega328P_Datasheet.pdf)
[![Architecture](https://img.shields.io/badge/Architecture-Interrupt--Driven-green.svg)](https://github.com/Msindisi-Carlet101/access-control-avr)

> A secure, interrupt-driven access control system built with AVR assembly language featuring keypad authentication, servo-controlled locking, LED feedback, and 7-segment display—demonstrating embedded systems best practices without polling or software delays.

## 📋 Table of Contents
- [Project Overview](#project-overview)
- [Features](#features)
- [Hardware Components](#hardware-components)
- [System Architecture](#system-architecture)
- [State Machine](#state-machine)
- [Technical Implementation](#technical-implementation)
- [Performance & Results](#performance--results)
- [Installation & Setup](#installation--setup)
- [Usage Guide](#usage-guide)
- [Known Limitations](#known-limitations)
- [Future Improvements](#future-improvements)
- [Academic Context](#academic-context)
- [Author](#author)

## 🎯 Project Overview

This project implements a **fully functional access control system** on the ATmega328P microcontroller using pure AVR assembly language. Developed for the ELEN2021A Microprocessors course at the University of the Witwatersrand, the system demonstrates professional embedded systems engineering with:

- ✅ **Zero polling** - 100% interrupt-driven architecture
- ✅ **No software delays** - Hardware timers for all timing operations
- ✅ **State machine design** - Clean separation of system states
- ✅ **Hardware PWM** - Precise servo control via Timer1
- ✅ **Multi-peripheral coordination** - Keypad, buttons, LEDs, servo, and 7-segment display

### Default Access Code
**1234** (configurable via programming mode)

## ⭐ Features

### 🔑 Core Security Features
- **4-Digit PIN Authentication** - Keypad-based code entry system
- **Dynamic Code Programming** - Users can set custom access codes
- **Progressive Security Escalation**:
  - First wrong attempt → Error state (blue LED flash)
  - Second wrong attempt → Alarm state (red + blue LED flash)
- **Auto-Lock Timer** - System re-locks after 3 seconds of unlock
- **Manual Lock Button** - Immediate re-lock during unlock window
- **Alarm Reset** - Hold both buttons for 3 seconds to reset from alarm

### 🎨 Visual Feedback System
- **Red LED (PB5)** - Locked state / Alarm condition
- **Blue/Yellow LED (PB4)** - Error state / Alarm condition
- **Green LED (PB3)** - Unlocked state / Programming mode
- **7-Segment Display** - Real-time state and digit display:
  - `L` → Locked
  - `U` → Unlocked
  - `P` → Programming mode
  - `-` → Error state
  - `.` (blinking) → Alarm state
  - Digits `0-9` during code entry

### 🔧 Hardware Control
- **Servo Motor Lock Mechanism** - Three positions:
  - 0° - Locked
  - 90° - Half-open (reserved)
  - 180° - Fully unlocked
- **Matrix Keypad** - 8-key input (expandable to 4×4 matrix)
- **Dual Push Buttons** - Lock and programming controls

## 🔌 Hardware Components

### Pin Configuration

| Component | Pin | Port | Function |
|-----------|-----|------|----------|
| **Servo Motor** | D10 | PB2 (OC1B) | PWM-controlled lock mechanism |
| **Red LED** | D13 | PB5 | Locked/Alarm indicator |
| **Blue LED** | D12 | PB4 | Error/Alarm indicator |
| **Green LED** | D11 | PB3 | Unlocked/Programming indicator |
| **Lock Button** | A3 | PC0 | Manual lock trigger |
| **Mode Button** | A4 | PC1 | Programming mode entry |
| **Keypad (8 keys)** | D0-D7 | PORTD | 4-digit code input |
| **7-Seg Display** | Multiple | PORTC/PORTD | State visualization |

### 7-Segment Display Connections

**PORTC Segments:**
- A0 → Segment G
- A2 → Segment F
- A4 → Segment A
- A5 → Segment B

**PORTD Segments:**
- D1 → Segment E
- D2 → Segment C
- D4 → Segment D
- D0 → Decimal Point

### Bill of Materials
- 1× ATmega328P microcontroller (Arduino Uno compatible)
- 1× SG90 Servo motor (or equivalent)
- 3× LEDs (Red, Blue/Yellow, Green) + 220Ω resistors
- 1× 4×4 Matrix keypad (or 8 individual buttons)
- 2× Push buttons + 10kΩ pull-down resistors
- 1× Common cathode 7-segment display
- Breadboard and jumper wires
- 5V power supply

## 🏗️ System Architecture

### Interrupt-Driven Design Philosophy

**Why Interrupts Over Polling?**
- ⚡ **Instant response** to user input (< 1ms latency)
- 🔋 **Power efficient** - CPU sleeps between events
- 🎯 **Deterministic timing** - No missed inputs
- 🧵 **Non-blocking** - Multiple tasks execute concurrently

### Timer Configuration

#### Timer1 (16-bit) - Servo Control
```assembly
