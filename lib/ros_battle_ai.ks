//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 KOS ROBOT WARS PHYSICAL COMBAT AI LIBRARY V2
// (Utility Decision Engine, Kinematic Intercept & Archetype Engine)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/ros_nav2.ks").

// Robot Wars Global Parameters
global combatState is "SEARCHING".
global activeTargetVessel is 0.
global initialPartCount is ship:parts:length.
global healthPercentage is 100.

// Persistent Combat Archetype Profiling Variables
global vesselPersonality is "BALANCED".
global weightRam is 1.0.
global weightFlank is 1.0.
global weightBait is 1.0.
global driverReactionLatency is 0.10.

// Helper function for conditional numbers (kOS equivalent of ternary)
local function selectNum {
  parameter cond, valTrue, valFalse.
  if cond { return valTrue. } else { return valFalse. }
}

//_________________________________________________
// 1. COMBAT ARCHETYPE & PERSONALITY ENGINE
//_________________________________________________

// Initializes Combat Archetype based on unique ship parameters (seed includes geo position & root ID for twin craft separation)
global function initVesselArchetype {
  local rootHash is ship:rootpart:uid:length.
  local uidNum is ship:rootpart:uid:tonumber(0).
  if uidNum <> 0 { set rootHash to uidNum. }
  
  // Geo position + root UID ensures identical craft placed in arena get different seeds!
  local pSeed is mod(abs(ship:geoposition:lng * 1370 + ship:geoposition:lat * 930 + ship:parts:length * 29 + rootHash), 100) / 100.0.
  
  if pSeed < 0.35 {
    set vesselPersonality to "BRAWLER".
    set weightRam to 1.6.
    set weightFlank to 0.7.
    set weightBait to 0.5.
    set driverReactionLatency to 0.05.
  } else if pSeed < 0.70 {
    set vesselPersonality to "FLANKER".
    set weightRam to 0.8.
    set weightFlank to 1.7.
    set weightBait to 0.8.
    set driverReactionLatency to 0.12.
  } else {
    set vesselPersonality to "COUNTER_BAITER".
    set weightRam to 0.9.
    set weightFlank to 0.9.
    set weightBait to 1.8.
    set driverReactionLatency to 0.20.
  }
}

//_________________________________________________
// 2. KINEMATIC LEAD INTERCEPT & ANGULAR VELOCITY
//_________________________________________________

// Computes predictive lead intercept position vector (aims where enemy WILL be)
global function getTargetInterceptVector {
  parameter enemyVessel.
  
  if enemyVessel = 0 { return ship:position. }
  
  local relPos is enemyVessel:position. // In kOS relative frame, ship:position is V(0,0,0)
  local relVel is enemyVessel:velocity:surface - ship:velocity:surface.
  
  // Closing speed along line of sight
  local closingSpeed is -vDot(relVel, relPos:normalized).
  if closingSpeed < 0.5 { set closingSpeed to 0.5. }
  
  // Time-to-impact calculation (clamped to 3.0s max lead)
  local tImpact is min(3.0, relPos:mag / closingSpeed).
  
  // Lead vector prediction
  local predictedPos is enemyVessel:position + (enemyVessel:velocity:surface * tImpact).
  return predictedPos.
}

// Angular Velocity Calculation (detects mutual circling/orbiting rate)
global function getTargetAngularVelocity {
  parameter enemyVessel.
  if enemyVessel = 0 { return 0. }
  
  local relPos is enemyVessel:position.
  local relVel is enemyVessel:velocity:surface - ship:velocity:surface.
  
  // Vector cross product yields rotation rate around rover
  local crossVec is vcrs(relPos:normalized, relVel).
  return crossVec:mag.
}

//_________________________________________________
// 3. UTILITY EVALUATION ENGINE (Continuous Scoring)
//_________________________________________________

global function evaluateCombatUtility {
  parameter enemyVessel.
  parameter currentAction. // Passed for hysteresis stickiness
  
  if enemyVessel = 0 { return lex("action", "SEARCH", "score", 100). }
  
  local targetDist is enemyVessel:distance.
  local aimErr is getAimErrorAngle(enemyVessel).
  local angVel is getTargetAngularVelocity(enemyVessel).
  local mySpeed is ship:velocity:surface:mag.
  
  // Normalized variables in range [0, 1]
  local normDist is max(0, 1.0 - (targetDist / 50.0)).
  local normSpeed is min(1.0, mySpeed / 6.0).
  local normCosAim is (cos(aimErr) + 1.0) / 2.0. // 0..1 scale
  local normSinAim is abs(sin(aimErr)).
  
  // Utility Scores Calculation
  local ramScore is (normCosAim * 40) + (normSpeed * 30) + (normDist * 30).
  set ramScore to ramScore * weightRam.
  
  local flankBonus is selectNum(targetDist < 15, 30, 0).
  local flankScore is (normSinAim * 30) + (min(1.0, angVel) * 35) + flankBonus.
  set flankScore to flankScore * weightFlank.
  
  local baitAngBonus is selectNum(angVel > 0.8, 50, 0).
  local baitAimBonus is selectNum(aimErr > 60, 30, 0).
  local baitDistBonus is selectNum(targetDist < 8, 20, 0).
  local baitScore is baitAngBonus + baitAimBonus + baitDistBonus.
  set baitScore to baitScore * weightBait.
  
  // Apply Utility Hysteresis (+8 score stickiness bonus to currently active state to prevent high-frequency jitter)
  if currentAction = "EXECUTE_RAM" { set ramScore to ramScore + 8. }
  else if currentAction = "EXECUTE_FLANK" { set flankScore to flankScore + 8. }
  else if currentAction = "EXECUTE_BAIT" { set baitScore to baitScore + 8. }
  
  // Select Action with Highest Utility
  if ramScore >= flankScore and ramScore >= baitScore {
    return lex("action", "EXECUTE_RAM", "score", ramScore).
  } else if flankScore >= baitScore {
    return lex("action", "EXECUTE_FLANK", "score", flankScore).
  } else {
    return lex("action", "EXECUTE_BAIT", "score", baitScore).
  }
}

//_________________________________________________
// 4. MOBILITY & VESSEL OPERATIONAL METRICS
//_________________________________________________

// Determines if target vessel is operational and mobile (not flipped, has wheels & control core)
global function isVesselOperational {
  parameter targetVessel.

  if targetVessel = 0 { return false. }
  if targetVessel:typename <> "Vessel" { return false. }

  // 1. Must be loaded in active physics bubble before accessing parts!
  if not targetVessel:loaded {
    return false.
  }

  // 2. Filter out debris, flags, EVA suits
  if targetVessel:type = "Debris" or targetVessel:type = "Flag" or targetVessel:type = "EVA" {
    return false.
  }

  // 3. Filter out broken carcasses (< 3 parts)
  if targetVessel:parts:length < 3 {
    return false.
  }

  // 4. Must have an operational control core (CommandPod or kOSProcessor)
  local hasControlCore is false.
  for p in targetVessel:parts {
    if p:hasmodule("ModuleCommand") or p:hasmodule("kOSProcessor") {
      set hasControlCore to true.
    }
  }
  if not hasControlCore { return false. }

  // 5. FLIPPED CHECK: If rover is flipped over (> 70 deg off vertical), it lacks mobility / is defeated!
  local roverUp is targetVessel:facing:upvector.
  local bodyUp is targetVessel:up:vector.
  local tiltAngle is vAng(roverUp, bodyUp).
  if tiltAngle > 70.0 {
    return false. // Rover flipped onto its back/side! Unable to move!
  }

  // 6. WHEEL MOBILITY CHECK: Must have at least 2 functional wheel parts remaining
  local wheelCount is 0.
  for p in targetVessel:parts {
    for m in p:modules {
      if m:contains("Wheel") or m:contains("Steering") {
        set wheelCount to wheelCount + 1.
      }
    }
  }
  if wheelCount < 2 {
    return false. // Lacks mobility / wheels destroyed!
  }

  // 7. STRANDED IMMOBILITY CHECK: If propped up (> 40 deg tilt) and stationary (< 0.1 m/s), it is immobile/defeated!
  if tiltAngle > 40.0 and targetVessel:velocity:surface:mag < 0.1 {
    return false.
  }

  return true.
}

// Checks if a vessel is a valid hostile enemy target
global function isHostileTarget {
  parameter targetVessel.

  if not isVesselOperational(targetVessel) { return false. }

  local vName is targetVessel:name.

  // 1. Ignore Master / Commander / Carrier / Base vehicles
  if vName:contains("Master") or vName:contains("master") or vName:contains("Command") or vName:contains("command") or vName:contains("Carrier") or vName:contains("carrier") or vName:contains("Console") or vName:contains("console") or vName:contains("Mothership") or vName:contains("mothership") {
    return false.
  }

  // 2. Team Filtering (if vessel names contain Team A/B or Red/Blue)
  local myName is ship:name.

  if myName:contains("Team A") or myName:contains("team a") or myName:contains("Alpha") or myName:contains("alpha") or myName:contains("Red") or myName:contains("red") {
    if vName:contains("Team A") or vName:contains("team a") or vName:contains("Alpha") or vName:contains("alpha") or vName:contains("Red") or vName:contains("red") {
      return false. // Friendly team member!
    }
  } else if myName:contains("Team B") or myName:contains("team b") or myName:contains("Bravo") or myName:contains("bravo") or myName:contains("Blue") or myName:contains("blue") {
    if vName:contains("Team B") or vName:contains("team b") or vName:contains("Bravo") or vName:contains("bravo") or vName:contains("Blue") or vName:contains("blue") {
      return false. // Friendly team member!
    }
  }

  return true.
}

//_________________________________________________
// 5. TARGET SCANNING & HEALTH METRICS
//_________________________________________________

global function scanForHostileTarget {
  local closestVessel is 0.
  local minDist is 999999.

  // If current locked target is still operational and hostile, maintain target lock
  if activeTargetVessel <> 0 {
    if isHostileTarget(activeTargetVessel) {
      return activeTargetVessel.
    } else {
      set activeTargetVessel to 0.
    }
  }

  local targetList is list().
  list targets in targetList.

  for v in targetList {
    if v:typename = "Vessel" and v <> ship {
      if isHostileTarget(v) {
        local d is v:distance.
        if d < minDist and d < 3500 {
          set minDist to d.
          set closestVessel to v.
        }
      }
    }
  }

  return closestVessel.
}

global function updateVesselHealth {
  local curParts is ship:parts:length.
  local partRatio is curParts / max(1, initialPartCount).
  set healthPercentage to round(partRatio * 100).
  return healthPercentage.
}

global function getAimErrorAngle {
  parameter enemyVessel.
  if enemyVessel = 0 { return 180. }
  local enemyDir is enemyVessel:position - ship:position.
  return vAng(ship:facing:forevector, enemyDir).
}

global function isFlankThreat {
  parameter enemyVessel.
  if enemyVessel = 0 { return false. }
  if enemyVessel:typename <> "Vessel" { return false. }

  local enemyVec is enemyVessel:position - ship:position.
  local d is enemyVessel:distance.

  // Only consider flank threat within 10 meters
  if d > 10.0 { return false. }

  // Measure angle relative to side vectors (starboard/port)
  local starAngle is vAng(ship:facing:starvector, enemyVec).
  local portAngle is vAng(-ship:facing:starvector, enemyVec).

  // If enemy is approaching within 50 degrees of side vector, flank is threatened!
  return (starAngle < 50.0 or portAngle < 50.0).
}

//_________________________________________________
// 6. ROBOT WARS TELEMETRY HUD
//_________________________________________________

global function drawRobotWarsHUD {
  parameter enemyVessel.
  parameter currentSubstate.
  parameter impactCount.

  clearScreen.

  local targetName is "NONE".
  local targetDistStr is "--- m".
  local relSpeedStr is "--- m/s".
  local enemyPartsStr is "---".

  if enemyVessel <> 0 {
    set targetName to enemyVessel:name.
    set targetDistStr to round(enemyVessel:distance, 1) + " m".
    local relVel is (ship:velocity:surface - enemyVessel:velocity:surface):mag.
    set relSpeedStr to round(relVel, 1) + " m/s".
    if enemyVessel:loaded {
      set enemyPartsStr to "" + enemyVessel:parts:length.
    }
  }

  local profileLine is "PROFILE: " + padRight(vesselPersonality, 15) + " | HEALTH: " + healthPercentage + "%".
  local modeLine    is "MODE:    [" + currentSubstate + "]".
  local targetLine  is "TARGET:  " + padRight(targetName, 18) + " | DIST: " + targetDistStr.
  local strikeLine  is "CLOSING: " + padRight(relSpeedStr, 15) + " | STRIKES: " + impactCount.
  local partsLine   is "ENEMY PARTS: " + padRight(enemyPartsStr, 8) + " | MY PARTS: " + ship:parts:length.

  print "==================================================" at (0, 0).
  print "=== ROS 2 ROBOT WARS PHYSICAL MELEE COMBAT ===" at (0, 1).
  print "==================================================" at (0, 2).
  print padRight(profileLine, 50) at (0, 3).
  print padRight(modeLine, 50) at (0, 4).
  print padRight(targetLine, 50) at (0, 5).
  print padRight(strikeLine, 50) at (0, 6).
  print padRight(partsLine, 50) at (0, 7).
  print "--------------------------------------------------" at (0, 8).
}
