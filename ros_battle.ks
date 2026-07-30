//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 KOS DIRECT ROVER BATTLE - MAIN EXECUTABLE
// (Victory Flex Dance, Silent Sentry & Wave Defense)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

set CONFIG:IPU to 1000.

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/ros_nav2.ks").
runOncePath("0:/lib/ros_battle_ai.ks").

clearScreen.
print "==================================================".
print "=== ROS 2 KOS GOVERNED ROVER BATTLE INITIALIZING =".
print "==================================================".

// 1. Initialize Direct Gun Part Modules & LaserDist Raytracer
initBattleWeapons().

brakes off.
sas on.

local lastHudTime is 0.
local victoryDanceStart is 0.

// Celestial Body Max Speed Limit (4.0 m/s Kerbin, 2.0 m/s Anywhere else)
local maxCombatSpeed is 2.0.
if ship:body:name = "Kerbin" {
  set maxCombatSpeed to 4.0.
}

hudText("Celestial Body: " + ship:body:name + " | Max Speed Limit: " + maxCombatSpeed + " m/s", 5, 2, 22, rgb(0.2, 1.0, 0.4), true).

// Physical Damage Reaction Tracking Variables
local lastPartCount is ship:parts:length.
local evadingUntil is 0.
local combatSideSign is 1.

until false {
  // 1. Monitor vessel health & physical part count
  local curHealth is updateVesselHealth().
  local curParts is ship:parts:length.

  // 2. Detect physical bullet hit (part destroyed/lost)
  if curParts < lastPartCount {
    hudText("BULLET HIT DETECTED (" + curParts + "/" + initialPartCount + " parts)! EVADING!", 3, 2, 22, rgb(1.0, 0.3, 0.2), true).
    set evadingUntil to time:seconds + 3.0. // Evade for 3.0s after taking physical hit
    set combatSideSign to -combatSideSign. // Switch evasion juke direction
  }
  set lastPartCount to curParts.

  local isEvading is time:seconds < evadingUntil.

  // 3. Scan for hostile target in physics bubble
  set activeTargetVessel to scanForHostileTarget().

  if activeTargetVessel = 0 {
    // VICTORY FLEX DANCE & SILENT SENTRY STANDBY MODE
    fireGunsDirect(false).

    if combatState <> "VICTORY_FLEX" and combatState <> "SENTRY_STANDBY" {
      set combatState to "VICTORY_FLEX".
      set victoryDanceStart to time:seconds.
      hudText("VICTORY! ALL ATTACKERS DEFEATED! EXECUTING VICTORY FLEX DANCE!", 5, 2, 25, rgb(0.2, 1.0, 0.4), true).
    }

    local flexTime is time:seconds - victoryDanceStart.

    if flexTime < 5.0 {
      // A. 5.0 SECONDS VICTORY FLEX DANCE (Donut Spins & Flashing Lights)
      set combatState to "VICTORY_FLEX".
      brakes off.

      if mod(flexTime, 1.2) < 0.6 {
        lock wheelsteering to mod(ship:heading + 90, 360).
        lock wheelthrottle to 0.50.
        lights on.
      } else {
        lock wheelsteering to mod(ship:heading - 90 + 360, 360).
        lock wheelthrottle to 0.50.
        lights off.
      }

    } else {
      // B. SILENT SENTRY STANDBY MODE (Silent until next attacker appears)
      set combatState to "SENTRY_STANDBY".
      brakes on.
      lights off.
      lock wheelthrottle to 0.
    }

  } else {
    // DIRECT COMBAT MODE (New Attacker Detected!)
    if combatState = "VICTORY_FLEX" or combatState = "SENTRY_STANDBY" {
      brakes off.
      set victoryDanceStart to 0.
      hudText("NEW ATTACKER DETECTED! ENGAGING TARGET!", 3, 2, 22, rgb(1.0, 0.3, 0.2), true).
    }

    local targetDist is activeTargetVessel:distance.
    local curSpeed is ship:velocity:surface:mag.

    if isEvading {
      // 1. PHYSICAL BULLET HIT EVASION MODE (3 Seconds after taking genuine part damage)
      set combatState to "EVADING_HIT".
      local targetHead is activeTargetVessel:geoposition:heading.
      local jukeHead is mod(targetHead + (combatSideSign * 45) + 360, 360).

      lock wheelsteering to jukeHead.

      // Governed speed during evasion
      if curSpeed > maxCombatSpeed {
        brakes on. lock wheelthrottle to 0.
      } else {
        brakes off. lock wheelthrottle to 0.80.
      }

    } else {
      // 2. DEFAULT MODE: 100% PURE LASER-STRAIGHT ATTACK APPROACH!
      set combatState to "ATTACK_FOCUS".

      // Point front of rover directly at enemy target with ZERO deflections
      lock wheelsteering to activeTargetVessel:geoposition.

      // Strict Ideal Range Lock (45m - 65m Window & Reverse Drive for <45m)
      if targetDist < 45.0 {
        // TOO CLOSE! Anti-Hugging Standoff: Brake and REVERSE AWAY!
        if curSpeed > 0.5 {
          brakes on.
          lock wheelthrottle to -0.40.
        } else {
          brakes off.
          lock wheelthrottle to -0.65.
        }
      } else if targetDist > 65.0 {
        // TOO FAR: Charge straight toward target (Governed Speed)
        if curSpeed > maxCombatSpeed {
          brakes on. lock wheelthrottle to 0.
        } else {
          brakes off. lock wheelthrottle to 0.80.
        }
      } else {
        // IDEAL RANGE WINDOW (45m - 65m): Perfect Standoff Firing Platform!
        if curSpeed > maxCombatSpeed {
          brakes on. lock wheelthrottle to 0.
        } else {
          brakes off. lock wheelthrottle to 0.35.
        }
      }
    }

    // 3. STRICT RAYTRACED SHOT TIMING (ONLY SHOOT WHEN DISTANCE <= 100m AND OPTICAL HIT CONFIRMED!)
    local isOpticalHit is isRaytracedTargetHit(activeTargetVessel).

    if targetDist <= 100.0 and isOpticalHit {
      fireGunsDirect(true).
    } else {
      fireGunsDirect(false).
    }
  }

  // 4. Update Telemetry HUD
  if (time:seconds - lastHudTime) > 0.2 {
    local modeTag is combatState.
    if combatState = "ATTACK_FOCUS" or combatState = "EVADING_HIT" {
      set modeTag to combatState + " (" + round(ship:velocity:surface:mag, 1) + "/" + maxCombatSpeed + "m/s)".
    }
    drawCombatHUD(activeTargetVessel, modeTag).
    set lastHudTime to time:seconds.
  }

  wait 0.05.
}
