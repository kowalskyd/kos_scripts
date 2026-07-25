# KAL-9000 Flight Software Suite (`kos-scripts`)

An autonomous guidance, navigation, and control (GNC) flight software suite written in kerboscript for the **kOS (Kerbal Operating System)** mod in **Kerbal Space Program (KSP)**.

The **KAL-9000** suite provides end-to-end mission automation—from launchpad liftoff and orbital insertion, to planetary transfers, pinpoint suicide burn landings, ground rover navigation, and autonomous 6-DOF rendezvous and docking.

---

## Table of Contents

- [Overview & Key Capabilities](#overview--key-capabilities)
- [System Architecture](#system-architecture)
- [Core Mission Controllers](#core-mission-controllers)
- [Library Deep Dive & Helper Modules](#library-deep-dive--helper-modules)
  - [KAL-9000 HUD & Telemetry (`lib/hud.ks`)](#kal-9000-hud--telemetry-libhudks)
  - [Orbital Mechanics & Maneuvers (`lib/mnv.ks`)](#orbital-mechanics--maneuvers-libmnvks)
  - [Autonomous Docking Guidance System (`lib/docking.ks`)](#autonomous-docking-guidance-system-libdockingks)
  - [Cinematic Camera Director (`lib/camera_director.ks`)](#cinematic-camera-director-libcamera_directorks)
  - [Pre-Flight Diagnostics Engine (`lib/diagnostics.ks`)](#pre-flight-diagnostics-engine-libdiagnosticsks)
  - [Automated Systems Deployment (`lib/system.ks`)](#automated-systems-deployment-libsystemks)
  - [Interplanetary Transfers (`lib/transfer.ks`)](#interplanetary-transfers-libtransferks)
  - [Surface Rover Guidance (`lib/rover.ks`)](#surface-rover-guidance-libroverks)
  - [Geostationary Orbits (`lib/geostationary.ks`)](#geostationary-orbits-libgeostationaryks)
  - [Utility & Vector Math (`lib/misc.ks`)](#utility--vector-math-libmiscks)
- [Bootloader & System Scripts](#bootloader--system-scripts)
- [Included Craft Specifications](#included-craft-specifications)
- [Installation & Usage](#installation--usage)

---

## Overview & Key Capabilities

- 🚀 **Automated Ascent & Gravity Turn**: Dynamic pitch program based on atmospheric density, target apoapsis, automatic staging, fairing ejection, and circularization burns.
- 🌕 **Complete Lunar Mission Profiles (Mun & Minmus)**: Fully automated end-to-end mission controllers performing orbital launch, plane alignment, transfer injection burns, capture, powered descent suicide landings, surface liftoff, and Kerbin re-entry.
- ⚓ **Autonomous 6-DOF Rendezvous & Docking v4**: Route planning with interactive port selection, relative velocity braking, approach corridor alignment, and RCS translational docking control.
- 🛬 **Terrain-Aware Suicide Burn & Landing**: Radar-based terrain tracking, deceleration distance calculation, dynamic throttle control, and touchdown mitigation.
- 🎥 **Cinematic Camera Director**: Integration with `kOS-StockCamera` addon for automated multi-angle shots during staging, maneuver burns, landings, and timewarp protection.
- 🖥️ **KAL-9000 HUD Interface**: Real-time 50x24 terminal GUI with telemetry, resource tracking, suicide burn gauge, pre-flight diagnostics checkmarks, and crew radio chatter logs.
- 🛡️ **G-Force & Acceleration Limiting**: Dynamic engine thrust limiting to respect structural limits (e.g. 3.0G max acceleration) during maneuvers.

---

## System Architecture

The codebase is organized into modular layers:

```
Script/
├── boot/                   # KSP VAB/SPH core bootloaders
│   ├── exploreBoot.ks
│   ├── ifeBoot.ks
│   ├── launch_boot.ks
│   └── rdvBoot.ks
├── sys/                    # Low-level system runners & archive sync
│   ├── AUTORUN.ks
│   ├── COPY.ks
│   └── DELAY.ks
├── lib/                    # Reusable GNC, math, HUD, and system libraries
│   ├── camera_director.ks  # Cinematic camera director
│   ├── diagnostics.ks      # Pre-flight health and budget verifier
│   ├── docking.ks          # 6-DOF docking and approach corridor system
│   ├── geostationary.ks    # Synchronous orbit calculations
│   ├── hud.ks              # KAL-9000 GUI, telemetry, and chatter log
│   ├── misc.ks             # Vector math and trigonometric utilities
│   ├── mnv.ks              # Hohmann transfers, node execution, G-limiting
│   ├── rover.ks            # PID ground steering and waypoint guidance
│   ├── system.ks           # Auto-deployer for fairings, antennas, solar panels
│   └── transfer.ks         # Interplanetary ejection and phase calculation
├── crafts/                 # KSP vessel definitions and metadata
│   ├── Space Station 01.craft
│   └── Transfer Capsule.craft
├── launch.ks               # Orbital launch orchestrator
├── mun.ks / mun*.ks        # Mun mission suite (Launch, Land, Mission, Return)
├── minmus.ks / minmus*.ks  # Minmus mission suite (Launch, Land, Mission, Return)
├── rendezvous.ks           # Standalone rendezvous controller
├── dock.ks                 # Docking execution controller
├── powereddescent.ks       # Standalone powered descent engine
├── explore.ks              # Planetary exploration suite
└── ife.ks                  # Interplanetary Far-space Exploration program
```

---

## Core Mission Controllers

| Script | Purpose & Description |
| :--- | :--- |
| **[`launch.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/launch.ks)** | Launches vessel to specified target orbit height and inclination. Manages countdown, gravity turn profile, automatic staging, fairing deployment, and apoapsis circularization. |
| **[`mun.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/mun.ks)** | Primary Mun mission master orchestrator. Sequentially executes launch, trans-lunar injection, lunar orbit insertion, landing, surface ascent, and return. |
| **`munLaunch.ks`** / **`munMission.ks`** / **`munLand.ks`** / **`munReturn.ks`** | Modular sub-orchestrators for individual phases of a Mun mission. |
| **[`minmus.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/minmus.ks)** | Primary Minmus mission orchestrator handling plane change burns, capture, landing, surface ascent, and trans-Kerbin return. |
| **`minmusLaunch.ks`** / **`minmusMission.ks`** / **`minmusLand.ks`** / **`minmusReturn.ks`** | Modular sub-orchestrators for individual phases of a Minmus mission. |
| **[`rendezvous.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/rendezvous.ks)** | Long-range orbital rendezvous controller. Aligns orbital planes, computes transfer orbit, matches phase angle, and performs terminal relative velocity kill near target. |
| **[`dock.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/dock.ks)** | Executes close-range 6-DOF docking operations using `lib/docking.ks`. |
| **[`powereddescent.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/powereddescent.ks)** | Standalone precision suicide burn controller for vacuum and atmospheric landings. |
| **[`explore.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/explore.ks)** | Automated planetary exploration program for unmanned/manned scientific probes. |
| **[`ife.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/ife.ks)** | Interplanetary Far-space Exploration flight controller. |

---

## Library Deep Dive & Helper Modules

### KAL-9000 HUD & Telemetry ([`lib/hud.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/hud.ks))

Provides a terminal-based text GUI designed for 50x24 character displays:
- **`initScreen(programName)`**: Formats layout with split telemetry, resource counters, and radio comms section.
- **`updateTelemetry(...)`**: Live telemetry renderer displaying altitude, orbital speed, apoapsis, periapsis, and ETA timers.
- **`updateLandingTelemetry(...)`**: Displays radar altitude ($AGL$), stop distance, throttle percentage, vertical/horizontal velocity, and a visual ASCII suicide burn gauge (`[████░░░░]`).
- **`updateResources()`**: Displays Liquid Fuel, Oxidizer, Monopropellant, Electric Charge, crew count, and pilot name.
- **`logChatter(sender, message)`**: Formats circular log chatter queue for mission comms.
- **`runDiagnostics(labels)`**: Displays animated pre-flight check list with green checkmarks (`✔`).

### Orbital Mechanics & Maneuvers ([`lib/mnv.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/mnv.ks))

Math engine for orbital calculations and burn execution:
- **`computeVelocity(per, apo, shipAlt)`**: Vis-viva velocity calculation at a specific orbital radius.
- **`hTrans(shipAlt, targetAlt)`**: Calculates $\Delta v$ required for a Hohmann transfer.
- **`goToFrom(targetAlt, fromAlt)`**: Creates a maneuver node at Apoapsis or Periapsis for altitude adjustment.
- **`exeMnv(deltaTime)`**: Autonomous maneuver node execution algorithm with automatic engine activation, G-force acceleration limiting (`mnvMaxG`), vector steering alignment, and throttle decay near burn termination.
- **`changeIncline(targetInc)`**: Calculates and creates maneuver nodes for ascending/descending node inclination changes.
- **`circAt(where)`**: Computes circularization maneuver at Apoapsis or Periapsis.

### Autonomous Docking Guidance System ([`lib/docking.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/docking.ks))

Full 6-DOF precision docking framework:
- **`selectPort(portList, vesselName)`**: Interactive terminal menu allowing manual or automatic port selection on target vessel.
- **Approach Corridor Math**: Computes relative position vectors, alignment offset boxes, and standoff waypoints.
- **RCS Translation Control**: Dynamic PID translation loops along X, Y, Z axes for soft docking alignment without consuming excessive monopropellant.
- **Obstacle Avoidance**: Automatically routes around target vessel geometry if docking port is on the far side or obscured.

### Cinematic Camera Director ([`lib/camera_director.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/camera_director.ks))

Automates camera cuts using `addons:camera` (falls back gracefully if not installed):
- **`playStagingScene(duration)`**: Automatically triggers wide dynamic camera angle when stage separation occurs.
- **`playLandingScene()`**: Positions camera below/beside vessel during powered descent landings.
- **Timewarp Safety**: Automatically locks camera to real-time smooth panning during high-speed on-rails timewarp.

### Pre-Flight Diagnostics Engine ([`lib/diagnostics.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/diagnostics.ks))

Comprehensive pre-launch vessel inspection:
- Verifies Electric Charge, Solar Panel presence, Parachutes, Heatshield Ablator, Antenna count, Landing Gear, RCS Thrusters, total $\Delta v$ budget, and launch Thrust-to-Weight Ratio ($TWR \ge 1.15$).

### Automated Systems Deployment ([`lib/system.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/system.ks))

Component deployment triggered by altitude/environment:
- **`deployFairing()`**: Ejects procedural fairings tagged `"fairing"`.
- **`deployAntenna(nameOfAntenna)`**: Deploys communications antennas tagged `"antenna"`.
- **`deployPanel()`**: Extends deployable solar panels.
- **`deploySystems()`**: Sets up trigger conditions (`altitude > body:atm:height + 500`) for automatic space deployment.

### Interplanetary Transfers ([`lib/transfer.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/transfer.ks))

Calculates ejection vectors, phase angles, and transfer burns for interplanetary target bodies.

### Surface Rover Guidance ([`lib/rover.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/rover.ks))

Autonomous ground rover controller with PID wheel steering, speed regulation, slope handling, waypoint driving, and roll/flip recovery.

### Geostationary Orbits ([`lib/geostationary.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/geostationary.ks))

Calculates exact semi-major axis and orbital period required for synchronous/geostationary orbits around any celestial body.

### Utility & Vector Math ([`lib/misc.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/misc.ks))

Vector cross/dot product helpers, angle normalization, and pitch/heading calculations.

---

## Bootloader & System Scripts

- **`boot/launch_boot.ks`**: Automatic boot script assigned to core in VAB. Loads archive scripts (`switch to 0.`) and launches `run launch.` on vessel load.
- **`boot/ifeBoot.ks`**, **`boot/exploreBoot.ks`**, **`boot/rdvBoot.ks`**: Mission-specific boot configurations.
- **`sys/AUTORUN.ks`**: Main boot entry point for automatic script execution.
- **`sys/COPY.ks`**: System utility to sync scripts from volume 0 (Archive) to local vessel core storage (Volume 1).

---

## Included Craft Specifications

The repository includes pre-built vessel craft files configured with KAL-9000 tags:
- **`Space Station 01`**: Modular orbital station equipped with standard docking ports and power arrays.
- **`Transfer Capsule`**: Crewed transfer vessel optimized for lunar/orbital transport.

---

## Installation & Usage

1. Copy the contents of this repository into your Kerbal Space Program installation directory:
   ```
   [KSP Root Directory]/Ships/Script/
   ```
2. Open KSP and build a vessel equipped with a **kOS Processor** unit.
3. (Optional) In the VAB/SPH, right-click the kOS module and select a boot script (e.g. `launch_boot.ks`).
4. Open the kOS terminal in-game and run desired commands:
   ```kerboscript
   // Launch to 80 km orbit
   run launch(80000).

   // Execute automated Mun mission
   run mun.

   // Perform autonomous docking to target
   run dock.
   ```
