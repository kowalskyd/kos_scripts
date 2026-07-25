# Mun Script Timewarp Specifications & Review

This document lists every timewarp executed during the automated Mun mission suite (`launch.ks`, `mun.ks`, `munLand.ks`, `munLaunch.ks`, `munReturn.ks`).

---

## 1. Kerbin Launch & Ascent (`launch.ks`)

### 1.1 Atmospheric Gravity Turn Ascent
- **Flight Stage**: Liftoff up to atmospheric exit (1,000 m to 60,000 m).
- **Warp Mode**: `PHYSICS`
- **Time Factor / Multiplier**: **2x** (`SET KUNIVERSE:TIMEWARP:RATE TO 2`)
- **Trigger / Conditions**: Active while pitching over in lower atmosphere (kept at 2x for aerodynamic stability).

### 1.2 Atmospheric Coast to Space
- **Flight Stage**: Engine cutoff after target Apoapsis is reached up to 70,000 m.
- **Warp Mode**: `PHYSICS`
- **Time Factor / Multiplier**: **4x** (`SET KUNIVERSE:TIMEWARP:RATE TO 4`)
- **Trigger / Conditions**: Active while vessel altitude $< 70,000\text{ m}$. Automatically resets to `RAILS` 1x at 70,000 m.

### 1.3 Coast to Apoapsis Insertion Window
- **Flight Stage**: Coasting above 70 km to the circularization burn at Apoapsis.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: Stops `warpMargin` seconds before Apoapsis:
  $$\text{warpMargin} = \max\left(30, \min\left(70, \frac{\text{mass}}{5} + 10\right)\right)$$

---

## 2. Trans-Lunar Injection & Capture (`mun.ks`, `lib/transfer.ks`, `lib/mnv.ks`)

### 2.1 Transfer Window Wait (`lib/transfer.ks`)
- **Flight Stage**: Waiting in Kerbin orbit for Mun phase angle alignment.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: Triggered if window $> 45\text{ s}$. Warps to 30 seconds before transfer window (`deltaTime - 30`).

### 2.2 Maneuver Node Burn Execution (`exeMnv()` in `lib/mnv.ks`)
- **Flight Stage**: Coasting to maneuver nodes (Trans-Lunar Injection, Orbital Corrections, Capture).
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: Pre-aligns steering vector, then warps to:
  $$\text{warpTime} = \text{Node Time} - \frac{\text{Burn Duration}}{2} - \text{margin}$$
  *(where margin = 10s to 60s depending on vessel mass)*.

### 2.3 Trans-Lunar Transit & Mun SOI Entry (`mun.ks`)
- **Flight Stage**: Coasting from Kerbin ejection to Mun Sphere of Influence entry.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: `warpto(time:seconds + ETA:transition - 15)` (stops 15 seconds before crossing boundary, allowing clean handoff into Mun SOI).

---

## 3. Mun Deorbit & Powered Descent (`munLand.ks`)

### 3.1 Warp to Deorbit Burn
- **Flight Stage**: Coasting in Mun orbit to deorbit burn node.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp (`exeMnv`)
- **Lead Time Offset**: Standard node lead-time margin.

### 3.2 Descent Falling Coast Phase
- **Flight Stage**: Falling vertically toward Mun surface after killing horizontal orbital velocity.
- **Warp Mode**: `PHYSICS`
- **Time Factor / Multiplier**: **4x** (`set warpmode to "physics"`, `set warp to 3`)
- **Trigger / Conditions**: Active when $\text{alt:radar} > 2,000\text{ m}$ AND $\text{alt:radar} > \text{stopDist} + \text{safetyMargin} + 500\text{ m}$.

### 3.3 Suicide Burn Ignition Preparation
- **Flight Stage**: Transition from physics warp back to 1x real-time before suicide burn ignition.
- **Warp Mode**: `REALTIME`
- **Time Factor / Multiplier**: **1x** (`set warp to 0`)
- **Trigger / Conditions**: Triggers as soon as radar altitude reaches $\text{stopDist} + \text{safetyMargin} + 500\text{ m}$ or falls below $2,000\text{ m}$.

---

## 4. Lunar Surface Liftoff & Re-orbit (`munLaunch.ks`)

### 4.1 Surface Pitchover Ascent
- **Flight Stage**: Liftoff from Mun surface up to target 35 km Apoapsis.
- **Warp Mode**: `PHYSICS`
- **Time Factor / Multiplier**: **2x** (`SET KUNIVERSE:TIMEWARP:RATE TO 2`)
- **Trigger / Conditions**: Active during powered ascent above 200 m radar altitude.

### 4.2 Coast to Apoapsis Circularization
- **Flight Stage**: Coasting above 5,000 m to Apoapsis.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: Triggered if $\text{ETA:apoapsis} > \text{warpMargin} + 30$. Warps to `ETA:apoapsis - warpMargin`.

---

## 5. Trans-Kerbin Return & Re-entry (`munReturn.ks`)

### 5.1 Trans-Kerbin Ejection Burn
- **Flight Stage**: Coasting to ejection node in Mun orbit.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp (`exeMnv`)
- **Lead Time Offset**: Standard node lead-time margin.

### 5.2 Coast to Kerbin SOI Entry
- **Flight Stage**: Coasting out of Mun's SOI into Kerbin's SOI.
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: `warpto(time:seconds + ETA:transition - 15)` (stops 15 seconds before crossing Mun SOI boundary).

### 5.3 Coast to Kerbin Re-entry Interface
- **Flight Stage**: High-altitude coast down toward Kerbin atmosphere (30 km periapsis).
- **Warp Mode**: `RAILS` (`WARPTO`)
- **Time Factor / Multiplier**: Automatic On-Rails Warp
- **Lead Time Offset**: `warpto(time:seconds + max(10, ETA:periapsis - 60))` (single clean On-Rails warp directly to atmospheric interface).
