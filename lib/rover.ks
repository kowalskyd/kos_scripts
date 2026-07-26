//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROVER CONTROL AND NAVIGATION LIBRARY
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global lastScienceBiome is "".

// Suffix helper for padding
local function padRight {
  parameter str, length.
  local padded is "" + str.
  until padded:length >= length {
    set padded to padded + " ".
  }
  return padded.
}

// Queries surface sector / biome safely without crashing across kOS versions
global function getCurrentBiome {
  // 1. Try SCANsat addon if installed
  if defined addons and addons:hasSuffix("scansat") {
    return addons:scansat:currentbiome().
  }
  
  // 2. Try to extract biome from active science experiment data
  for p in ship:parts {
    for m in p:modules {
      if m = "ModuleScienceExperiment" {
        local exp is p:getModule("ModuleScienceExperiment").
        if exp:hasdata and exp:data:length > 0 {
          local title is exp:data[0]:title.
          if title:contains(" from ") {
            return title:split(" from ")[1].
          }
        }
      }
    }
  }
  
  // 3. Coordinate Sector Fallback (Unique 0.05-deg geographical grid cell)
  local sectorLat is round(ship:geoposition:lat * 20) / 20.
  local sectorLng is round(ship:geoposition:lng * 20) / 20.
  return "Sector (" + sectorLat + ", " + sectorLng + ")".
}

// Checks if the Sun is above the horizon at the rover's current location
global function isSunUp {
  local sunVec is body("Sun"):position.
  local sunAngle is vAng(sunVec, ship:up:vector).
  return sunAngle < 89.0. // Sun above horizon (with 1-deg horizon margin)
}

// Helper to query current amount and max capacity of Electric Charge
global function getECInfo {
  local curEC is ship:electriccharge.
  local maxEC is 0.
  for res in ship:resources {
    if res:name = "ELECTRICCHARGE" {
      set curEC to res:amount.
      set maxEC to res:capacity.
    }
  }
  return list(curEC, maxEC).
}

// Long-Range Terrain Radar: Scans slope and elevation delta at specified distance and angle offset
global function scanSlopeAhead {
  parameter angleOffset is 0. // Offset angle in degrees relative to current heading
  parameter lookDist is 100.   // Lookahead distance in meters

  local currentGeo is ship:geoposition.
  local testHeading is mod(ship:heading + angleOffset + 360, 360).
  local testDirVec is heading(testHeading, 0):vector.
  
  local aheadGeoPos is ship:body:geopositionof(ship:position + testDirVec * lookDist).
  local hDiff is aheadGeoPos:terrainheight - currentGeo:terrainheight.
  local aheadSlope is arctan2(hDiff, lookDist).
  
  return list(aheadSlope, hDiff, aheadGeoPos).
}

// Toggles vessel-wide hibernation mode (probe core hibernation, torque cutoff, wheel motor cutoff, light dimming)
global function setHibernation {
  parameter enable.
  
  if enable {
    hudText("HIBERNATION: Powering down probe core, torque & wheel motors...", 4, 2, 25, rgb(0.8, 0.4, 1.0), false).
    lights off.
    sas off.
    brakes on.
    
    // Unlock steering & throttle so wheel motors release power draw
    unlock wheelsteering.
    unlock wheelthrottle.
    set ship:control:pilotmainthrottle to 0.

    for p in ship:parts {
      if p:hasmodule("ModuleReactionWheel") {
        local rw is p:getModule("ModuleReactionWheel").
        if rw:hasevent("toggle wheel state") {
          rw:setField("wheel state", "Disabled").
        }
      }
      
      if p:hasmodule("ModuleCommand") {
        local cmd is p:getModule("ModuleCommand").
        if cmd:hasfield("hibernate") {
          cmd:setField("hibernate", true).
        } else if cmd:hasfield("hibernation") {
          cmd:setField("hibernation", true).
        }
      }

      if p:hasmodule("ModuleWheelMotor") {
        local m is p:getModule("ModuleWheelMotor").
        if m:hasevent("disable motor") {
          m:doEvent("disable motor").
        }
      }
    }
  } else {
    // Wake up systems from hibernation
    for p in ship:parts {
      if p:hasmodule("ModuleCommand") {
        local cmd is p:getModule("ModuleCommand").
        if cmd:hasfield("hibernate") {
          cmd:setField("hibernate", false).
        } else if cmd:hasfield("hibernation") {
          cmd:setField("hibernation", false).
        }
      }
      
      if p:hasmodule("ModuleReactionWheel") {
        local rw is p:getModule("ModuleReactionWheel").
        if rw:hasevent("toggle wheel state") {
          rw:setField("wheel state", "Normal").
        }
      }

      if p:hasmodule("ModuleWheelMotor") {
        local m is p:getModule("ModuleWheelMotor").
        if m:hasevent("enable motor") {
          m:doEvent("enable motor").
        }
      }
    }
    
    sas on.
    lights on.
    hudText("Waking systems from hibernation!", 4, 2, 20, rgb(0.2, 1.0, 0.4), false).
  }
}

// Auto-upright recovery if rover flips or tumbles onto its roof
global function recoverFromFlip {
  local currentTilt is vAng(ship:up:vector, ship:facing:topvector).
  if currentTilt > 45 {
    hudText("WARNING: Rover flip detected! Attempting auto-upright...", 5, 2, 25, rgb(1, 0.2, 0.2), false).
    brakes on.
    set targetThrottle to 0.
    unlock wheelsteering.
    unlock wheelthrottle.
    
    // Enable SAS reaction wheel torque impulse to flip back onto wheels
    sas on.
    set ship:control:roll to 1.0.
    set ship:control:pitch to 1.0.
    wait 0.8.
    set ship:control:roll to -1.0.
    set ship:control:pitch to -1.0.
    wait 0.8.
    set ship:control:neutral to true.
    
    wait until vAng(ship:up:vector, ship:facing:topvector) < 25 or ship:groundspeed < 0.1.
    brakes off.
  }
}

// Mid-Air Jump Stabilizer: Levels reaction wheels while airborne for safe 4-wheel touchdown
global function handleAirborne {
  if not (ship:status = "LANDED" or ship:status = "SPLASHED") {
    hudText("AIRBORNE JUMP DETECTED! Aligning wheels for touchdown...", 4, 2, 25, rgb(1, 0.5, 0.0), false).
    brakes off. // Allow wheels to rotate freely on landing impact
    set targetThrottle to 0.
    sas on.

    until ship:status = "LANDED" or ship:status = "SPLASHED" {
      local airPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
      local airRoll is 90 - vAng(ship:up:vector, ship:facing:starvector).
      
      // Active reaction wheel torque to keep roof facing UP and belly facing DOWN
      set ship:control:pitch to min(1.0, max(-1.0, -airPitch * 0.1)).
      set ship:control:roll to min(1.0, max(-1.0, -airRoll * 0.1)).
      wait 0.05.
    }

    set ship:control:neutral to true.
    brakes on.
    hudText("TOUCHDOWN! Rover stabilized.", 3, 2, 20, rgb(0.2, 1.0, 0.4), false).
    wait 0.5.
    brakes off.
  }
}

// Executes a 60-degree detour around crater rims / steep ridge drop-offs
global function executeRidgeDetour {
  hudText("CLIFF DETECTED: Executing 60-deg ridge detour...", 4, 2, 25, rgb(1, 0.5, 0.0), false).
  brakes on.
  set targetThrottle to 0.
  unlock wheelsteering.
  unlock wheelthrottle.
  wait 0.8.

  // 1. Reverse 12 meters back from the cliff edge to clear danger zone
  brakes off.
  lock wheelthrottle to -0.35.
  local reverseStart is time:seconds.
  wait until (time:seconds - reverseStart > 3.5) or not (ship:status = "LANDED").
  
  brakes on.
  lock wheelthrottle to 0.
  wait 0.5.

  // 2. Calculate detour heading (60 deg to the right along crater rim)
  local currentHDG is ship:heading.
  local detourHDG is mod(currentHDG + 60, 360).
  local detourHeadingVector is heading(detourHDG, 0):vector.
  local detourGeo is ship:body:geopositionof(ship:position + detourHeadingVector * 45).

  hudText("Routing around crater rim...", 3, 2, 20, rgb(0.2, 0.8, 1.0), false).

  // 3. Drive 45 meters along detour path around the rim
  brakes off.
  local localThrottle is 0.
  lock wheelsteering to detourGeo.
  lock wheelthrottle to localThrottle.

  local detourStart is time:seconds.
  until (time:seconds - detourStart > 12) or (detourGeo:distance < 12) {
    local curSpd is ship:groundspeed.
    if curSpd < 4.0 {
      set localThrottle to 0.4.
    } else {
      set localThrottle to 0.
    }
    wait 0.1.
  }

  brakes on.
  lock wheelthrottle to 0.
  wait 0.5.
  hudText("Detour complete: Resuming waypoint navigation.", 3, 2, 20, rgb(0.2, 1.0, 0.4), false).
}

// Suspends movement and operations when the sun is down with automatic high-speed timewarp and vessel hibernation
global function waitForSunlight {
  if not isSunUp() {
    hudText("NIGHTTIME DETECTED: Suspending movement & entering hibernation...", 5, 2, 25, rgb(1, 0.5, 0.0), false).
    brakes on.
    set targetThrottle to 0.
    unlock wheelsteering.
    unlock wheelthrottle.
    wait until ship:groundspeed < 0.05. // Ensure rover is completely stationary before timewarp

    // Engage vessel-wide hibernation mode
    setHibernation(true).

    // Switch to RAILS timewarp for high-speed warp across the night
    set kuniverse:timewarp:mode to "RAILS".
    wait 0.2.

    until isSunUp() {
      local ecData is getECInfo().
      local sunAngle is round(vAng(body("Sun"):position, ship:up:vector), 1).

      local targetWarp is 5.
      if sunAngle < 92 {
        set targetWarp to 1.
      } else if sunAngle < 105 {
        set targetWarp to 3.
      }

      if kuniverse:timewarp:issettled and kuniverse:timewarp:warp <> targetWarp {
        set kuniverse:timewarp:warp to targetWarp.
      }

      local ecPct is 100.
      if ecData[1] > 0 { set ecPct to round((ecData[0] / ecData[1]) * 100). }

      print "--- Night Mode (Hibernation & Auto-Warp Active) ---" at (0, 7).
      print "Sun Angle:  " + padRight(sunAngle + " deg (Waiting < 89)", 30) at (0, 8).
      print "E.Charge:   " + padRight(round(ecData[0]) + "/" + round(ecData[1]) + " (" + ecPct + "%)", 30) at (0, 9).
      print "                                                                " at (0, 10).
      wait 0.2.
    }

    set kuniverse:timewarp:rate to 1.
    wait until kuniverse:timewarp:rate = 1.
    
    // Restore systems from hibernation
    setHibernation(false).

    print "                                                                " at (0, 7).
    print "                                                                " at (0, 8).
    print "                                                                " at (0, 9).
  }
}

// Waits until Electric Charge (EC) is fully recharged (>= 98%) with zero-power hibernation & automatic timewarp
global function waitForFullEC {
  local ecData is getECInfo().
  local curEC is ecData[0].
  local maxEC is ecData[1].

  if maxEC <= 0 { return. }
  
  if (curEC / maxEC) < 0.95 {
    hudText("Charging batteries (High-Speed Auto-Warp)...", 4, 2, 20, rgb(1, 0.8, 0.2), false).
    brakes on.
    set targetThrottle to 0.
    unlock wheelsteering.
    unlock wheelthrottle.
    wait until ship:groundspeed < 0.05.

    if not isSunUp() {
      waitForSunlight().
    }

    // Engage zero-power hibernation mode during battery charging
    setHibernation(true).

    set kuniverse:timewarp:mode to "RAILS".
    wait 0.2.

    if kuniverse:timewarp:issettled {
      set kuniverse:timewarp:warp to 4. // 100x high-speed warp
    }

    until false {
      set ecData to getECInfo().
      set curEC to ecData[0].
      set maxEC to ecData[1].

      if maxEC <= 0 or (curEC / maxEC) >= 0.98 {
        break.
      }

      if not isSunUp() {
        set kuniverse:timewarp:rate to 1.
        wait until kuniverse:timewarp:rate = 1.
        setHibernation(false).
        waitForSunlight().
        setHibernation(true).
      }

      if kuniverse:timewarp:issettled and kuniverse:timewarp:warp < 4 {
        set kuniverse:timewarp:warp to 4.
      }

      local ecPct is 100.
      if maxEC > 0 { set ecPct to round((curEC / maxEC) * 100). }

      print "--- Charging Batteries (Hibernation Active) ---" at (0, 7).
      print "E.Charge:   " + padRight(round(curEC) + "/" + round(maxEC) + " (" + ecPct + "%)", 30) at (0, 8).
      print "                                                                " at (0, 9).
      wait 0.2.
    }

    set kuniverse:timewarp:rate to 1.
    wait until kuniverse:timewarp:rate = 1.

    // Wake up from hibernation
    setHibernation(false).

    print "                                                                " at (0, 7).
    print "                                                                " at (0, 8).
    hudText("Batteries fully charged!", 3, 2, 20, rgb(0.2, 1.0, 0.4), false).
  }
}

global function driveToCoordinates {
  parameter targetLat.
  parameter targetLng.
  parameter maxSpeed is 10. // m/s (Fast cruising)
  parameter arrivalRadius is 15. // meters
  parameter autoCollectBiomes is true.

  // Check sunlight and EC before beginning drive
  waitForSunlight().
  waitForFullEC().
  local minDistToTarget is latlng(targetLat, targetLng):distance.
  local timeOfBestDist is time:seconds.
  local detourCount is 0.

  if lastScienceBiome = "" {
    set lastScienceBiome to getCurrentBiome().
  }

  local targetGeo is latlng(targetLat, targetLng).
  
  hudText("Heading to waypoint: Lat " + round(targetLat, 4) + ", Lng " + round(targetLng, 4), 3, 2, 20, rgb(0.2, 0.8, 0.2), false).
  
  brakes off.
  
  // Enable SAS to help stabilize reaction wheel anti-roll
  sas on.

  // Set up kOS steering and throttle manager for rovers
  local targetThrottle is 0.
  lock wheelsteering to targetGeo.
  lock wheelthrottle to targetThrottle.
  
  until false {
    // Check for airborne jumps / launches
    if not (ship:status = "LANDED" or ship:status = "SPLASHED") {
      handleAirborne().
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // Low battery (15%) emergency check during driving
    local ecCheck is getECInfo().
    if ecCheck[1] > 0 and (ecCheck[0] / ecCheck[1]) < 0.15 {
      hudText("LOW BATTERY (15%): Pausing drive to recharge...", 4, 2, 20, rgb(1, 0.5, 0.0), false).
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      waitForFullEC().
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // Nighttime check: pause driving if sun goes down
    if not isSunUp() {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      waitForSunlight().
      waitForFullEC().
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // Check for Biome boundary crossings during drive
    local currentBiome is getCurrentBiome().
    if autoCollectBiomes and lastScienceBiome <> "" and currentBiome <> lastScienceBiome {
      hudText("NEW BIOME ENTERED: " + currentBiome:toUpper() + "!", 4, 2, 20, rgb(0.2, 1.0, 0.4), false).
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      
      runScienceExperiments().
      set lastScienceBiome to currentBiome.
      
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    local dist is targetGeo:distance.
    local curSpeed is ship:groundspeed.
    local bearingTo is targetGeo:bearing. // relative angle to target (-180 to 180)
    
    // Track closest approach distance to waypoint
    if dist < (minDistToTarget - 5) {
      set minDistToTarget to dist.
      set timeOfBestDist to time:seconds.
    }

    // Arrival Condition 1: Direct reach (dist < arrivalRadius)
    if dist < arrivalRadius {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      hudText("Arrived at waypoint!", 3, 2, 20, rgb(0.2, 0.8, 0.2), false).
      break.
    }
    
    // Arrival Condition 2: Best-Approach Acceptance (Inaccessible Waypoint)
    // If target sits in a crater/cliff and we cannot get closer than ~250m after 40s or 3 detours
    local timeStagnant is time:seconds - timeOfBestDist.
    if (dist < 300 or minDistToTarget < 300) and (timeStagnant > 40 or detourCount >= 3) {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      hudText("WAYPOINT INACCESSIBLE (Best Approach: " + round(minDistToTarget, 1) + "m). Gathering science here!", 5, 2, 25, rgb(0.2, 1.0, 0.4), false).
      wait until ship:groundspeed < 0.2.
      runScienceExperiments().
      break.
    }
    
    // Pitch: nose-up/down tilt relative to horizontal
    local currentPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
    // Total tilt: tilt of the rover's roof relative to vertical
    local currentTilt is vAng(ship:up:vector, ship:facing:topvector).
    
    // Check for flip / rollover hazard
    if currentTilt > 45 {
      recoverFromFlip().
    } else if abs(currentPitch) > 22 or currentTilt > 22 {
      // Steep incline hazard: slow down / stop until settled
      brakes on.
      set targetThrottle to 0.
      hudText("STEEP INCLINE: Regulating speed for safety...", 3, 2, 20, rgb(1, 0.5, 0.0), false).
      wait until abs(90 - vAng(ship:up:vector, ship:facing:forevector)) <= 18 and vAng(ship:up:vector, ship:facing:topvector) <= 18.
      brakes off.
    }

    // Long-Range 100-Meter Raycast Terrain Scanner
    local scanCenter is scanSlopeAhead(0, 100).
    local aheadSlope is scanCenter[0].
    local hDiff is scanCenter[1].

    // Detect steep climb (>12 deg) or steep drop-off/cliff (< -10 deg) or > 8m height jump 100m ahead
    if aheadSlope > 12 or aheadSlope < -10 or abs(hDiff) > 8 {
      set detourCount to detourCount + 1.
      hudText("OBSTACLE 100M AHEAD (Slope " + round(aheadSlope, 1) + " deg)! Full stop for 30-deg detour...", 4, 2, 25, rgb(1, 0.5, 0.0), false).
      
      // FULL STOP BRAKING before executing detour turn
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      wait until ship:groundspeed < 0.2.
      wait 0.5.

      // Probe Left (-30 deg) and Right (+30 deg) slope alternatives 100m ahead
      local scanRight is scanSlopeAhead(30, 100).
      local scanLeft is scanSlopeAhead(-30, 100).
      
      local absSlopeRight is abs(scanRight[0]).
      local absSlopeLeft is abs(scanLeft[0]).

      // Pick flatter side for detour
      local detourOffset is 30.
      if absSlopeLeft < absSlopeRight {
        set detourOffset to -30.
      }

      local detourHDG is mod(ship:heading + detourOffset + 360, 360).
      local detourDirVec is heading(detourHDG, 0):vector.
      local detourGeo is ship:body:geopositionof(ship:position + detourDirVec * 90).

      hudText("Steering " + round(detourOffset) + " deg detour around obstacle for 90m...", 3, 2, 20, rgb(0.2, 0.8, 1.0), false).

      // Execute 90-meter detour leg in chosen direction
      brakes off.
      local detourThrottle is 0.
      lock wheelsteering to detourGeo.
      lock wheelthrottle to detourThrottle.

      local legStart is time:seconds.
      until (time:seconds - legStart > 18) or (detourGeo:distance < 15) {
        if not (ship:status = "LANDED") { handleAirborne(). }
        local curSpd is ship:groundspeed.
        if curSpd < 4.5 {
          set detourThrottle to 0.4.
        } else {
          set detourThrottle to 0.
        }
        wait 0.1.
      }

      brakes on.
      set targetThrottle to 0.
      wait 0.5.
      brakes off.

      hudText("Detour leg complete. Re-probing target path...", 3, 2, 20, rgb(0.2, 1.0, 0.4), false).
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // Dynamic Pre-Turn Deceleration & Speed Governor
    local safeSpeed is maxSpeed.

    if abs(bearingTo) > 35 {
      set safeSpeed to min(safeSpeed, 2.5). // Tight cornering speed limit (2.5 m/s)
    } else if abs(bearingTo) > 12 {
      set safeSpeed to min(safeSpeed, 3.5). // Moderate cornering speed limit (3.5 m/s)
    }

    if aheadSlope > 18 or hDiff > 6 {
      set safeSpeed to min(safeSpeed, 3.5). // Hill crest speed limit
    }

    if abs(currentPitch) > 10 or currentTilt > 10 {
      set safeSpeed to min(safeSpeed, 4.0). // Slope speed limit
    }
    
    // Pre-Turn Active Deceleration: Tap brakes if approaching a turn at high speed
    if abs(bearingTo) > 12 and curSpeed > (safeSpeed + 0.8) {
      brakes on.
      set targetThrottle to 0.
    } else if curSpeed < safeSpeed {
      brakes off.
      set targetThrottle to min(1.0, (safeSpeed - curSpeed) * 0.5 + 0.2).
    } else {
      brakes off.
      set targetThrottle to 0.
    }
    
    local ecData is getECInfo().
    local ecCur is ecData[0].
    local ecMax is ecData[1].
    local ecPct is 100.
    if ecMax > 0 { set ecPct to round((ecCur / ecMax) * 100). }

    // Clean standalone telemetry display
    print "--- Rover Telemetry ---" at (0, 7).
    print "Biome:      " + padRight(currentBiome, 30) at (0, 8).
    print "Distance:   " + padRight(round(dist, 1) + " m", 30) at (0, 9).
    print "Speed:      " + padRight(round(curSpeed, 1) + " / " + round(safeSpeed, 1) + " m/s", 30) at (0, 10).
    print "100m Slope: " + padRight(round(aheadSlope, 1) + " deg", 30) at (0, 11).
    print "Pitch/Tilt: " + padRight(round(currentPitch, 1) + " / " + round(currentTilt, 1), 30) at (0, 12).
    print "E.Charge:   " + padRight(round(ecCur) + "/" + round(ecMax) + " (" + ecPct + "%)", 30) at (0, 13).
    
    wait 0.1.
  }
}

global function runScienceExperiments {
  // Ensure daylight and full battery before running experiments
  waitForSunlight().
  waitForFullEC().

  set lastScienceBiome to getCurrentBiome().

  hudText("Deploying science suite (" + lastScienceBiome + ")...", 3, 2, 20, rgb(0.2, 0.6, 1.0), false).

  local experimentsList is list().
  for p in ship:parts {
    for m in p:modules {
      if m = "ModuleScienceExperiment" {
        experimentsList:add(p:getModule("ModuleScienceExperiment")).
      }
    }
  }
  
  if experimentsList:length = 0 {
    print "No science experiments found on vessel." at (0, 14).
    return.
  }

  // Check antenna connection status
  local commsConnected is ship:connection:isconnected.
  
  for exp in experimentsList {
    // If experiment doesn't have data yet, deploy it
    if not exp:hasdata {
      exp:deploy().
      local startWait is time:seconds.
      wait until exp:hasdata or (time:seconds - startWait > 5).
    }
    
    // Transmit ONLY if antenna is connected to comms network
    if exp:hasdata and commsConnected {
      exp:transmit().
      local tStart is time:seconds.
      wait until (not exp:hasdata) or (time:seconds - tStart > 8).
    }
  }
  
  // Try to collect all stored data into the ship's science container (ESU)
  local containerList is ship:modulesNamed("ModuleScienceContainer").
  if containerList:length > 0 {
    local container is containerList[0].
    if container:hasaction("collect all") {
      container:doAction("collect all", true).
    } else if container:hasevent("collect all") {
      container:doEvent("collect all").
    } else if container:hasevent("container: collect all") {
      container:doEvent("container: collect all").
    }
    wait 1.0.
  }

  // Out-of-Comms / Reset Safety Handler:
  // If sensors STILL hold untransmitted data (because vessel is out of comms range),
  // reset/dump the sensor so individual parts are cleared for the next waypoint.
  for exp in experimentsList {
    if exp:hasdata {
      hudText("Out of Comms Range: Clearing sensor for next waypoint...", 3, 2, 20, rgb(1, 0.6, 0.0), false).
      if exp:hasevent("reset experiment") {
        exp:doEvent("reset experiment").
      } else if exp:hasevent("reset") {
        exp:doEvent("reset").
      } else if exp:hasaction("reset") {
        exp:doAction("reset", true).
      } else if exp:hasevent("discard data") {
        exp:doEvent("discard data").
      } else if exp:hasevent("dump data") {
        exp:doEvent("dump data").
      }
    }
  }
  
  hudText("Science processed for: " + lastScienceBiome, 3, 2, 20, rgb(0.2, 1.0, 0.4), false).
}
