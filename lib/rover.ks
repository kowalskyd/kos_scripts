//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROVER CONTROL AND AUTONOMOUS NAVIGATION LIBRARY
// (Curiosity / Perseverance Predictive DEM Architecture)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global lastScienceBiome is "".
global autonavGrid is list().
global autonavBestOffset is 0.
global autonavLowestCost is 0.
global autonavWaypointIndex is 1.
global autonavStartGeo is ship:geoposition.

// Suffix helper for padding text in HUD telemetry
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
    local scanAddon is addons:scansat.
    if scanAddon:hasSuffix("currentbiome") {
      return scanAddon:currentbiome().
    } else if scanAddon:hasSuffix("biome") {
      return scanAddon:biome(ship:geoposition).
    }
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

// Safe SCANsat slope query helper
global function getSCANsatSlope {
  parameter lat, lng.
  if defined addons and addons:hasSuffix("scansat") {
    local scanAddon is addons:scansat.
    local geo is latlng(lat, lng).
    local sVal is 0.
    if scanAddon:hasSuffix("slope") {
      set sVal to scanAddon:slope(ship:body, geo).
    } else if scanAddon:hasSuffix("scansatslope") {
      set sVal to scanAddon:scansatslope(ship:body, geo).
    } else if scanAddon:hasSuffix("slopefor") {
      set sVal to scanAddon:slopefor(ship:body, geo).
    }
    if sVal < 0 or sVal > 89 { return 0. }
    return sVal.
  }
  return 0.
}

//_________________________________________________
// 1. DYNAMIC TERRAIN DEM GRID & COST MAPPING
//_________________________________________________

// Samples a 5x5 forward-oriented terrain grid (0 to 30m ahead, +/- 12m lateral)
global function sampleTerrainCostGrid {
  parameter forwardSpan is 30.
  parameter sideSpan is 12.

  local grid is list().
  local roverGeo is ship:geoposition.
  local roverH is roverGeo:terrainheight.
  local foreVec is ship:facing:forevector.
  local starVec is ship:facing:starvector.

  local fwdSteps is 5.
  local sideSteps is 5.
  local dFwd is forwardSpan / fwdSteps.
  local dSide is (sideSpan * 2) / (sideSteps - 1).

  from { local i is 1. } until i > fwdSteps step { set i to i + 1. } do {
    local distFwd is i * dFwd.
    from { local j is 0. } until j >= sideSteps step { set j to j + 1. } do {
      local distSide is -sideSpan + (j * dSide).
      
      local cellPos is ship:position + foreVec * distFwd + starVec * distSide.
      local cellGeo is ship:body:geopositionof(cellPos).
      local cellH is cellGeo:terrainheight.
      local hDiff is cellH - roverH.
      local distTotal is sqrt(distFwd^2 + distSide^2).
      local slope is arctan2(hDiff, distTotal).

      // SCANsat global macro slope check if available
      local macroSlope is getSCANsatSlope(cellGeo:lat, cellGeo:lng).

      // Micro-cliff check: Limit total elevation difference scaled by distance (e.g., max 0.25m rise per meter forward)
      local maxAllowedHDiff is max(1.5, distTotal * 0.25).

      // Impassable hazard criteria: >18 deg slope climb, <-15 deg drop, micro-cliff > maxAllowedHDiff, or SCANsat macro slope >22 deg
      local isImpassable is false.
      if slope > 18 or slope < -15 or abs(hDiff) > maxAllowedHDiff or macroSlope > 22 {
        set isImpassable to true.
      }

      // Cost calculation formula
      local cellCost is abs(slope) * 2.0 + abs(hDiff) * 3.0 + abs(distSide) * 0.10 + macroSlope * 1.0.
      if isImpassable { set cellCost to 9999. }

      local cell is lexicon().
      set cell["fwd"] to distFwd.
      set cell["side"] to distSide.
      set cell["geo"] to cellGeo.
      set cell["slope"] to slope.
      set cell["hDiff"] to hDiff.
      set cell["cost"] to cellCost.
      set cell["impassable"] to isImpassable.

      grid:add(cell).
    }
  }
  return grid.
}

// Evaluates candidate headings (-60 to +60 deg) across the DEM cost grid to pick best route
global function calculateCuriosityPath {
  parameter targetGeo.
  parameter grid.

  local baseHDG is targetGeo:heading. // True compass heading toward waypoint
  local candidateOffsets is list(0, 15, -15, 30, -30, 45, -45, 60, -60).

  local bestHDG is baseHDG.
  local bestOffset is 0.
  local lowestCost is 99999.

  for offset in candidateOffsets {
    local testHDG is mod(baseHDG + offset + 360, 360).
    local testVec is heading(testHDG, 0):vector.

    local sumCost is 0.
    local cellCount is 0.
    local isSectorBlocked is false.

    // Check all grid cells inside this candidate heading cone
    for cell in grid {
      local cellDirVec is (cell["geo"]:position - ship:position):normalized.
      local angleToCell is vAng(testVec, cellDirVec).

      if angleToCell < 22.0 {
        if cell["impassable"] {
          set isSectorBlocked to true.
          break.
        }
        set sumCost to sumCost + cell["cost"].
        set cellCount to cellCount + 1.
      }
    }

    if not isSectorBlocked and cellCount > 0 {
      local avgCost is sumCost / cellCount.
      // Offset penalty: heavily penalize unnecessary detours when direct path is clear
      local totalCost is avgCost + (abs(offset) * 1.5).

      if totalCost < lowestCost {
        set lowestCost to totalCost.
        set bestHDG to testHDG.
        set bestOffset to offset.
      }
    }
  }

  // Fallback: If all forward rays blocked, detour 75 degrees away from worst hazard
  if lowestCost >= 9000 {
    set bestHDG to mod(ship:heading + 75, 360).
    set bestOffset to 75.
  }

  // Flag grid cells along chosen best heading vector for 2D radar visualization
  local chosenVec is heading(bestHDG, 0):vector.
  for cell in grid {
    local cellDirVec is (cell["geo"]:position - ship:position):normalized.
    if vAng(chosenVec, cellDirVec) < 22.0 {
      set cell["isPath"] to true.
    }
  }

  return list(bestHDG, lowestCost, bestOffset).
}

//_________________________________________________
// 2. POINT TURN & STRAIGHT DRIVE CONTROLS
//_________________________________________________

// Active braking helper: Brings rover to absolute groundspeed < 0.05 m/s using brakes and active reverse pulses
global function executeFullStop {
  parameter statusMsg is "Full Stop".

  brakes on.
  set ship:control:pilotmainthrottle to 0.
  unlock wheelthrottle.
  lock wheelthrottle to 0.

  local stopStart is time:seconds.
  until ship:groundspeed < 0.05 or (time:seconds - stopStart > 5.0) {
    // Apply gentle reverse pulse on low-g bodies (Mun/Minmus) if skidding above 0.3 m/s
    if ship:groundspeed > 0.3 {
      lock wheelthrottle to -0.25.
    } else {
      lock wheelthrottle to 0.
    }
    updateRoverTelemetry(ship:geoposition, statusMsg + " (" + round(ship:groundspeed, 2) + " m/s)").
    wait 0.05.
  }

  lock wheelthrottle to 0.
  brakes on.
  wait 0.3.
}

// Zero-speed point turn execution toward target heading
global function executePointTurn {
  parameter targetHDG.
  parameter statusMsg is "Point Turn".

  local hdgDiff is mod(targetHDG - ship:heading + 540, 360) - 180.
  if abs(hdgDiff) < 4.0 { return. }

  // Slow down first if moving faster than 1.2 m/s before executing turn correction
  if ship:groundspeed > 1.2 {
    brakes on.
    lock wheelthrottle to 0.
    wait until ship:groundspeed < 1.0 or not brakes.
    brakes off.
  }

  local gRatio is 1.0.
  if defined rosGetGravityRatio { set gRatio to rosGetGravityRatio(). }
  local turnThrottleHi is min(0.35, max(0.08, 0.18 * gRatio)).
  local turnThrottleLo is min(0.12, max(0.04, 0.08 * gRatio)).

  sas on.
  lock wheelsteering to targetHDG.

  local turnStart is time:seconds.
  until abs(mod(targetHDG - ship:heading + 540, 360) - 180) < 3.5 or (time:seconds - turnStart > 7.0) {
    brakes off.
    local currentDiff is abs(mod(targetHDG - ship:heading + 540, 360) - 180).
    
    if ship:groundspeed > 1.5 {
      lock wheelthrottle to 0.
    } else if currentDiff > 18 {
      lock wheelthrottle to turnThrottleHi.
    } else {
      lock wheelthrottle to turnThrottleLo.
    }

    if defined rosUpdateTelemetry {
      rosUpdateTelemetry(ship:geoposition, statusMsg + " (" + round(ship:heading, 1) + " -> " + round(targetHDG, 1) + " deg)").
    } else {
      updateRoverTelemetry(ship:geoposition, statusMsg + " (" + round(ship:heading, 1) + " -> " + round(targetHDG, 1) + " deg)").
    }
    wait 0.05.
  }

  lock wheelthrottle to 0.
  wait 0.05.
}

//_________________________________________________
// 3. HAZARD MONITORING & RECOVERY (ROLL / PITCH / SLIP)
//_________________________________________________

// Evaluates Pitch and Roll angles separately for rollover and steep slope hazards
global function checkTiltHazards {
  local currentPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
  local currentRoll  is 90 - vAng(ship:up:vector, ship:facing:starvector).

  local maxClimb is 20.0.
  if defined rosGetMaxClimbAngle { set maxClimb to rosGetMaxClimbAngle(). }
  local maxRollThreshold is max(22.0, maxClimb + 2.0).

  if abs(currentRoll) > maxRollThreshold {
    return list(true, "CRITICAL ROLL TILT (" + round(currentRoll, 1) + " deg)", currentRoll, currentPitch).
  } else if abs(currentPitch) > (maxRollThreshold + 5.0) {
    return list(true, "STEEP PITCH INCLINE (" + round(currentPitch, 1) + " deg)", currentRoll, currentPitch).
  }

  return list(false, "OK", currentRoll, currentPitch).
}

// Handles emergency halt and down-slope point turn on high roll tilt
global function executeRollHazardRecovery {
  parameter rollVal.

  hudText("CRITICAL ROLL HAZARD (" + round(rollVal, 1) + " deg)! Emergency Halting...", 4, 2, 25, rgb(1, 0, 0), true).
  brakes on.
  lock wheelthrottle to 0.
  wait 0.5.

  // 1. Reverse 3 meters straight back
  brakes off.
  lock wheelthrottle to -0.30.
  local revStart is time:seconds.
  wait until (time:seconds - revStart > 2.5) or (ship:groundspeed < 0.05 and time:seconds - revStart > 0.8).

  brakes on.
  lock wheelthrottle to 0.
  wait 0.4.

  // 2. Point turn down-slope to stabilize center of mass
  local rollSign is 1.
  if rollVal < 0 { set rollSign to -1. }
  local downSlopeHDG is mod(ship:heading + (80 * rollSign) + 360, 360).
  executePointTurn(downSlopeHDG, "Roll Recovery Turn").
}

// Visual Odometry slip detection (compares wheel throttle vs ground speed)
global function checkWheelSlip {
  parameter appliedThrottle.
  parameter currentSlipTimer.

  if appliedThrottle > 0.15 and ship:groundspeed < 0.15 {
    return currentSlipTimer + 0.1.
  }
  return 0.
}

// Unstick recovery sequence when wheel traction is lost
global function executeSlipRecovery {
  hudText("TRACTION LOSS / WHEEL SLIP DETECTED! Reversing...", 4, 2, 25, rgb(1, 0.5, 0), true).
  brakes on.
  lock wheelthrottle to 0.
  wait 0.5.

  // 1. Reverse 3.5 meters
  brakes off.
  lock wheelthrottle to -0.35.
  local revStart is time:seconds.
  wait until (time:seconds - revStart > 3.0) or (ship:groundspeed < 0.05 and time:seconds - revStart > 1.0).

  brakes on.
  lock wheelthrottle to 0.
  wait 0.4.

  // 2. Point turn 45 degrees to side to clear obstacle
  local detourHDG is mod(ship:heading + 45, 360).
  executePointTurn(detourHDG, "Unstick Detour").
}

//_________________________________________________
// 4. HIBERNATION, AIRBORNE & BATTERY MANAGEMENT
//_________________________________________________

// Toggles vessel-wide hibernation mode (probe core hibernation, torque cutoff, wheel motor cutoff, light dimming)
global function setHibernation {
  parameter enable.
  
  if enable {
    lights off.
    sas off.
    brakes on.
    
    unlock wheelsteering.
    unlock wheelthrottle.
    set ship:control:neutral to true.
    set ship:control:pilotmainthrottle to 0.

    for p in ship:parts {
      if p:hasmodule("ModuleReactionWheel") {
        local rw is p:getModule("ModuleReactionWheel").
        if rw:hasevent("toggle wheel state") {
          rw:setField("wheel state", "Disabled").
        } else if rw:hasaction("toggle wheel state") {
          rw:doAction("toggle wheel state", true).
        }
      }
      
      // ModuleCommand hibernation is intentionally skipped to prevent shutting down the kOS CPU
      if p:hasmodule("ModuleCommand") {
        // Core kept active for kOS CPU execution
      }

      if p:hasmodule("ModuleWheelMotor") {
        local m is p:getModule("ModuleWheelMotor").
        if m:hasevent("disable motor") {
          m:doEvent("disable motor").
        } else if m:hasaction("disable motor") {
          m:doAction("disable motor", true).
        }
      }
    }
  } else {
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
        } else if rw:hasaction("toggle wheel state") {
          rw:doAction("toggle wheel state", true).
        }
      }

      if p:hasmodule("ModuleWheelMotor") {
        local m is p:getModule("ModuleWheelMotor").
        if m:hasevent("enable motor") {
          m:doEvent("enable motor").
        } else if m:hasaction("enable motor") {
          m:doAction("enable motor", true).
        }
      }
    }
    
    sas on.
    lights on.
  }
}

// Auto-upright recovery if rover flips onto roof
global function recoverFromFlip {
  local currentTilt is vAng(ship:up:vector, ship:facing:topvector).
  if currentTilt > 45 {
    brakes on.
    unlock wheelsteering.
    unlock wheelthrottle.
    
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

// Mid-Air Jump Stabilizer: Levels reaction wheels while airborne for safe touchdown
global function handleAirborne {
  if not (ship:status = "LANDED" or ship:status = "SPLASHED") {
    brakes off.
    sas on.

    until ship:status = "LANDED" or ship:status = "SPLASHED" {
      local airPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
      local airRoll is 90 - vAng(ship:up:vector, ship:facing:starvector).
      
      set ship:control:pitch to min(1.0, max(-1.0, -airPitch * 0.1)).
      set ship:control:roll to min(1.0, max(-1.0, -airRoll * 0.1)).
      wait 0.05.
    }

    set ship:control:neutral to true.
    brakes on.
    wait 0.5.
    brakes off.
  }
}

// Suspends movement when sun is down with timewarp & hibernation
global function waitForSunlight {
  if not isSunUp() {
    brakes on.
    unlock wheelsteering.
    unlock wheelthrottle.
    
    setHibernation(true).

    local waitStart is time:seconds.
    until ship:groundspeed < 0.1 or (time:seconds - waitStart > 3) {
      wait 0.1.
    }

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

      if defined rosUpdateTelemetry {
        rosUpdateTelemetry(ship:geoposition, "Night Mode (Waiting for Sunlight)").
      } else {
        print "--- Night Mode (Hibernation & Auto-Warp Active) ---" at (0, 7).
        print "Sun Angle:  " + padRight(sunAngle + " deg (Waiting < 89)", 30) at (0, 8).
        print "E.Charge:   " + padRight(round(ecData[0]) + "/" + round(ecData[1]) + " (" + ecPct + "%)", 30) at (0, 9).
      }
      wait 0.2.
    }

    set kuniverse:timewarp:rate to 1.
    wait until kuniverse:timewarp:rate = 1.
    
    setHibernation(false).

    if not (defined rosUpdateTelemetry) {
      print "                                                                " at (0, 7).
      print "                                                                " at (0, 8).
      print "                                                                " at (0, 9).
    }
  }
}

// Recharges battery to >= 98% with zero-power hibernation
global function waitForFullEC {
  local ecData is getECInfo().
  local curEC is ecData[0].
  local maxEC is ecData[1].

  if maxEC <= 0 { return. }
  
  if (curEC / maxEC) < 0.95 {
    brakes on.
    unlock wheelsteering.
    unlock wheelthrottle.

    if not isSunUp() {
      waitForSunlight().
    }

    setHibernation(true).

    local waitStart is time:seconds.
    until ship:groundspeed < 0.1 or (time:seconds - waitStart > 3) {
      wait 0.1.
    }

    set kuniverse:timewarp:mode to "RAILS".
    wait 0.2.

    if kuniverse:timewarp:issettled {
      set kuniverse:timewarp:warp to 4.
    } else {
      set kuniverse:timewarp:mode to "PHYSICS".
      wait 0.2.
      if kuniverse:timewarp:issettled {
        set kuniverse:timewarp:warp to 3.
      }
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

      if kuniverse:timewarp:issettled {
        if kuniverse:timewarp:mode = "RAILS" and kuniverse:timewarp:warp < 4 {
          set kuniverse:timewarp:warp to 4.
        } else if kuniverse:timewarp:mode = "PHYSICS" and kuniverse:timewarp:warp < 3 {
          set kuniverse:timewarp:warp to 3.
        }
      }

      local ecPct is 100.
      if maxEC > 0 { set ecPct to round((curEC / maxEC) * 100). }

      if defined rosUpdateTelemetry {
        rosUpdateTelemetry(ship:geoposition, "Recharging Batteries (" + ecPct + "%)").
      } else {
        print "--- Charging Batteries (Hibernation Active) ---" at (0, 7).
        print "E.Charge:   " + padRight(round(curEC) + "/" + round(maxEC) + " (" + ecPct + "%)", 30) at (0, 8).
      }
      wait 0.2.
    }

    set kuniverse:timewarp:rate to 1.
    wait until kuniverse:timewarp:rate = 1.

    setHibernation(false).

    if not (defined rosUpdateTelemetry) {
      print "                                                                " at (0, 7).
      print "                                                                " at (0, 8).
    }
  }
}

//_________________________________________________
// 5. CONTINUOUS TELEMETRY HUD & NAVIGATION ENGINE
//_________________________________________________

// Live HUD display helper with 2D DEM Radar map and SCANsat status
global function updateRoverTelemetry {
  parameter targetGeo.
  parameter statusMsg is "".

  if defined rosUpdateTelemetry {
    rosUpdateTelemetry(targetGeo, statusMsg).
    return.
  }

  local curSpd is ship:groundspeed.
  local currentBiome is getCurrentBiome().
  local distTarget is targetGeo:distance.
  local distBase is autonavStartGeo:distance.
  local targetBearing is round(targetGeo:bearing, 1).

  local currentPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
  local currentRoll  is 90 - vAng(ship:up:vector, ship:facing:starvector).

  local surfaceG is ship:body:mu / (ship:body:radius^2).
  local gFactor is sqrt(max(0.1, surfaceG) / 9.81).
  local bodySpeedCap is max(1.6, 4.0 * gFactor).

  local ecData is getECInfo().
  local ecCur is ecData[0].
  local ecMax is ecData[1].
  local ecPct is 100.
  if ecMax > 0 { set ecPct to round((ecCur / ecMax) * 100). }

  local scansatStatus is "NOT DETECTED (kOS DEM)".
  if defined addons and addons:hasSuffix("scansat") {
    set scansatStatus to "CONNECTED (Active DEM)".
  }

  local impassableCount is 0.
  for cell in autonavGrid {
    if cell["impassable"] { set impassableCount to impassableCount + 1. }
  }

  local pathText is "Direct (0 deg)".
  if autonavBestOffset > 0 { set pathText to "Bypass Right (+" + autonavBestOffset + " deg)". }
  else if autonavBestOffset < 0 { set pathText to "Bypass Left (" + autonavBestOffset + " deg)". }

  local stabilityText is "[STABLE]".
  if abs(currentRoll) > 10 or abs(currentPitch) > 15 { set stabilityText to "[HAZARD]". }

  print "==================================================" at (0, 0).
  print "=== ROS 2 NAV2 AUTONAV MISSION CONTROL ===" at (0, 1).
  print "==================================================" at (0, 2).
  print "Waypoint Target: Waypoint #" + autonavWaypointIndex + "  [Lat:" + round(targetGeo:lat,2) + ", Lng:" + round(targetGeo:lng,2) + "]" at (0, 3).
  print "Target Distance: " + padRight(round(distTarget, 1) + " m (Bearing: " + targetBearing + " deg)", 30) at (0, 4).
  print "Dist from Base:  " + padRight(round(distBase, 1) + " m", 30) at (0, 5).
  print "Current Biome:   " + padRight(currentBiome, 30) at (0, 6).
  print "SCANsat Status:  " + padRight(scansatStatus, 30) at (0, 7).
  print "--------------------------------------------------" at (0, 8).
  print "Cruising Speed:  " + padRight(round(curSpd, 1) + " / " + round(bodySpeedCap, 1) + " m/s (" + ship:body:name + " g=" + round(surfaceG,2) + ")", 30) at (0, 9).
  print "Pitch / Roll:    " + padRight(round(currentPitch, 1) + " / " + round(currentRoll, 1) + " deg " + stabilityText, 32) at (0, 10).
  print "E.Charge:        " + padRight(round(ecCur) + "/" + round(ecMax) + " (" + ecPct + "%)", 30) at (0, 11).
  print "Nav Corridor:    " + padRight(pathText + " (Cost: " + round(autonavLowestCost,1) + ")", 30) at (0, 12).
  print "Hazards Scan:    " + padRight(impassableCount + " / " + autonavGrid:length + " cells blocked", 30) at (0, 13).
  print "--------------------------------------------------" at (0, 14).
  print "2D LOCAL TERRAIN RADAR MAP (0-30m Ahead):         " at (0, 15).

  if autonavGrid:length >= 25 {
    from { local row is 4. } until row < 0 step { set row to row - 1. } do {
      local rowStr is "  [ ".
      from { local col is 0. } until col >= 5 step { set col to col + 1. } do {
        local cellIdx is row * 5 + col.
        local cell is autonavGrid[cellIdx].
        if cell["impassable"] {
          set rowStr to rowStr + "#  ".
        } else if cell:haskey("isPath") and cell["isPath"] {
          set rowStr to rowStr + "*  ".
        } else if cell["cost"] > 10 {
          set rowStr to rowStr + "~  ".
        } else {
          set rowStr to rowStr + ".  ".
        }
      }
      set rowStr to rowStr + "]  " + ((row + 1) * 6) + "m".
      print padRight(rowStr, 48) at (0, 16 + (4 - row)).
    }
    print "        [^]  Rover (Heading " + round(ship:heading, 1) + " deg)   " at (0, 21).
  } else {
    print "  [ Grid map scanning... ]                        " at (0, 16).
    print "                                                  " at (0, 17).
    print "                                                  " at (0, 18).
    print "                                                  " at (0, 19).
    print "                                                  " at (0, 20).
    print "                                                  " at (0, 21).
  }

  print "--------------------------------------------------" at (0, 22).
  if statusMsg <> "" {
    print "Status: " + padRight(statusMsg, 40) at (0, 23).
  } else {
    print "                                                  " at (0, 23).
  }
}

// Main Curiosity-style step-based autonomous drive loop
global function driveToCoordinates {
  parameter targetLat.
  parameter targetLng.
  parameter maxSpeed is 4.0. // m/s (Curiosity cruise speed)
  parameter arrivalRadius is 12.0. // meters
  parameter autoCollectBiomes is true.
  parameter waypointIndex is 1.
  parameter startGeo is ship:geoposition.

  set autonavWaypointIndex to waypointIndex.
  set autonavStartGeo to startGeo.

  // Pre-drive battery and daylight check
  waitForSunlight().
  waitForFullEC().

  local targetGeo is latlng(targetLat, targetLng).
  local minDistToTarget is targetGeo:distance.
  local timeOfBestDist is time:seconds.
  local slipTimer is 0.

  if lastScienceBiome = "" {
    set lastScienceBiome to getCurrentBiome().
  }

  brakes off.
  sas on.

  local targetThrottle is 0.
  lock wheelsteering to targetGeo.
  lock wheelthrottle to targetThrottle.

  until false {
    // 1. Airborne check
    if not (ship:status = "LANDED" or ship:status = "SPLASHED") {
      handleAirborne().
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // 2. Battery & Night check
    local ecCheck is getECInfo().
    if (ecCheck[1] > 0 and (ecCheck[0] / ecCheck[1]) < 0.15) or not isSunUp() {
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

    // 3. Biome boundary crossing check
    local currentBiome is getCurrentBiome().
    if autoCollectBiomes and lastScienceBiome <> "" and currentBiome <> lastScienceBiome {
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
    if dist < (minDistToTarget - 4) {
      set minDistToTarget to dist.
      set timeOfBestDist to time:seconds.
    }

    // 4. Arrival condition
    if dist < arrivalRadius {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      wait until ship:groundspeed < 0.2.
      runScienceExperiments().
      break.
    }

    // 5. Stagnant progress fallback check
    local timeStagnant is time:seconds - timeOfBestDist.
    if (timeStagnant > 70 and dist < 400) or (timeStagnant > 45 and dist < 150) {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      wait until ship:groundspeed < 0.2.
      runScienceExperiments().
      break.
    }

    // 6. Pitch & Roll Hazard Enforcement
    local tiltHazard is checkTiltHazards().
    if tiltHazard[0] {
      if tiltHazard[1]:contains("ROLL") {
        executeRollHazardRecovery(tiltHazard[2]).
        lock wheelsteering to targetGeo.
        lock wheelthrottle to targetThrottle.
      }
    }

    // 7. Visual Odometry Slip Detection
    set slipTimer to checkWheelSlip(targetThrottle, slipTimer).
    if slipTimer > 3.0 {
      executeSlipRecovery().
      set slipTimer to 0.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // 8. Dynamic DEM Grid Scan & Path Evaluation
    set autonavGrid to sampleTerrainCostGrid(30, 12).
    local pathEval is calculateCuriosityPath(targetGeo, autonavGrid).
    local desiredHDG is pathEval[0].
    set autonavLowestCost to pathEval[1].
    set autonavBestOffset to pathEval[2].

    // 9. Point Turn if heading deviation > 22 degrees
    local hdgDev is abs(mod(desiredHDG - ship:heading + 540, 360) - 180).
    if hdgDev > 22.0 {
      executePointTurn(desiredHDG, "Autonav Point Turn").
      lock wheelsteering to desiredHDG.
      lock wheelthrottle to targetThrottle.
    }

    // 10. Straight-Line Driving Step & Gravity Speed Matching
    local surfaceG is ship:body:mu / (ship:body:radius^2).
    local gFactor is sqrt(max(0.1, surfaceG) / 9.81).
    local bodySpeedCap is min(maxSpeed, max(1.6, maxSpeed * gFactor)).

    local curSpeed is ship:groundspeed.
    local safeSpeed is bodySpeedCap.
    if tiltHazard[3] > 10 { set safeSpeed to min(safeSpeed, 1.8). } // Slope speed limit

    // Monitor lateral drift angle relative to facing heading
    local velVec is ship:velocity:surface.
    local driftAngle is 0.
    if curSpeed > 0.4 { set driftAngle to vAng(velVec, ship:facing:forevector). }

    // If over-speeding or slipping sideways on low-g regolith, tap brakes
    if curSpeed > (safeSpeed + 0.3) or (curSpeed > 0.6 and driftAngle > 14.0) {
      brakes on.
      set targetThrottle to 0.
    } else if curSpeed < safeSpeed {
      brakes off.
      set targetThrottle to min(1.0, (safeSpeed - curSpeed) * 0.3 + 0.10).
    } else {
      brakes off.
      set targetThrottle to 0.
    }

    updateRoverTelemetry(targetGeo, "Cruising step (" + round(curSpeed,1) + "/" + round(safeSpeed,1) + " m/s)").
    wait 0.05.
  }
}

// Deploy and transmit/store science experiments
global function runScienceExperiments {
  

  set lastScienceBiome to getCurrentBiome().
  print "Deploying science suite (" + lastScienceBiome + ")..." at (0, 14).

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

  local commsConnected is ship:connection:isconnected.
  
  for exp in experimentsList {
    if not exp:hasdata {
      exp:deploy().
      local startWait is time:seconds.
      wait until exp:hasdata or (time:seconds - startWait > 2).
    }
    
    if exp:hasdata and commsConnected {
      exp:transmit().
      local tStart is time:seconds.
      wait until (not exp:hasdata) or (time:seconds - tStart > 4).
    }
  }
  
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

  for exp in experimentsList {
    if exp:hasdata {
      print "Out of Comms Range: Clearing sensor for next waypoint..." at (0, 14).
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
  
  print "Science processed for: " + lastScienceBiome at (0, 14).
}
