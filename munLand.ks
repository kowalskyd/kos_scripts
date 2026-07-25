runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

if ship:body:name <> "Mun" {
  clearScreen.
  print "=======================================".
  print "        MUN LANDING SCRIPT ERROR       ".
  print "=======================================".
  print "Error: Vessel is not orbiting the Mun.".
  print "Currently orbiting: " + ship:body:name.
  print "=======================================".
  wait 5.
} else if ship:status = "LANDED" or ship:status = "SPLASHED" {
  clearScreen.
  print "Error: Vessel is already landed.".
  wait 5.
} else {
  runOncePath("0:/lib/hud.ks").
  initScreen("mun_landing").
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

  // Check TWR on the Mun (stage first to ensure engine is active)
  local gMun is body:mu / body:radius^2.
  local twrMun is 0.
  if ship:maxthrust > 0 {
    set twrMun to (ship:maxthrust / ship:mass) / gMun.
  } else {
    // Engine not active yet, estimate TWR after staging check
    stage.
    wait 0.5.
    if ship:maxthrust > 0 {
      set twrMun to (ship:maxthrust / ship:mass) / gMun.
    } else {
      set twrMun to 3. // Safe fallback
      logChatter("KAL-9000", "WARNING: Could not determine TWR.").
    }
  }
  
  logChatter("CapCom", "Mun local TWR calculated: " + round(twrMun, 2)).
  if twrMun < 1.2 {
    logChatter("CapCom", "WARNING: Low TWR profile detected!").
    wait 3.
  }

  // -------------------------------------------
  // STEP 1: Select Illuminated Flat Crater & Deorbit to 7km
  // -------------------------------------------
  logChatter("CapCom", "Step 1: Selecting illuminated flat crater basin.").
  set MAPVIEW to true.
  wait 1.

  // Define flat equatorial crater basin candidates (smooth crater floors away from rims)
  local craterCandidates is list(
    lexicon("name", "East Crater Floor", "geo", latlng(0.0, 27.0)),
    lexicon("name", "Equatorial Basin", "geo", latlng(0.0, 0.0)),
    lexicon("name", "Fargodeep Basin", "geo", latlng(0.0, 159.0)),
    lexicon("name", "Northwest Basin", "geo", latlng(0.0, -140.0))
  ).

  local selectedCrater is craterCandidates[0].
  local sunVec is Sun:position - body:position.

  // Pick first candidate crater floor in direct sunlight (< 85 degrees sun angle)
  for c in craterCandidates {
    local cPos is c:geo:position - body:position.
    local sunAngle is vAng(sunVec, cPos).
    if sunAngle <= 85 {
      set selectedCrater to c.
      break.
    }
  }

  logChatter("CapCom", "Target Crater Selected: " + selectedCrater:name + " (Sunlight Illuminated)").
  hudMsg("TARGET: " + selectedCrater:name:toUpper()).
  wait 2.

  if ship:orbit:periapsis > 9000 {
    // Calculate time to cross target crater longitude
    local targetLng is selectedCrater:geo:lng.
    local currentLng is ship:longitude.
    local diffLng is targetLng - currentLng.
    until diffLng >= 0 { set diffLng to diffLng + 360. }

    local orbPeriod is ship:orbit:period.
    local rotPeriod is body:rotationperiod.
    local relDegPerSec is (360 / orbPeriod) - (360 / rotPeriod).
    if relDegPerSec <= 0 { set relDegPerSec to 360 / orbPeriod. }

    local timeToTarget is diffLng / relDegPerSec.
    local burnTime is time:seconds + timeToTarget - (orbPeriod / 2).

    until burnTime > time:seconds + 30 {
      set burnTime to burnTime + (360 / relDegPerSec).
    }

    local dvNeeded is hTrans(ship:altitude, 7000).
    local deorbitNode is node(burnTime, 0, 0, dvNeeded).
    add deorbitNode.
    wait 0.1.

    logChatter("CapCom", "Deorbit node planned to place periapsis over " + selectedCrater:name).
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
  set MAPVIEW to true.
  wait 1.

  // Align surface retrograde first to ensure we are aligned before warping
  logChatter("Crew", "Aligning spacecraft to surface retrograde...").
  lock steering to srfretrograde.
  wait until vAng(ship:facing:vector, srfretrograde:vector) < 5 or ETA:periapsis < 15.
  logChatter("Crew", "Retrograde lock confirmed.").

  if ETA:periapsis > 20 {
    logChatter("CapCom", "Warping to periapsis landing entry...").
    warpto(time:seconds + ETA:periapsis - 15).
    wait until kuniverse:timewarp:issettled or kuniverse:timewarp:rate = 1.
  }

  // Quick vector check at periapsis before burn ignition
  lock steering to srfretrograde.
  wait until vAng(ship:facing:vector, srfretrograde:vector) < 3 or ETA:periapsis < 3.
  set MAPVIEW to false.

  // -------------------------------------------
  // STEP 3: Kill horizontal velocity at periapsis
  // -------------------------------------------
  initScreen("deorbit").
  logChatter("CapCom", "Step 3: Killing horizontal orbital speed.").
  hudMsg("DEORBIT BURN ACTIVE").
  lock horizontalRetro to vxcl(up:vector, srfretrograde:vector).
  lock steering to lookdirup(choose horizontalRetro:normalized if ship:groundspeed > 18 else up:vector, up:vector).
  lock throttle to 1.

  local emergencyDescent is false.
  until ship:groundspeed < 15 {
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

    // Safety: if getting close to ground, break out to descent phase
    if adjustedRadar < stopDist + 200 and alt:radar < 3000 {
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

  local safetyMargin is 10.
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

    local targetVspd is max(-12, -0.5 - (radar / 30)).

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
    if radar < 8 and vSpd < -3 {
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
  logChatter("Crew", "Touchdown! We are safe on the surface.").
  logChatter("CapCom", "Superb landing, Mission Control is celebrating!").
  hudMsg("LANDED ON MUN!", rgb(0,1,0)).
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
