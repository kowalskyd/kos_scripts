// =============================================
//      KAL-9000 BOOSTER POWERED DESCENT SCRIPT
// =============================================
// Automates the deorbit, boostback, reentry,
// and landing of a booster stage at the KSC pad.

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/mnv.ks").

wait 0.1.

// Target KSC Launchpad coordinates
local targetPad is latlng(-0.1027, -74.5753).

// Vacuum fall time estimator function (used in low-altitude atmospheric descent)
local function estimateFallTime {
  local g is body:mu / (body:radius + ship:altitude)^2.
  local vSpd is ship:verticalspeed.
  local altRadar is ship:altitude.
  
  local timeToAp is 0.
  local apAlt is altRadar.
  if vSpd > 0 {
    set timeToAp to vSpd / g.
    set apAlt to altRadar + (vSpd^2) / (2 * g).
  }
  
  local fallTime is sqrt(max(0.1, 2 * apAlt / g)).
  return timeToAp + fallTime.
}

// Predicts the exact universal time when the vessel will cross a target altitude (entry interface)
local function getEntryTime {
  parameter targetAlt.
  
  local tMin is time:seconds.
  local tMax is tMin + max(10, ETA:periapsis).
  local tImpact is tMin.
  
  local rTarget is body:radius + targetAlt.
  local steps is 0.
  until steps > 18 {
    set tImpact to (tMin + tMax) / 2.
    local pos is positionat(ship, tImpact) - body:position.
    if pos:mag < rTarget {
      set tMax to tImpact.
    } else {
      set tMin to tImpact.
    }
    set steps to steps + 1.
  }
  return tImpact.
}

// Predicts the exact geoposition at a target altitude, correcting for Kerbin's rotation
local function getEntryGeo {
  parameter targetAlt.
  
  local tImpact is getEntryTime(targetAlt).
  local impactPos is positionat(ship, tImpact).
  local absoluteGeo is body:geopositionof(impactPos).
  
  local tDiff is tImpact - time:seconds.
  local rotSpeed is 360 / body:rotationperiod.
  local correctedLng is absoluteGeo:lng - (rotSpeed * tDiff).
  
  until correctedLng >= -180 { set correctedLng to correctedLng + 360. }
  until correctedLng < 180 { set correctedLng to correctedLng - 360. }
  
  return latlng(absoluteGeo:lat, correctedLng).
}

// Active parachute deployment function
local function deployAllParachutes {
  for p in ship:parts {
    if p:hasmodule("ModuleParachute") {
      local m is p:getmodule("ModuleParachute").
      // Try standard action names
      if m:hasaction("deploy") {
        m:doaction("deploy", true).
      }
      if m:hasaction("deploy chute") {
        m:doaction("deploy chute", true).
      }
      // Try standard event names
      if m:hasevent("deploy") {
        m:doevent("deploy").
      }
      if m:hasevent("deploy chute") {
        m:doevent("deploy chute").
      }
    }
  }
}

if ship:body:name <> "Kerbin" {
  clearScreen.
  print "=======================================".
  print "     POWERED DESCENT SCRIPT ERROR      ".
  print "=======================================".
  print "Error: Vessel is not on/near Kerbin.".
  print "Currently orbiting: " + ship:body:name.
  print "=======================================".
  wait 5.
} else if ship:status = "LANDED" or ship:status = "SPLASHED" {
  clearScreen.
  print "Error: Vessel is already landed.".
  wait 5.
} else {
  // Enable RCS immediately for alignment authority during setup
  rcs on.
  
  runOncePath("0:/lib/hud.ks").
  initScreen("powered_descent").
  logChatter("CapCom", "Recovery sequence initiated. Running diagnostics...").
  hudMsg("RECOVERY SEQUENCE INITIATED").

  runDiagnostics(list("Booster Staging", "Landing Gears", "RCS & Steering")).

  // Activate booster engines if not already running
  local doneStaging is false.
  until doneStaging {
    local engines is list().
    list engines in engines.
    local hasInactiveEngine is false.
    for eng in engines {
      if not eng:ignition {
        set hasInactiveEngine to true.
      }
    }
    if hasInactiveEngine {
      logChatter("KAL-9000", "Staging booster engines...").
      hudMsg("STAGING ENGINES").
      stage.
      wait 1.5.
    } else {
      set doneStaging to true.
    }
  }

  // Calculate local TWR on Kerbin
  local gKerbin is body:mu / body:radius^2.
  local twrKerbin is 0.
  if ship:maxthrust > 0 {
    set twrKerbin to (ship:maxthrust / ship:mass) / gKerbin.
  } else {
    set twrKerbin to 1.5. // Safe fallback
  }
  logChatter("CapCom", "Kerbin local TWR calculated: " + round(twrKerbin, 2)).

  // Determine travel direction
  local eastVector is heading(90, 0):vector.
  local eastSpeed is vdot(ship:velocity:orbit, eastVector).

  // -------------------------------------------
  // STEP 1: Deorbit or Boostback Burn
  // -------------------------------------------
  local needsBoostback is false.
  local padPosHoriz is vxcl(up:vector, targetPad:position).
  local velHoriz is vxcl(up:vector, ship:velocity:surface).

  if ship:orbit:periapsis > 70000 {
    // Orbital case: perform a targeted deorbit burn
    logChatter("CapCom", "Step 1: Commencing orbital alignment for KSC deorbit.").
    hudMsg("ALIGNING ORBIT TO KSC").
    
    local deorbitLong is targetPad:lng.
    if eastSpeed > 0 {
      set deorbitLong to targetPad:lng - 150.
    } else {
      set deorbitLong to targetPad:lng + 150.
    }
    until deorbitLong >= -180 { set deorbitLong to deorbitLong + 360. }
    until deorbitLong < 180 { set deorbitLong to deorbitLong - 360. }
    
    // Calculate initial longitude distance
    local curLong is ship:longitude.
    local longDist is 0.
    if eastSpeed > 0 {
      set longDist to deorbitLong - curLong.
      until longDist >= 0 { set longDist to longDist + 360. }
    } else {
      set longDist to curLong - deorbitLong.
      until longDist >= 0 { set longDist to longDist + 360. }
    }
    
    // Phase 1A: Align to retrograde first so we are ready before warp
    lock steering to retrograde.
    logChatter("Crew", "Pre-aligning to retrograde...").
    until vAng(ship:facing:vector, retrograde:vector) < 5 {
      updateLandingTelemetry("orbit_align", alt:radar, longDist, 0, ship:verticalspeed, ship:groundspeed).
      wait 0.1.
    }
    logChatter("Crew", "Retrograde alignment confirmed.").
    
    // Phase 1B: Warp to the deorbit window (if far away)
    if longDist > 12 {
      logChatter("KAL-9000", "Warping to deorbit window.").
      local warpTime is time:seconds + (longDist - 8) * (ship:orbit:period / 360).
      
      // Temporarily unlock steering/throttle for warp
      lock throttle to 0.
      unlock steering.
      unlock throttle.
      
      kuniverse:timewarp:warpto(warpTime).
      wait 0.5.
      wait until kuniverse:timewarp:rate = 1 and kuniverse:timewarp:issettled.
      
      // Re-align to retrograde after warp
      lock steering to retrograde.
      logChatter("Crew", "Re-aligning to retrograde...").
      until vAng(ship:facing:vector, retrograde:vector) < 5 {
        // Recalculate longDist
        set curLong to ship:longitude.
        if eastSpeed > 0 {
          set longDist to deorbitLong - curLong.
          until longDist >= 0 { set longDist to longDist + 360. }
        } else {
          set longDist to curLong - deorbitLong.
          until longDist >= 0 { set longDist to longDist + 360. }
        }
        updateLandingTelemetry("orbit_align", alt:radar, longDist, 0, ship:verticalspeed, ship:groundspeed).
        wait 0.1.
      }
      logChatter("Crew", "Retrograde lock confirmed.").
    }
    
    // Phase 1C: Fine drift to the exact burn point at 1x speed while holding retrograde steering
    local aligned is false.
    until aligned {
      set curLong to ship:longitude.
      if eastSpeed > 0 {
        set longDist to deorbitLong - curLong.
        until longDist >= 0 { set longDist to longDist + 360. }
      } else {
        set longDist to curLong - deorbitLong.
        until longDist >= 0 { set longDist to longDist + 360. }
      }
      
      updateLandingTelemetry("orbit_align", alt:radar, longDist, 0, ship:verticalspeed, ship:groundspeed).
      
      if longDist < 2.5 {
        set aligned to true.
      }
      wait 0.1.
    }
    
    logChatter("CapCom", "Deorbit window reached. Initiating deorbit burn.").
    hudMsg("DEORBIT BURN ACTIVE").
    
    // Since we are already steering retrograde and aligned, start the engines immediately
    lock throttle to 1.
    
    // First, burn until the periapsis is below 45km so the entry solver is valid
    until ship:orbit:periapsis < 45000 {
      updateLandingTelemetry("deorbiting", alt:radar, -9999, throttle, ship:verticalspeed, ship:groundspeed).
      wait 0.
    }
    
    // Now, target the exact 45km atmospheric entry longitude
    local doneDeorbit is false.
    until doneDeorbit {
      local entryGeo is getEntryGeo(45000).
      local longDiff is entryGeo:lng - targetPad:lng.
      local distError is longDiff * 10470.
      
      updateLandingTelemetry("deorbiting", alt:radar, distError, throttle, ship:verticalspeed, ship:groundspeed).
      
      if eastSpeed > 0 {
        if longDiff > 3.5 { set doneDeorbit to true. }
      } else {
        if longDiff < -3.5 { set doneDeorbit to true. }
      }
      
      // Safety: if we get too low in the atmosphere, cut burn
      if ship:altitude < 65000 {
        logChatter("KAL-9000", "Altitude safety limit reached. Cutting engines.").
        set doneDeorbit to true.
      }
      
      wait 0.
    }
    lock throttle to 0.
    wait until ship:thrust = 0.
    wait 0.1. // Allow physics frame to settle
    rcs off.
    logChatter("CapCom", "Deorbit burn complete. Trajectory targeted to KSC (overshoot).").
  } else if targetPad:distance > 15000 and vdot(velHoriz, padPosHoriz) < 0 {
    // Suborbital case moving away from KSC: perform a boostback burn
    set needsBoostback to true.
  }

  if needsBoostback {
    logChatter("CapCom", "Booster is suborbital and moving away from KSC. Initiating boostback burn.").
    hudMsg("BOOSTBACK BURN ACTIVE").
    
    // Rotate to target (facing the pad, but with 20 deg pitch up to save altitude)
    local padDir is vxcl(up:vector, targetPad:position):normalized.
    local targetDir is padDir * cos(20) + up:vector * sin(20).
    rcs on.
    lock steering to lookdirup(targetDir, up:vector).
    
    logChatter("Crew", "Aligning booster for boostback...").
    until vAng(ship:facing:vector, targetDir) < 5 {
      updateLandingTelemetry("aligning", alt:radar, 0, 0, ship:verticalspeed, ship:groundspeed).
      wait 0.1.
    }
    logChatter("Crew", "Boostback alignment confirmed. Starting engines.").
    
    lock throttle to 1.
    
    // First, if periapsis is not yet below 45km, burn until it is so the solver is valid
    until ship:orbit:periapsis < 45000 {
      updateLandingTelemetry("boostback", alt:radar, -9999, throttle, ship:verticalspeed, ship:groundspeed).
      wait 0.
    }
    
    local doneBoostback is false.
    until doneBoostback {
      local entryGeo is getEntryGeo(45000).
      local longDiff is entryGeo:lng - targetPad:lng.
      local distError is longDiff * 10470.
      
      updateLandingTelemetry("boostback", alt:radar, distError, throttle, ship:verticalspeed, ship:groundspeed).
      
      // We want to overshoot KSC by 1.2 degrees of longitude (approx 12km)
      if eastSpeed > 0 {
        if longDiff < -1.2 { set doneBoostback to true. }
      } else {
        if longDiff > 1.2 { set doneBoostback to true. }
      }
      
      // Safety: if we get too low in the atmosphere, cut burn
      if ship:altitude < 45000 {
        logChatter("KAL-9000", "Altitude threshold met during boostback. Cutting engines.").
        set doneBoostback to true.
      }
      
      wait 0.
    }
    lock throttle to 0.
    wait until ship:thrust = 0.
    wait 0.1. // Allow physics frame to settle
    logChatter("CapCom", "Boostback burn complete. Entering coast phase.").
  }

  // -------------------------------------------
  // STEP 2: Coast & Reentry (Safety-Ceiling-Driven Reentry Burn)
  // -------------------------------------------
  logChatter("CapCom", "Coasting to atmospheric entry...").
  
  // Unlock steering and throttle to allow KSP to timewarp without blocks
  lock throttle to 0.
  unlock steering.
  unlock throttle.
  
  // Warp to 15 seconds before crossing the 70km atmospheric boundary
  if ship:altitude > 71500 {
    local entryTime is getEntryTime(70000).
    if entryTime - time:seconds > 30 {
      logChatter("KAL-9000", "Warping to atmospheric entry...").
      kuniverse:timewarp:warpto(entryTime - 15).
      wait 0.5. // Give KSP time to engage warp
      wait until kuniverse:timewarp:rate = 1 and kuniverse:timewarp:issettled.
    }
  }
  
  // Re-lock steering to retrograde for entry alignment
  rcs on.
  lock steering to srfretrograde.
  
  // Deploy airbrakes from 75k altitude onwards
  if ship:altitude < 75000 {
    brakes on.
    logChatter("Crew", "Deploying airbrakes (75k ceiling).").
  } else {
    when ship:altitude < 75000 then {
      brakes on.
      logChatter("Crew", "Deploying airbrakes (75k ceiling).").
    }
  }
  
  until ship:altitude < 70000 {
    updateLandingTelemetry("coasting", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
    wait 0.5.
  }
  
  logChatter("CapCom", "Atmospheric entry. Deploying grid fins/RCS.").
  rcs on.
  
  // Monitor speed through reentry and execute safety deceleration burns if thresholds are exceeded
  until ship:altitude < 5000 {
    local spd is ship:velocity:surface:mag.
    local altVal is ship:altitude.
    
    updateLandingTelemetry("reentry", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
    
    // 1. High-altitude thermal safety check (between 40km and 15km, speed must not exceed 1050 m/s)
    if altVal < 40000 and altVal > 15000 and spd > 1050 {
      logChatter("CapCom", "WARNING: Speed exceeds thermal limit (" + round(spd) + " m/s). Starting safety burn.").
      hudMsg("THERMAL SAFETY BURN", rgb(1, 0.5, 0)).
      
      rcs on.
      lock steering to srfretrograde.
      wait 0.2. // Allow steering to settle
      lock throttle to 1.
      until ship:velocity:surface:mag < 800 or ship:altitude < 15000 {
        updateLandingTelemetry("safety_burn", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
        wait 0.
      }
      lock throttle to 0.
      logChatter("CapCom", "Safety burn complete. Resuming coast.").
    }
    
    // 2. Low-altitude parachute deployment safety check (below 8km, speed must be brought below 240 m/s to avoid chute tearing)
    if altVal < 8000 and spd > 240 {
      logChatter("CapCom", "WARNING: Speed too high for chutes (" + round(spd) + " m/s). Deploying braking thrust.").
      hudMsg("CHUTE BRAKING BURN", rgb(1, 0.5, 0)).
      
      rcs on.
      lock steering to srfretrograde.
      wait 0.2.
      lock throttle to 1.
      until ship:velocity:surface:mag < 220 or ship:altitude < 3500 {
        updateLandingTelemetry("chute_brake", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
        wait 0.
      }
      lock throttle to 0.
      logChatter("CapCom", "Braking burn complete. Speed safe for chutes.").
      break.
    }
    
    wait 0.1.
  }

  // -------------------------------------------
  // STEP 3: Parachute Deployment & Glide
  // -------------------------------------------
  logChatter("CapCom", "Step 3: Preparing for parachute deployment.").
  hudMsg("PREPARING PARACHUTES").
  
  // Wait until altitude is below 5000m and speed is below 250 m/s
  until ship:altitude < 5000 and ship:velocity:surface:mag < 250 {
    updateLandingTelemetry("glide_pre_chute", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
    wait 0.1.
  }
  
  logChatter("Crew", "Deploying all parachutes!").
  hudMsg("PARACHUTES DEPLOYED", rgb(0, 1, 0)).
  deployAllParachutes().
  stage. // Trigger staging as a fallback
  
  // Coast and let the parachutes slow us down to terminal velocity
  logChatter("CapCom", "Coasting under parachutes...").
  until alt:radar < 1000 or ship:verticalspeed > -25 {
    updateLandingTelemetry("chute_descent", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
    wait 0.5.
  }

  // -------------------------------------------
  // STEP 4: Parachute-Cushioned Landing Burn
  // -------------------------------------------
  logChatter("KAL-9000", "Entering final powered descent phase.").
  hudMsg("POWERED CUSHION ACTIVE").
  
  local landed is false.
  local phase is "falling".
  local lastChatTime is time:seconds.
  
  until landed {
    local grav is body:mu / (body:radius + ship:altitude)^2.
    local thrAccel is max(0.1, ship:maxthrust / ship:mass).
    local effDecel is max(0.01, thrAccel - grav).
    local spd is ship:velocity:surface:mag.
    local vSpd is ship:verticalspeed.
    local hSpd is ship:groundspeed.
    local radar is alt:radar.
    local stopDist is spd^2 / (2 * effDecel).
    
    if phase = "falling" {
      lock steering to srfretrograde.
      lock throttle to 0.
      // Ignite when stopping distance matches altitude (target stopping 8m above ground)
      if radar <= stopDist + 8 {
        set phase to "braking".
        logChatter("KAL-9000", "Touchdown burn ignited!").
        hudMsg("TOUCHDOWN BURN", rgb(1,0,0)).
      }
    }
    
    if phase = "braking" {
      lock steering to srfretrograde.
      // Throttle ratio to target stopping at 8m above ground
      local thrRatio is stopDist / max(1, radar - 8).
      lock throttle to max(0.05, min(1, thrRatio)).
      
      if spd < 5 and radar < 30 {
        set phase to "descent".
        gear on.
        logChatter("CapCom", "Controlled final touchdown descent.").
      }
    }
    
    if phase = "descent" {
      local targetVspd is -1.2.
      if radar > 15 { set targetVspd to -2.0. }
      else if radar > 5 { set targetVspd to -1.0. }
      else { set targetVspd to -0.6. }
      
      local hoverThr is grav / thrAccel.
      local pidGain is min(0.5, 0.05 * twrKerbin).
      local vSpdErr is targetVspd - vSpd.
      local thr is hoverThr + vSpdErr * pidGain.
      
      lock steering to up.
      lock throttle to max(0, min(1, thr)).
      gear on.
    }
    
    // Update UI telemetry
    updateLandingTelemetry(phase, radar, stopDist, throttle, vSpd, hSpd).
    
    if time:seconds - lastChatTime > 12 {
      randomChatter("landing").
      set lastChatTime to time:seconds.
    }
    
    // Detect touchdown
    if ship:status = "LANDED" or ship:status = "SPLASHED" {
      set landed to true.
    }
    
    // Emergency failsafe: if we are low and falling fast, override to max thrust
    if radar < 10 and vSpd < -3 {
      lock throttle to 1.
      lock steering to up.
    }
    
    wait 0.
  }
  
  // Post-landing shutdown
  lock throttle to 0.
  wait 0.1.
  unlock steering.
  unlock throttle.
  set ship:control:pilotMainThrottle to 0.
  rcs off.
  sas on.
  
  initScreen("recovered").
  logChatter("Crew", "Touchdown! Booster successfully recovered!").
  logChatter("CapCom", "Booster recovery successful. KSC ground crew moving in.").
  hudMsg("BOOSTER RECOVERED!", rgb(0,1,0)).
  
  wait 5.
}
