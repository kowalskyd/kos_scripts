# KAL-9000 Flight Software Suite (`kos-scripts`)

An autonomous guidance, navigation, and control (GNC) flight software suite written in kerboscript for the **kOS (Kerbal Operating System)** mod in **Kerbal Space Program (KSP)**.

The **KAL-9000** suite provides end-to-end mission automation—from launchpad liftoff and orbital insertion, to lunar transfers, terrain-aware suicide burn landings, autonomous 6-DOF rendezvous and docking, ROS 2 Nav2 autonomous rover exploration, and passenger in-flight entertainment displays.

---

## Video Demonstration

[![KAL-9000 Mission Demonstration](https://img.youtube.com/vi/H44tpVnJ75o/0.jpg)](https://www.youtube.com/watch?v=H44tpVnJ75o&feature=youtu.be)

*Watch the KAL-9000 flight software suite in action across planetary missions, autonomous landings, and ROS 2 rover autonav exploration.*

---

## Table of Contents

- [Video Demonstration](#video-demonstration)
- [Overview & Technical Capabilities](#overview--technical-capabilities)
- [System Architecture](#system-architecture)
- [Core Mission Controllers & Sequencers](#core-mission-controllers--sequencers)
  - [Orbital Launch (`launch.ks`)](#orbital-launch-launchks)
  - [Automated Mun Mission Suite (`munMission.ks`, `mun.ks`, `munLand.ks`, `munLaunch.ks`, `munReturn.ks`)](#automated-mun-mission-suite-munmissionks-munks-munlandks-munlaunchks-munreturnks)
  - [Automated Minmus Mission Suite (`minmusMission.ks`, `minmus.ks`, `minmusLand.ks`, `minmusLaunch.ks`, `minmusReturn.ks`)](#automated-minmus-mission-suite-minmusmissionks-minmusks-minmuslandks-minmuslaunchks-minmusreturnks)
  - [Orbital Rendezvous (`rendezvous.ks`) & Docking (`dock.ks`)](#orbital-rendezvous-rendezvousks--docking-dockks)
  - [Booster Powered Descent & KSC Landing (`powereddescent.ks`)](#booster-powered-descent--ksc-landing-powereddescentks)
  - [ROS 2 Autonomous Rover Exploration (`ros_explore.ks`)](#ros-2-autonomous-rover-exploration-ros_exploreks)
  - [In-Flight Entertainment System (`ife.ks`)](#in-flight-entertainment-system-ifeks)
- [Library Deep Dive & GNC Modules](#library-deep-dive--gnc-modules)
  - [KAL-9000 Telemetry & Terminal HUD (`lib/hud.ks`)](#kal-9000-telemetry--terminal-hud-libhudks)
  - [ROS 2 Nav2 Autonav Engine (`lib/ros_nav2.ks`)](#ros-2-nav2-autonav-engine-libros_nav2ks)
  - [Orbital Mechanics Engine (`lib/mnv.ks`)](#orbital-mechanics-engine-libmnvks)
  - [Autonomous Docking Guidance System (`lib/docking.ks`)](#autonomous-docking-guidance-system-libdockingks)
  - [Cinematic Camera Director (`lib/camera_director.ks`)](#cinematic-camera-director-libcamera_directorks)
  - [Pre-Flight Diagnostics Engine (`lib/diagnostics.ks`)](#pre-flight-diagnostics-engine-libdiagnosticsks)
  - [Systems Deployment Manager (`lib/system.ks`)](#systems-deployment-manager-libsystemks)
  - [Interplanetary Transfers (`lib/transfer.ks`)](#interplanetary-transfers-libtransferks)
  - [Surface Rover Support Library (`lib/rover.ks`)](#surface-rover-support-library-libroverks)
  - [Geostationary Orbit Mechanics (`lib/geostationary.ks`)](#geostationary-orbit-mechanics-libgeostationaryks)
  - [Math & Vector Utilities (`lib/misc.ks`)](#math--vector-utilities-libmiscks)
- [Bootloader & Low-Level System Scripts](#bootloader--low-level-system-scripts)
- [Included Craft Specifications](#included-craft-specifications)
- [Installation & Usage](#installation--usage)

---

## Overview & Technical Capabilities

- **Mathematical Gravity Turn Ascent**: Atmospheric pitch guidance program scaling from 90 degrees at 1,000 m to 10 degrees at 60,000 m using a exponential altitude function, with automatic flameout detection and booster separation.
- **Vis-Viva Circularization Engine**: Analytic orbital insertion calculations computing required delta-v directly from gravitational parameter $\mu$, semi-major axis, and apoapsis radius.
- **End-to-End Lunar Sequencers**: 5-phase master state machines (`munMission.ks` and `minmusMission.ks`) that coordinate launch, transfer injection, orbital capture, daylight-aware deorbit burns, suicide burn landings, lunar surface ascent, and atmospheric re-entry.
- **Suicide Burn & Landing Control**: Real-time stopping distance calculation ($d = \frac{v^2}{2(a - g)}$) compared against radar altitude above ground level ($AGL$), featuring automatic landing site darkness checks to delay deorbit burns into daylight.
- **Booster Recovery & Pad Targeting**: Trajectory bisection algorithms (`getEntryTime`) predicting entry interface positions with planetary rotation corrections, retro-propulsion, and aerodynamic steering to land first-stage boosters back at the KSC Launchpad.
- **6-DOF Autonomous Docking**: Interactive port selection, standoff approach corridor box alignment, relative velocity dampening, and 3-axis RCS translation control loops.
- **ROS 2 Nav2 Autonomous Rover Exploration**: 4-tier Layered Perception & Navigation Pyramid incorporating DWA local path planning, 3D surface normal gradient vectors ($\vec{N}$), SCANsat orbital DEM pre-filtering, 35m LaserDist raycasting, dynamic gravity scaling, Bug2 barrier perimeter escape, and unreachability sector blacklisting.
- **Dynamic Camera Automation**: Integration with `kOS-StockCamera` to execute cinematic multi-cut sequence transitions on staging events, maneuver burns, landings, and timewarp safety locks.
- **Dual-Processor Support & IFE**: Terminal GUI supporting 50x24 split-screen telemetry and chatter logs on primary flight computers, paired with a dedicated In-Flight Entertainment (`ife.ks`) system featuring live ASCII orbital radar maps for secondary processors.

---

## System Architecture

```text
Script/
├── boot/                   # KSP VAB/SPH core bootloaders
│   ├── exploreBoot.ks      # Bootloader for rover exploration missions
│   ├── ifeBoot.ks          # Bootloader for passenger IFE processor
│   ├── launch_boot.ks      # Primary launch bootloader (autoruns launch.ks)
│   └── rdvBoot.ks          # Bootloader for rendezvous operations
├── sys/                    # Low-level system runners & archive sync
│   ├── AUTORUN.ks          # Main boot entry point for core logic
│   ├── COPY.ks             # Volume 0 (Archive) to Volume 1 (Local Core) sync
│   └── DELAY.ks            # Execution delay helper
├── lib/                    # Reusable GNC, math, HUD, and system libraries
│   ├── camera_director.ks  # Multi-cut cinematic camera director addon interface
│   ├── diagnostics.ks      # Pre-flight health, resource budget, and TWR inspector
│   ├── docking.ks          # 6-DOF docking corridor & relative velocity guidance
│   ├── geostationary.ks    # Geosynchronous altitude and period math
│   ├── hud.ks              # KAL-9000 50x24 terminal UI, telemetry, and chatter log
│   ├── misc.ks             # List min/max and utility functions
│   ├── mnv.ks              # Vis-viva math, maneuver node execution, G-limiting
│   ├── ros_nav2.ks         # ROS 2 Nav2 Costmaps, DWA Planner, Surface Normal Engine & Blacklisting
│   ├── rover.ks            # Ground rover power management, point turns, and science
│   ├── system.ks           # Auto-deployer for fairings, antennas, solar panels
│   └── transfer.ks         # Phase angle, synodic period, and ejection math
├── crafts/                 # KSP vessel definitions
│   └── Auto-Saved Ship.craft # Primary flight-ready vessel configuration
├── launch.ks               # Master ascent and orbit insertion controller
├── mun.ks                  # Standalone Mun transfer and capture controller
├── munLaunch.ks            # Mun surface liftoff and orbit circularization
├── munMission.ks           # Master end-to-end Mun mission orchestrator
├── munLand.ks              # Daylight-checked Mun deorbit and suicide burn landing
├── munReturn.ks            # Trans-Kerbin injection and parachute re-entry
├── minmus.ks               # Minmus transfer and capture controller
├── minmusLaunch.ks         # Minmus surface liftoff and circularization
├── minmusMission.ks        # Master end-to-end Minmus mission orchestrator
├── minmusLand.ks           # Minmus deorbit and soft landing controller
├── minmusReturn.ks         # Minmus return and Kerbin re-entry controller
├── rendezvous.ks           # Long-range phase angle matching and velocity kill
├── dock.ks                 # Target acquisition and 6-DOF docking driver
├── powereddescent.ks       # KSC booster return, boostback, and pad landing
├── ros_explore.ks          # ROS 2 Nav2 Autonomous Frontier Exploration Controller (Primary)
├── explore.ks              # Legacy waypoint rover explorer
└── ife.ks                  # Dual-processor passenger In-Flight Entertainment
```

---

## Core Mission Controllers & Sequencers

### Orbital Launch (`launch.ks`)

The primary launch controller automates countdown, liftoff, gravity turn, staging, fairing ejection, and orbital insertion:
- **Target Orbit**: Default 120,000 m (configurable via `TARGET_ALT`).
- **Gravity Turn Math**: Smooth mathematical curve executing pitch program between 1,000 m and 60,000 m:
  $$\text{pitch} = 90 - 80 \times \left(\frac{\text{altitude} - 1000}{59000}\right)^{0.35}$$
- **Smart Staging Engine**: Monitors `eng:flameout` on active engines. Drops exhausted boosters, waits 1.5 seconds for stage clearance, and re-asserts top module command authority (`P:CONTROLFROM()`).
- **Vis-Viva Circularization**: At target apoapsis, computes exact velocity difference:
  $$v_{\text{ap}} = \sqrt{\mu \left(\frac{2}{r_{\text{ap}}} - \frac{1}{a}\right)}, \quad v_{\text{circ}} = \sqrt{\frac{\mu}{r_{\text{ap}}}}, \quad \Delta v = v_{\text{circ}} - v_{\text{ap}}$$
  Creates a maneuver node at `time + eta:apoapsis` and executes burn via `exeMnv()`.

### Automated Mun Mission Suite (`munMission.ks`, `mun.ks`, `munLand.ks`, `munLaunch.ks`, `munReturn.ks`)

- **`munMission.ks`**: Master 5-step sequencer that runs pre-flight diagnostics, executes `launch.ks`, initiates `mun.ks` transfer, performs `munLand.ks` touchdown, executes `munLaunch.ks` ascent, and completes `munReturn.ks` re-entry.
- **`mun.ks`**: Computes phase angle to Mun, plans Hohmann transfer node via `transferToBody()`, executes mid-course periapsis adjustment (`setNewPeriapsis(35000, 120)`), warps to SOI transition, and performs Mun orbit capture burn.
- **`munLand.ks`**: Performs pre-landing diagnostic check (`runDiagnostics`). Calculates lander TWR on Mun. Checks if the planned periapsis landing site is on the dark side of Mun using vector angles ($\arccos(\vec{v}_{\text{sun}} \cdot \vec{r}_{\text{pe}}) > 90^\circ$); if dark, automatically delays deorbit burn by half an orbit to guarantee touchdown in daylight. Calculates suicide burn stopping distance:
  $$d_{\text{stop}} = \frac{v^2}{2 (a - g)}$$
  Controls landing throttle continuously until touchdown.
- **`munLaunch.ks`**: Controls surface liftoff from Mun, executes 45-degree pitch ascent to 15 km apoapsis, and performs circularization burn.
- **`munReturn.ks`**: Calculates escape burn node for Trans-Kerbin Injection (TKI), sets Kerbin periapsis to 30 km for aerocapture, separates descent capsule from service module, arms parachutes, and manages touchdown.

### Automated Minmus Mission Suite (`minmusMission.ks`, `minmus.ks`, `minmusLand.ks`, `minmusLaunch.ks`, `minmusReturn.ks`)

Provides complete mission automation for Minmus, incorporating relative inclination matching at the ascending/descending nodes prior to transfer injection, low-gravity soft landing control, surface ascent, and Kerbin return.

### Orbital Rendezvous (`rendezvous.ks`) & Docking (`dock.ks`)

- **`rendezvous.ks`**: Designed for intercepting targets in lower or higher orbits. Aligns orbital planes, computes target phase angle $\Delta \theta$, warps to the transfer window, adds transfer maneuver node, iteratively fine-tunes node execution time to achieve relative intercept distances below 1,000 m, and matches target velocity at closest approach.
- **`dock.ks`**: Passes target vessel to `dockToTarget()` in `lib/docking.ks`.

### Booster Powered Descent & KSC Landing (`powereddescent.ks`)

Automates boostback, atmospheric re-entry, and precision landing of reusable first-stage boosters back at the KSC Launchpad (`latlng(-0.1027, -74.5753)`):
- Uses binary bisection search (`getEntryTime`) over trajectory positions to calculate entry interface time.
- Corrects entry coordinates for planetary rotation rate ($\omega = \frac{360^\circ}{T_{\text{rot}}}$).
- Performs boostback burn to align predicted impact site with KSC coordinates.
- Guides aerodynamic orientation during re-entry and triggers terminal suicide burn.

### ROS 2 Autonomous Rover Exploration (`ros_explore.ks`)

Primary ground exploration program implementing a 4-tier Layered Perception & Navigation Pyramid based on ROS 2 Nav2 standards:
- **ROS 2 Nav2 Local Costmap & DWA Planner**: Computes 35m 2D local occupancy costmaps (`rosSampleCostmap`) using Dynamic Window Approach (DWA) candidate corridor evaluations (`rosCalculateDwaPath`) to dynamically bypass terrain hazards.
- **Surface Normal Gradient Engine ($\vec{N}$)**: Calculates 3D surface normals via cross-product elevation sampling to classify positive climbable ridges (`/`), steep impassable walls (`^`), and true cliff drop-offs (`!`).
- **Dynamic Surface Gravity Scaling**: Speeds and wheel throttle limits automatically scale based on local surface gravity ($g_{surface}$), capping cruise speeds on low-gravity bodies (Mun/Minmus) to $1.5 - 2.0\text{ m/s}$ with proportional throttle and zero-lock engine braking to eliminate wheelspin and skidding.
- **Layered Perception & SCANsat Pre-Filtering**: Integrates orbital SCANsat DEM maps to pre-blacklist liquid oceans (`terrainheight <= 5.0m`) and steep mountain ranges before driving begins. Gracefully degrades to native kOS local DEM probing if satellite coverage is unmapped.
- **Unreachability Blacklisting & Bug2 Barrier Escape**: Automatically blacklists stagnant or unreachable sector keys (`rosBlacklistedSectors`). When encountering extended coastlines or crater walls, executes a $180^\circ$ turn and a 150m Inland Escape Drive (`rosEscapeInland`) away from the barrier.
- **2D Global Frontier Map Telemetry**: Real-time 30-row un-truncated HUD displaying 35m local costmap radar and a regional 1.0km x 1.0km 2D Occupancy Grid plotting Rover (`@`), Active Target (`O`), Visited Sectors (`X`), and Blacklisted Barriers (`!`).

### In-Flight Entertainment System (`ife.ks`)

A standalone display system designed for secondary kOS processors on crewed vessels:
- **Screen 1 (Passenger Tracker)**: Displays MET, current SOI, orbital velocity, altitude, destination guide, target distance, destination weather/atmosphere summary, cabin pressure, and snack bar inventory.
- **Screen 2 (Live 2D Orbital Radar Map)**: Real-time ASCII radar view plotting central body, target orbit ring, vessel position, and velocity vector.
- **Screen 3 (Orbit Visualizer)**: Animated ASCII rendering of celestial bodies and orbital inclination projections.

---

## Library Deep Dive & GNC Modules

### KAL-9000 Telemetry & Terminal HUD ([`lib/hud.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/hud.ks))

Provides a terminal GUI framework tailored for standard 50x24 kOS character terminals:
- `initScreen(programName)`: Clears screen, draws outer structural border, title banner, telemetry split divider, and radio communications panel.
- `updateTelemetry(vesselSpeed, altReal, ap, pe, etaAp, etaPe)`: Renders altitude, orbital speed, apoapsis, periapsis, and ETA timers on the left pane, and triggers `updateResources()` on the right pane.
- `updateLandingTelemetry(phaseName, radarAlt, stopDist, throttleVal, vSpd, hSpd)`: Displays landing phase, radar altitude ($AGL$), stopping distance, throttle percentage, vertical/horizontal velocity, and an ASCII suicide burn bar gauge (`[████░░░░]`).
- `updateResources()`: Reads liquid fuel, oxidizer, monopropellant, electric charge, crew count, and active pilot name.
- `logChatter(sender, message)`: Pushes radio chatter into a 6-row circular buffer display at the bottom of the terminal screen.
- `runDiagnostics(labels)`: Renders pre-flight system check list with step-by-step validation status indicators.

### ROS 2 Nav2 Autonav Engine ([`lib/ros_nav2.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/ros_nav2.ks))

The GNC navigation engine for autonomous mobile robotics:
- `rosGetSurfaceG()` & `rosGetDynamicMaxSpeed()`: Calculates local surface gravity $g_{surface}$ and scales safe cruising speed cap $\text{safeSpd} = \max(1.5, \min(v_{\text{base}}, v_{\text{base}} \sqrt{g_{ratio}}))$ and wheel throttle limit $\text{maxThrottle} = \min(1.0, \max(0.12, 0.45 g_{ratio}))$.
- `rosGetTerrainNormalAndGradient()`: Computes 3D terrain surface normals ($\vec{N}$) and steepest gradient direction.
- `rosSampleCostmap(forwardSpan, sideSpan)`: Probes a 5x5 35m local grid, classifying terrain cells into `CLEAR`, `CLIMBABLE_RIDGE`, `STEEP_RIDGE`, `NEGATIVE_DROP`, or `PHYSICAL_OBSTACLE` (gated LaserDist range $< 35\text{m}$).
- `rosCalculateDwaPath(targetGeo, costmap)`: Evaluates DWA corridor heading offsets ($0^\circ, \pm 15^\circ, \pm 30^\circ$), applying perpendicular alignment penalties near ridges.
- `rosSelectFrontierTarget(currentGeo, scanRadius)`: Generates candidate frontiers using a 3-point line probe to filter out water intersections, ranking frontiers by information gain score $S = 1000 - \text{VisitedPenalty} - (\text{MacroSlope} \times 25)$.
- `rosBlacklistSector(key, reason)` & `rosEscapeInland(escapeDist)`: Logs unnavigable sector keys to `rosBlacklistedSectors` and executes 150m inland escape maneuvers on barrier aborts.
- `rosUpdateTelemetry(targetGeo, statusMsg)` & `rosRenderGlobalFrontierMap()`: Renders un-truncated 50-char terminal HUD and 2D Global Frontier Occupancy Map.

### Orbital Mechanics Engine ([`lib/mnv.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/mnv.ks))

Core GNC math engine for maneuver calculation and execution:
- `computeVelocity(per, apo, shipAlt)`: Calculates orbital speed using the Vis-Viva equation:
  $$v = \sqrt{\mu \left(\frac{2}{r} - \frac{1}{a}\right)}$$
- `hTrans(shipAlt, targetAlt)`: Computes transfer $\Delta v$ between two circular coaxial orbits.
- `goToFrom(targetAlt, fromAlt)`: Generates maneuver node at apoapsis or periapsis to modify opposite apsis to `targetAlt`.
- `exeMnv(deltaTime)`: Autonomous node execution routine:
  - Dynamically calculates engine acceleration ($a = \frac{F_{\text{max}}}{m}$).
  - Computes max acceleration limits based on structure constraint `mnvMaxG` (default 3.0 G). Adjusts engine `thrustlimit` slider on active engines to prevent structural overload.
  - Aligns attitude vector to node burn vector (`node:deltav`).
  - Executes burn with precise throttle throttling near burn completion ($\Delta v < 5\text{ m/s}$) to prevent overshooting.
- `changeIncline(targetInc)`: Computes inclination change node at ascending or descending nodes.
- `circAt(where)`: Computes circularization maneuver node at apoapsis or periapsis.

### Autonomous Docking Guidance System ([`lib/docking.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/docking.ks))

Full 6-DOF precision docking framework:
- `selectPort(portList, vesselName)`: Renders terminal menu displaying available docking ports on target vessel, node types, and custom part tags (`tag`).
- **Approach Corridor Guidance**: Establishes standoff offset point 20 meters directly along target port facing vector.
- **RCS Translational PID Control**: Translates along relative X, Y, Z axes to maintain alignment inside the approach corridor while dampening transverse relative speed.
- **Obstacle Avoidance**: Automatically routes around target vessel geometry if selected port is positioned on an obscured face.

### Cinematic Camera Director ([`lib/camera_director.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/camera_director.ks))

Interoperates with `addons:camera` (kOS-StockCamera) to automate camera cuts:
- `playLaunchScene()`, `playLiftoffScene()`, `playStagingScene()`: Executes dramatic wide pans, ground view tracking, and staging separation shots.
- `playLandingScene()`: Positions camera below lander during suicide burns.
- **Timewarp Protection**: Locks camera during on-rails timewarp ($>1\times$) to prevent rapid camera rotation or flickering.

### Pre-Flight Diagnostics Engine ([`lib/diagnostics.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/diagnostics.ks))

Validates vessel health prior to launch:
- Inspects Electric Charge ($\ge 200$), Solar Panel presence, Parachute counts, Heatshield Ablator ($\ge 100$), Antenna count, Landing Gear, RCS Thrusters, total vessel $\Delta v$ budget ($\ge 5,500\text{ m/s}$), and sea-level launch $TWR \ge 1.15$.

### Systems Deployment Manager ([`lib/system.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/system.ks))

Automated part deployment based on vessel tags and flight triggers:
- `deployFairing()`: Triggers `ModuleProceduralFairing` on parts tagged `"fairing"`.
- `deployAntenna(nameOfAntenna)`: Triggers `ModuleDeployableAntenna` on parts tagged `"antenna"`.
- `deployPanel()`: Extends all vessel solar panels (`panels on`).
- `deploySystems()`: Arms background altitude trigger (`altitude > body:atm:height + 500`) to execute fairing, antenna, and panel deployment automatically upon exiting atmosphere.

### Interplanetary Transfers ([`lib/transfer.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/transfer.ks))

Calculates interplanetary transfer windows and ejection burns:
- `computeTargetAngle(targetBody)`: Computes required phase angle using semi-major axis of transfer orbit.
- `computePhaseAngle(targetBody)`: Determines true anomaly difference between vessel and target body relative to longitude of ascending node.
- `transferToBody(targetBody, doWarp)`: Calculates synodic period $T_{\text{syn}} = \frac{T_1 T_2}{T_2 - T_1}$, warps to transfer window, adds maneuver node, and executes ejection burn.

### Surface Rover Support Library ([`lib/rover.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/rover.ks))

Ground rover support and utility library:
- `executePointTurn(targetHDG)`: Gravity-scaled zero-speed point turns with pre-turn speed reduction to $<1.0\text{ m/s}$ and in-turn speed limiting to prevent overspeeding on Mun/Minmus.
- `handleAirborne()`: Monitors flight status when airborne; uses SAS reaction wheel torque to level pitch and roll parallel to the horizon for safe 4-wheel landings.
- `recoverFromFlip()`: Detects vessel rollovers ($>45^\circ$ tilt) and applies reaction wheel torque impulses to auto-upright the rover back onto its wheels.
- `waitForSunlight()` & `waitForFullEC()`: Suspends operations during lunar night or low battery with zero-power hibernation, keeping the ROS 2 Autonav HUD and 2D Global Frontier Map active on screen.
- `runScienceExperiments()`: Deploys all active `ModuleScienceExperiment` parts, transmits data over radio link, transfers data into `ModuleScienceContainer`, and resets sensors for repeat use.

### Geostationary Orbit Mechanics ([`lib/geostationary.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/geostationary.ks))

- `geoAltitude(nameOfBody)`: Computes synchronous orbit altitude:
  $$r_{\text{sync}} = \left(\frac{G M T_{\text{rot}}^2}{4 \pi^2}\right)^{1/3} - R_{\text{body}}$$
- `geoVelocity(nameOfBody)`: Computes synchronous orbital velocity.
- `geoPhase(nameOfBody, phase)`: Computes phasing orbit semi-major axis for resonant satellite constellation deployment.

### Math & Vector Utilities ([`lib/misc.ks`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/lib/misc.ks))

Provides `minOf(newList)` and `maxOf(newList)` list search functions.

---

## Bootloader & Low-Level System Scripts

- **`boot/launch_boot.ks`**: Assigned to kOS core in VAB. Waits 2 seconds, switches volume to Archive (`switch to 0.`), and runs `launch.ks`.
- **`boot/exploreBoot.ks`**, **`boot/ifeBoot.ks`**, **`boot/rdvBoot.ks`**: Core bootloaders for rover, IFE, and rendezvous vessels.
- **`sys/AUTORUN.ks`**: Main boot execution router.
- **`sys/COPY.ks`**: Copies mission scripts from Volume 0 (Archive) to Volume 1 (Local Core Storage) for offline execution outside antenna range.
- **`sys/DELAY.ks`**: System timer execution delay utility.

---

## Included Craft Specifications

The repository includes the primary flight-ready vessel configuration file:
- **`Auto-Saved Ship`** ([`crafts/Auto-Saved Ship.craft`](file:///Users/danielkowalsky/Library/Application%20Support/Steam/steamapps/common/Kerbal%20Space%20Program/Ships/Script/crafts/Auto-Saved%20Ship.craft)): A multi-stage launch vehicle and lunar lander configured with part tags (`fairing` on procedural fairings, `antenna` on deployable antennas) and staging layout compatible with all KAL-9000 mission controllers.

---

## Installation & Usage

1. Copy the contents of this repository into your Kerbal Space Program installation directory:
   ```text
   [KSP Root Directory]/Ships/Script/
   ```
2. Launch KSP and open a vessel equipped with a **kOS Processor** unit.
3. (Optional) In the VAB or SPH, right-click the kOS module and select a boot script (such as `launch_boot.ks`).
4. Open the kOS in-game terminal and execute commands:
   ```kerboscript
   // Launch vessel to 120 km Kerbin orbit
   run launch(120000).

   // Run automated end-to-end Mun mission (Launch -> Transfer -> Land -> Ascent -> Return)
   run munMission.

   // Perform autonomous 6-DOF docking
   run dock.

   // Launch ROS 2 Nav2 autonomous rover exploration mapping
   runpath("0:/ros_explore.ks").
   ```
