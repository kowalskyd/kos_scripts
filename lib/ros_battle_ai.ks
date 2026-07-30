//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 KOS DIRECT ROVER BATTLE & COMBAT AI LIBRARY
// (Pure Direct Gun Module Triggering, No BDA WeaponManager Required)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/ros_nav2.ks").

// Battle Global Parameters
global combatState is "SEARCHING".
global activeTargetVessel is 0.
global initialPartCount is ship:parts:length.
global healthPercentage is 100.
global minPersonalSpace is 65.
global gunModuleList is list().
global primaryWeaponPart is 0.

//_________________________________________________
// 1. DIRECT GUN PART MODULE INTEGRATION
//_________________________________________________

global function initBattleWeapons {
  set gunModuleList to list().
  set primaryWeaponPart to 0.

  for p in ship:parts {
    for m in p:modules {
      if m = "ModuleWeapon" or m = "ModuleGatling" or m = "ModuleTurret" {
        local g is p:getmodule(m).
        gunModuleList:add(g).
        if primaryWeaponPart = 0 {
          set primaryWeaponPart to p.
        }

        // Toggle weapon ON automatically on boot so user doesn't have to manually press toggle!
        if g:hasevent("toggle") {
          g:doevent("toggle").
        } else if g:hasaction("toggle weapon") {
          g:doaction("toggle weapon", true).
        }
      }
    }
  }

  set initialPartCount to ship:parts:length.

  if gunModuleList:length > 0 {
    hudText("GUNS ARMED & READY! Evasive Combat AI Active!", 5, 2, 22, rgb(0.2, 1.0, 0.4), true).
  } else {
    hudText("WARNING: No gun modules found on ship parts.", 5, 2, 22, rgb(1.0, 0.3, 0.3), true).
  }
}

// Prints exact PartModule action, event, and field names on kOS terminal
global function printWeaponDiagnostics {
  print "=== WEAPON PART DIAGNOSTICS ===".
  for g in gunModuleList {
    print "ACTIONS: " + g:allactions.
    print "EVENTS:  " + g:allevents.
  }
  print "===============================".
}

// Directly fires gun part modules on interval bursts
global function fireGunsDirect {
  parameter fireState. // boolean true/false

  // 1. Native Action Group 1 Trigger (bypasses mod quirks if AG1 assigned in KSP)
  if fireState {
    AG1 ON.
  } else {
    AG1 OFF.
  }

  // 2. Direct PartModule Action triggers using exact BDArmory action names
  for g in gunModuleList {
    if fireState {
      // Ensure gun is toggled ON
      if g:hasevent("toggle") { g:doevent("toggle"). }
      if g:hasaction("fire (hold)") { g:doaction("fire (hold)", true). }
      if g:hasaction("fire (toggle)") { g:doaction("fire (toggle)", true). }
      if g:hasaction("fire") { g:doaction("fire", true). }
      if g:hasaction("fire guns") { g:doaction("fire guns", true). }
    } else {
      if g:hasaction("fire (hold)") { g:doaction("fire (hold)", false). }
      if g:hasaction("fire (toggle)") { g:doaction("fire (toggle)", false). }
      if g:hasaction("fire") { g:doaction("fire", false). }
      if g:hasaction("fire guns") { g:doaction("fire guns", false). }
    }
  }
}

// Raytracing Fire Control using LaserDist addon or geometric raycone math
global function isRaytracedTargetHit {
  parameter enemyVessel.
  if enemyVessel = 0 { return false. }

  // 1. Check LaserDist Addon API if available
  if addons:hasaddon("LaserDist") {
    local laserList is addons:laserdist:alllasers.
    if laserList:length > 0 {
      for l in laserList {
        if l:hit {
          if abs(l:distance - enemyVessel:distance) < 20.0 or l:distance < (enemyVessel:distance + 5.0) {
            return true.
          }
        }
      }
    }
  }

  // 2. Geometric Ray-Cone Mesh Intersection Fallback
  local enemyDir is (enemyVessel:position - ship:position):normalized.
  local gunFacing is ship:facing:forevector.
  local rayAngle is vAng(gunFacing, enemyDir).

  // Dynamic angular target size threshold: arctan2(rover_radius, distance)
  local maxAngleThreshold is min(7.5, max(1.2, arctan2(3.0, max(1.0, enemyVessel:distance)))).
  return rayAngle < maxAngleThreshold.
}

// Determines if target vessel is operational (loaded, not debris, has control core, part count >= 3)
global function isVesselOperational {
  parameter targetVessel.

  if targetVessel = 0 { return false. }
  if targetVessel:typename <> "Vessel" { return false. }

  // 1. Must be loaded in physics bubble before accessing parts!
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

  return hasControlCore.
}

// Checks if a vessel is a valid hostile enemy target (filters out Master/Commanders and Friendly Teams)
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
// 2. TARGET SCANNING & HEALTH METRICS
//_________________________________________________

global function scanForHostileTarget {
  local closestVessel is 0.
  local minDist is 999999.

  // If current locked target is no longer hostile/operational, drop it!
  if hasTarget {
    if isHostileTarget(target) {
      return target.
    } else {
      unsetTarget().
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

//_________________________________________________
// 3. PERSONAL SPACE & AMMO METRICS
//_________________________________________________

global function applyPersonalSpaceRepulsion {
  parameter rawTargetGeo.

  local totalRepelVec is V(0,0,0).
  local nearbyCount is 0.

  local targetList is list().
  list targets in targetList.

  for v in targetList {
    if v:typename = "Vessel" and v <> ship {
      local d is v:distance.
      if d < minPersonalSpace and d > 0.5 {
        local awayVec is (ship:position - v:position):normalized.
        local repulsionStrength is (minPersonalSpace - d) / minPersonalSpace.
        set totalRepelVec to totalRepelVec + (awayVec * repulsionStrength * 40.0).
        set nearbyCount to nearbyCount + 1.
      }
    }
  }

  if nearbyCount > 0 {
    return ship:body:geopositionof(rawTargetGeo:position + totalRepelVec).
  }

  return rawTargetGeo.
}

global function getAmmoInfo {
  local ammoCount is 0.
  local ammoName is "NONE".

  for r in ship:resources {
    if r:name:contains("Ammo") or r:name:contains("Bullet") or r:name:contains("Shell") or r:name:contains("20x102") or r:name:contains("50Cal") or r:name:contains("30mm") {
      set ammoCount to ammoCount + r:amount.
      set ammoName to r:name.
    }
  }

  return list(ammoCount, ammoName).
}

global function getGunMountOffsetAngle {
  if primaryWeaponPart = 0 { return 0. }
  return vAng(ship:facing:forevector, primaryWeaponPart:facing:forevector).
}

global function getGunAimError {
  parameter enemyVessel.
  if enemyVessel = 0 { return 180. }
  local enemyDir is enemyVessel:position - ship:position.
  return vAng(ship:facing:forevector, enemyDir).
}

//_________________________________________________
// 4. COMBAT TELEMETRY HUD
//_________________________________________________

global function drawCombatHUD {
  parameter enemyVessel.
  parameter currentSubstate.

  clearScreen.

  local targetName is "NONE".
  local targetDistStr is "--- m".
  local aimErrorStr is "--- deg".

  if enemyVessel <> 0 {
    set targetName to enemyVessel:name.
    set targetDistStr to round(enemyVessel:distance, 1) + " m".
    local errAngle is getGunAimError(enemyVessel).
    set aimErrorStr to round(errAngle, 1) + " deg".
  }

  local ammoData is getAmmoInfo().
  local ammoStr is round(ammoData[0]) + " (" + ammoData[1] + ")".

  local statusLine is "STATE: [" + combatState + "] | HEALTH: " + healthPercentage + "%".
  local targetLine is "TARGET: " + padRight(targetName, 20) + " | DIST: " + targetDistStr.
  local aimLine is "AIM ERR: " + aimErrorStr.
  local ammoLine is "AMMO RESERVES: " + ammoStr.

  print "==================================================" at (0, 0).
  print "=== ROS 2 KOS DIRECT ROVER BATTLE HUD ===" at (0, 1).
  print "==================================================" at (0, 2).
  print padRight(statusLine, 50) at (0, 3).
  print padRight(targetLine, 50) at (0, 4).
  print padRight(aimLine, 50) at (0, 5).
  print padRight(ammoLine, 50) at (0, 6).
  print "--------------------------------------------------" at (0, 7).
}
