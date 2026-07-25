runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

if ship:body:name <> "Minmus" {
  clearScreen.
  print "=======================================".
  print "       MINMUS LANDING SCRIPT ERROR     ".
  print "=======================================".
  print "Error: Vessel is not orbiting Minmus.".
  print "Currently orbiting: " + ship:body:name.
  print "=======================================".
  wait 5.
} else if ship:status = "LANDED" or ship:status = "SPLASHED" {
  clearScreen.
  print "Error: Vessel is already landed.".
  wait 5.
} else {
  runOncePath("0:/lib/hud.ks").
  initScreen("minmus_landing").
  logChatter("CapCom", "Landing sequence initiated. Running diagnostics...").
  hudMsg("LANDING SEQUENCE INITIATED").

  runDiagnostics(list("Lander Staging", "Landing Gears", "Lights & Panels")).

  // Ensure the lander engine is activated and any extra transfer stages are dropped
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
      logChatter("KAL-9000", "Staging transfer booster...").
      hudMsg("STAGING BOOSTER").
      stage.
      wait 1.5.
    } else {
      set doneStaging to true.
    }
  }

  // Reset engine thrust limits to ensure full power for the landing sequence
  for eng in ship:engines {
    set eng:thrustlimit to 100.
  }

  logChatter("Crew", "Deploying landing legs, lights, and panels.").
  gear on.
  lights on.
  panels on.

  // Check TWR on Minmus (stage first to ensure engine is active)
  local gMinmus is body:mu / body:radius^2.
  local twrMinmus is 0.
  if ship:maxthrust > 0 {
    set twrMinmus to (ship:maxthrust / ship:mass) / gMinmus.
  } else {
    // Engine not active yet, estimate TWR after staging check
    stage.
    wait 0.5.
    if ship:maxthrust > 0 {
      set twrMinmus to (ship:maxthrust / ship:mass) / gMinmus.
    } else {
      set twrMinmus to 3. // Safe fallback
      logChatter("KAL-9000", "WARNING: Could not determine TWR.").
    }
  }
  
  logChatter("CapCom", "Minmus local TWR calculated: " + round(twrMinmus, 2)).
  if twrMinmus < 1.2 {
    logChatter("CapCom", "WARNING: Low TWR profile detected!").
    wait 3.
  }

  // -------------------------------------------
  // STEP 1: Deorbit - lower periapsis to ~7km
  // -------------------------------------------
  logChatter("CapCom", "Step 1: Commencing deorbit burn.").
  wait 1.

  if ship:orbit:periapsis > 9000 {
    goToFrom(8000, "AP"). // Minmus safe Pe is much lower, e.g. 3.1km, but we need safety margin
    
    // Check if the landing site of the planned node is in the dark
    local myNode is nextNode.
    local peTime is time:seconds + myNode:ETA + myNode:orbit:period / 2.
    local moonToPe is positionat(ship, peTime) - body:position.
    local sunVec is Sun:position - body:position.
    
    if vAng(sunVec, moonToPe) > 90 {
      logChatter("CapCom", "WARNING: Planned landing site is in darkness. Delaying burn by half an orbit to land in sunlight.").
      local newEta is myNode:ETA + myNode:orbit:period / 2.
      local newDV is myNode:prograde.
      remove myNode.
      wait 0.1.
      local newNode is node(time:seconds + newEta, 0, 0, newDV).
      add newNode.
    }
    
    exeMnv().
    wait 1.
  } else {
    logChatter("CapCom", "Periapsis already low: " + round(ship:orbit:periapsis/1000, 1) + " km").
  }
  playDescendScene().

  // -------------------------------------------
  // STEP 2: Warp to periapsis
  // -------------------------------------------
  logChatter("CapCom", "Step 2: Warping to periapsis landing entry.").
  wait 1.

  // Align surface retrograde first to ensure we are aligned before warping
  logChatter("Crew", "Aligning spacecraft to surface retrograde...").
  playAlignScene(10).
  lock steering to srfretrograde.
  wait until vAng(ship:facing:vector, srfretrograde:vector) < 5.
  logChatter("Crew", "Retrograde lock confirmed.").

  if ETA:periapsis > 20 {
    logChatter("CapCom", "Warping to periapsis landing entry...").
    set MAPVIEW to true.
    local targetTime is time:seconds + ETA:periapsis - 10.
    warpto(targetTime).
    wait until time:seconds >= targetTime.
    set MAPVIEW to false.
  }

  // Final alignment before deorbit burn
  lock steering to srfretrograde.
  wait until vAng(ship:facing:vector, srfretrograde:vector) < 3.
  wait until ETA:periapsis < 3 or ETA:periapsis > ship:orbit:period - 5.

  // -------------------------------------------
  // STEP 3: Kill horizontal velocity at periapsis
  // -------------------------------------------
  initScreen("deorbit").
  logChatter("CapCom", "Step 3: Killing horizontal orbital speed.").
  hudMsg("DEORBIT BURN ACTIVE").
  lock horizontalRetro to vxcl(up:vector, srfretrograde:vector).
  lock steering to lookdirup(choose horizontalRetro:normalized if ship:groundspeed > 15 else up:vector, up:vector).
  lock throttle to 1.

  local emergencyDescent is false.
  until ship:groundspeed < 12 {
    local grav is body:mu / (body:radius + ship:altitude)^2.
    local thrAccel is ship:maxthrust / ship:mass.
    local effDecel is max(0.01, thrAccel - grav).
    local stopDist is (ship:velocity:surface:mag^2 / (2 * effDecel)) + (ship:velocity:surface:mag * 0.8).

    // Calculate adjusted radar to account for terrain slope/ridges ahead
    local currentGeo is body:geopositionof(V(0,0,0)).
    local maxH is currentGeo:terrainheight.
    local horizVel is vxcl(up:vector, ship:velocity:surface).
    local stopDistHoriz is ship:groundspeed * (ship:velocity:surface:mag / max(0.1, effDecel)).
    if horizVel:mag > 1 and stopDistHoriz > 10 {
      local dir is horizVel:normalized.
      for fraction in list(0.25, 0.5, 0.75, 1.0) {
        local samplePoint is dir * (stopDistHoriz * fraction).
        local sampleH is body:geopositionof(samplePoint):terrainheight.
        if sampleH > maxH {
          set maxH to sampleH.
        }
      }
    }
    local adjustedRadar is alt:radar - max(0, maxH - currentGeo:terrainheight).

    updateLandingTelemetry("deorbiting", alt:radar, stopDist, throttle, ship:verticalspeed, ship:groundspeed).

    // Safety: if getting close to ground, break out to descent phase (using Minmus-specific threshold)
    if adjustedRadar < stopDist + 100 and alt:radar < 1500 {
      set emergencyDescent to true.
      logChatter("KAL-9000", "Critical altitude margin met! Switching to descent.").
      break.
    }
    wait 0.
  }

  local phase is "falling".
  if not emergencyDescent {
    lock throttle to 0.
    logChatter("CapCom", "Horizontal speed killed. Commencing vertical descent.").
    wait 0.5.
  } else {
    set phase to "braking".
  }

  // -------------------------------------------
  // STEP 4: Falling + suicide burn + final descent
  // -------------------------------------------
  local function setMaxTWR {
    parameter targetTWR.
    local grav is body:mu / (body:radius + ship:altitude)^2.
    local targetAcc is targetTWR * grav.
    if targetAcc - grav < 2.5 {
      set targetAcc to grav + 2.5.
    }
    local targetThrust is targetAcc * ship:mass.
    local totalPossible is 0.
    for eng in ship:engines {
      if eng:ignition {
        set totalPossible to totalPossible + eng:possiblethrust.
      }
    }
    if totalPossible > 0 {
      local limitPercent is (targetThrust / totalPossible) * 100.
      set limitPercent to max(5, min(100, limitPercent)).
      for eng in ship:engines {
        if eng:ignition {
          set eng:thrustlimit to limitPercent.
        }
      }
    }
  }

  local safetyMargin is 20.
  local lastChatTime is time:seconds.

  // Reset engine thrust limits for full suicide burn power
  for eng in ship:engines {
    set eng:thrustlimit to 100.
  }

  // ---- PHASE A: FALLING (coast down until suicide burn altitude) ----
  logChatter("KAL-9000", "Commencing vertical descent. Coasting to suicide burn altitude.").
  lock steering to srfretrograde.
  lock throttle to 0.

  until false {
    local grav is body:mu / (body:radius + ship:altitude)^2.
    local thrAccel is ship:maxthrust / ship:mass.
    local effDecel is max(0.01, thrAccel - grav).
    local spd is ship:velocity:surface:mag.
    local stopDist is (spd^2 / (2 * effDecel)) + (spd * 0.8).
    local radar is alt:radar.

    updateLandingTelemetry("falling", radar, stopDist, throttle, ship:verticalspeed, ship:groundspeed).

    // Auto-warp during falling phase
    if radar > 2000 and radar > stopDist + safetyMargin + 500 {
      if kuniverse:timewarp:rate = 1 {
        logChatter("KAL-9000", "Engaging warp for descent coast.").
        set warpmode to "physics".
        set warp to 3.
      }
    } else {
      if kuniverse:timewarp:rate > 1 {
        logChatter("KAL-9000", "Disengaging warp. Preparing for suicide burn.").
        set warp to 0.
        wait until kuniverse:timewarp:rate = 1.
      }
    }

    if radar <= stopDist + safetyMargin {
      break.
    }
    wait 0.
  }

  // ---- PHASE B: SUICIDE BURN (full thrust until slow, smooth ramp-down to cutoff) ----
  logChatter("KAL-9000", "Suicide burn window reached. Full braking thrust!").
  hudMsg("SUICIDE BURN ACTIVE", rgb(1,0,0)).
  playLandingScene().
  rcs off.

  until ship:verticalspeed > -3.0 {
    // 1. Steering protection: lock steering to UP when speed is low to prevent flipping
    if ship:velocity:surface:mag < 20 or ship:verticalspeed > -18.0 {
      lock steering to up.
    } else {
      lock steering to srfretrograde.
    }

    // 2. Throttle ramp-down: 100% full thrust when fast, scaling down to ~12% near cutoff (-3 m/s)
    local tVal is 1.0.
    if ship:verticalspeed > -18.0 {
      set tVal to max(0.12, (ship:verticalspeed - (-3.0)) / (-18.0 - (-3.0))).
    }
    lock throttle to tVal.

    updateLandingTelemetry("braking", alt:radar, 0, throttle, ship:verticalspeed, ship:groundspeed).
    wait 0.
  }
  lock throttle to 0.  // Immediately kill engines at cutoff
  lock steering to up.

  // ---- PHASE C: SETTLING (kill engines, gently rotate to vertical) ----
  lock throttle to 0.
  local settleStart is time:seconds.
  local settleDir is ship:facing:vector.
  until time:seconds - settleStart > 0.5 {
    local blend is min(1, (time:seconds - settleStart) / 0.5).
    lock steering to (1 - blend) * settleDir + blend * up:vector.
    wait 0.
  }
  lock steering to up.

  // ---- PHASE D: CONTROLLED DESCENT (PID hover down to touchdown) ----
  logChatter("CapCom", "Controlled final landing descent started.").
  hudMsg("FINAL DESCENT").
  setMaxTWR(2.2).
  rcs on.
  gear on.

  local lastVspdErr is 0.
  local lastVspdTime is time:seconds.

  until ship:status = "LANDED" or ship:status = "SPLASHED" {
    local grav is body:mu / (body:radius + ship:altitude)^2.
    local vSpd is ship:verticalspeed.
    local hSpd is ship:groundspeed.
    local radar is alt:radar.

    local targetVspd is max(-10, -0.5 - (radar / 25)).

    local activeMaxThrust is 0.
    for eng in ship:engines {
      if eng:ignition {
        set activeMaxThrust to activeMaxThrust + eng:possiblethrust.
      }
    }
    local limitedMaxAcc is max(0.01, activeMaxThrust / ship:mass).
    local hoverThr is grav / limitedMaxAcc.
    local vSpdErr is targetVspd - vSpd.

    local dt is max(0.001, time:seconds - lastVspdTime).
    if dt > 1.0 {
      set dt to 0.02.
      set lastVspdErr to vSpdErr.
    }
    local vSpdDeriv is (vSpdErr - lastVspdErr) / dt.
    set lastVspdErr to vSpdErr.
    set lastVspdTime to time:seconds.

    local kp is 0.25.
    local kd is 0.10.
    local thr is hoverThr + vSpdErr * kp + vSpdDeriv * kd.

    local horizVel is ship:velocity:surface - vdot(ship:velocity:surface, up:vector) * up:vector.
    local steerDir is up:vector.
    if horizVel:mag > 0.3 {
      local maxTilt is 8.
      local tiltAngle is min(maxTilt, horizVel:mag * 1.5).
      set steerDir to cos(tiltAngle) * up:vector - sin(tiltAngle) * horizVel:normalized.
    }
    lock steering to steerDir.
    lock throttle to max(0, min(1, thr)).

    // Emergency: if very low and falling fast, full thrust
    if radar < 5 and vSpd < -2 {
      lock throttle to 1.
      lock steering to up.
    }

    updateLandingTelemetry("descent", radar, 0, throttle, vSpd, hSpd).

    if time:seconds - lastChatTime > 15 {
      randomChatter("landing").
      set lastChatTime to time:seconds.
    }

    wait 0.
  }

  // -------------------------------------------
  // STEP 5: Landed!
  // -------------------------------------------
  lock throttle to 0.
  for eng in ship:engines {
    set eng:thrustlimit to 100.
  }
  wait 0.1.
  unlock steering.
  unlock throttle.
  set ship:control:pilotMainThrottle to 0.
  rcs off.
  sas on.

  initScreen("landed").
  logChatter("Crew", "Touchdown! Safe landing on Minmus's flat!").
  logChatter("CapCom", "Minmus landing successful. The green fields look beautiful.").
  hudMsg("LANDED ON MINMUS!", rgb(0,1,0)).
  stopCameraScene().
  if not (defined automatedMission) {
    until false {
      updateLandingTelemetry("landed", alt:radar, 0, 0, ship:verticalspeed, ship:groundspeed).
      wait 1.0.
    }
  } else {
    wait 5.
  }
}
