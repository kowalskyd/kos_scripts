//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 KOS TACTICAL ROBOT WARS COMBAT MAIN EXECUTABLE
// (50m Tactical Standoff Reset Engine & Kinetic Charge)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

set CONFIG:IPU to 1000.

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/ros_nav2.ks").
runOncePath("0:/lib/ros_battle_ai.ks").

set terminal:width to 50.
set terminal:height to 11.
core:doaction("Open Terminal", true).

clearScreen.
print "==================================================".
print "=== ROS 2 TACTICAL ROBOT WARS COMBAT INITIALIZING =".
print "==================================================".

brakes off.
sas on.
initVesselArchetype().

local lastHudTime is 0.
local victoryDanceStart is 0.
local impactCount is 0.
local lastImpactCooldown is 0.
local disengageUntil is 0.
local postVictoryBackoffUntil is 0.
local escapeCooldown is 0.
local escapeMode is "NONE".
local isChargingRunway is false.
local combatSideSign is 1.

// 50m Standoff Reset Engine Variables (Active at match start!)
local isStandoffResetActive is true.
local closeRangeTimer is 0.

local lastMovedTime is time:seconds.
local lastGeoPos is 0.
local flippedTimer is 0.
local isSelfDefeated is false.

local progressCheckTimer is 0.
local lastCheckDist is 0.
local isBaitStopping is false.
local baitStopUntil is 0.

// Max Speed Limit for Arena Precision Combat (5.5 m/s)
local maxCombatSpeed is 5.5.

// Unique per-vessel random seed offset so rovers make completely different stochastic choices!
local vSeed is mod(ship:name:length * 47 + ship:parts:length * 19, 100) / 100.0.

// Physical damage tracking & state machine variables
local lastPartCount is ship:parts:length.
local currentManeuver is "TACTICAL_DIRECT_ALIGN".
local maneuverTimer is 0.
local maneuverDuration is 3.0.

// Thread-safe steering lock
local autoSteer is ship:heading.
lock wheelsteering to autoSteer.

until false {
  // 1. Immobility & Flipped Self-Defeat Check
  // A. Check if flipped upside down or non-operational for > 3.0 seconds
  if not isVesselOperational(ship) {
    if flippedTimer = 0 { set flippedTimer to time:seconds. }
    if (time:seconds - flippedTimer) > 3.0 {
      set isSelfDefeated to true.
    }
  } else {
    set flippedTimer to 0.
  }

  // B. Track ground displacement (must move > 0.8m in 3.0 seconds during combat)
  local curGeo is ship:geoposition.
  if lastGeoPos = 0 {
    set lastGeoPos to curGeo.
    set lastMovedTime to time:seconds.
  } else if lastGeoPos:position:mag > 0.8 {
    set lastGeoPos to curGeo.
    set lastMovedTime to time:seconds.
  }

  local immobileDuration is time:seconds - lastMovedTime.

  if immobileDuration > 3.0 and combatState <> "VICTORY_FLEX" and combatState <> "SENTRY_STANDBY" and combatState <> "POST_VICTORY_DISENGAGE" {
    set isSelfDefeated to true.
  }

  if isSelfDefeated {
    set combatState to "DEFEATED_IMMOBILE".
    hudText("ROVER DEFEATED! FLIPPED / IMMOBILE! SHUTTING DOWN!", 2, 2, 25, rgb(1.0, 0.2, 0.2), true).
    brakes on.
    lights off.
    lock wheelthrottle to 0.
    lock wheelsteering to ship:heading.

  } else {
    // 2. Monitor vessel health & physical part count
    local curHealth is updateVesselHealth().
    local curParts is ship:parts:length.

    // 3. Detect physical collision / part impact
    if curParts < lastPartCount {
      set impactCount to impactCount + 1.
      set disengageUntil to time:seconds + 2.0. // 2.0s burst escape
      set escapeCooldown to time:seconds + 4.0.
      set isChargingRunway to false.
      set combatSideSign to -combatSideSign.

      local escVal is floor(mod(random() + vSeed, 1.0) * 3).
      if escVal = 0 { set escapeMode to "FORWARD_FLANK_BREAK". }
      else if escVal = 1 { set escapeMode to "REVERSE_ARC_SPIN". }
      else { set escapeMode to "S_CURVE_JUT". }
    }
    set lastPartCount to curParts.

    // 4. Scan for closest operational & mobile opponent vessel
    set activeTargetVessel to scanForHostileTarget().

    // 5. Mid-Battle 50m Standoff Reset Triggers (Close range > 3s or stagnant range)
    if activeTargetVessel <> 0 {
      local targetDist is activeTargetVessel:distance.

      // OFFENSIVE RAM STRIKE DETECTION:
      // Valid strike requires bumper proximity (< 3.2m), higher speed than target, and frontal aim (< 45 deg)
      if targetDist < 3.2 and time:seconds > lastImpactCooldown {
        local mySpeed is ship:velocity:surface:mag.
        local enemySpeed is activeTargetVessel:velocity:surface:mag.
        local aimErr is getAimErrorAngle(activeTargetVessel).

        if mySpeed > enemySpeed and aimErr < 45.0 {
          set impactCount to impactCount + 1.
          set lastImpactCooldown to time:seconds + 1.5.
        }
      }

      // Trigger A: Too close for too long (> 3.0s under 6.0m)
      if targetDist < 6.0 {
        if closeRangeTimer = 0 { set closeRangeTimer to time:seconds. }
        if (time:seconds - closeRangeTimer) > 3.0 {
          set isStandoffResetActive to true. // Trigger 50m Tactical Reset!
        }
      } else {
        set closeRangeTimer to 0.
      }

      // Trigger B: Progress Monitoring (Stagnant range over 1.5s window)
      if time:seconds > progressCheckTimer {
        local deltaDist is abs(targetDist - lastCheckDist).
        if deltaDist < 1.0 and targetDist < 45.0 {
          set isStandoffResetActive to true. // Trigger 50m Standoff Reset on range failure!
        }
        set lastCheckDist to targetDist.
        set progressCheckTimer to time:seconds + 1.5.
      }
    }

    // 6. Detect Close Contact / Push-Lock (< 3.5m distance: trigger asymmetric erratic escape!)
    if activeTargetVessel <> 0 and time:seconds > disengageUntil and time:seconds > escapeCooldown {
      if activeTargetVessel:distance < 3.5 {
        set disengageUntil to time:seconds + 2.0.
        set escapeCooldown to time:seconds + 4.0.
        set isChargingRunway to false.
        set combatSideSign to -combatSideSign.

        local escVal is floor(mod(random() + vSeed, 1.0) * 3).
        if escVal = 0 { set escapeMode to "FORWARD_FLANK_BREAK". }
        else if escVal = 1 { set escapeMode to "REVERSE_ARC_SPIN". }
        else { set escapeMode to "S_CURVE_JUT". }
      }
    }

    if activeTargetVessel = 0 {
      // VICTORY / POST-STRIKE DISENGAGE MODE
      if postVictoryBackoffUntil = 0 {
        set postVictoryBackoffUntil to time:seconds + 3.0. // Mandatory 3.0s reverse to un-wedge from wreck
      }

      if time:seconds < postVictoryBackoffUntil {
        // MANDATORY POST-VICTORY UN-WEDGE DISENGAGE
        set combatState to "POST_VICTORY_DISENGAGE".
        hudText("TARGET DEFEATED! UN-WEDGING & BACKING AWAY!", 2, 2, 22, rgb(0.2, 1.0, 0.4), true).

        brakes off.
        lock wheelthrottle to -0.85. // Full power reverse drive to clear wreck
        set autoSteer to mod(ship:heading + 180, 360).

      } else {
        // ARENA VICTORY FLEX & STANDBY
        if combatState <> "VICTORY_FLEX" and combatState <> "SENTRY_STANDBY" {
          set combatState to "VICTORY_FLEX".
          set victoryDanceStart to time:seconds.
          hudText("VICTORY! ALL OPPONENT ROVERS DEFEATED!", 5, 2, 25, rgb(0.2, 1.0, 0.4), true).
        }

        local flexTime is time:seconds - victoryDanceStart.

        if flexTime < 6.0 {
          set combatState to "VICTORY_FLEX".
          brakes off.
          if mod(flexTime, 1.0) < 0.5 {
            set autoSteer to mod(ship:heading + 120, 360).
            lock wheelthrottle to 0.45.
            lights on.
          } else {
            set autoSteer to mod(ship:heading - 120 + 360, 360).
            lock wheelthrottle to 0.45.
            lights off.
          }
        } else {
          set combatState to "SENTRY_STANDBY".
          brakes on.
          lights off.
          set autoSteer to ship:heading.
          lock wheelthrottle to 0.
        }
      }

    } else {
      set postVictoryBackoffUntil to 0.
      // TACTICAL MELEE COMBAT ACTIVE
      local targetDist is activeTargetVessel:distance.
      local curSpeed is ship:velocity:surface:mag.
      local aimErr is getAimErrorAngle(activeTargetVessel).

      if time:seconds < disengageUntil {
        // ERRATIC STOCHASTIC ESCAPE ENGINE
        set combatState to "ESCAPE_" + escapeMode.

        if escapeMode = "FORWARD_FLANK_BREAK" {
          local targetHead is activeTargetVessel:geoposition:heading.
          local escHead is mod(targetHead + (combatSideSign * 100) + 360, 360).
          set autoSteer to escHead.

          brakes off.
          if curSpeed > maxCombatSpeed { brakes on. lock wheelthrottle to 0. }
          else { lock wheelthrottle to 0.70. }

        } else if escapeMode = "REVERSE_ARC_SPIN" {
          local targetHead is activeTargetVessel:geoposition:heading.
          local escHead is mod(targetHead + 180 + (combatSideSign * 45), 360).
          set autoSteer to escHead.

          brakes off.
          if curSpeed > maxCombatSpeed { brakes on. lock wheelthrottle to 0. }
          else { lock wheelthrottle to -0.75. }

        } else {
          local targetHead is activeTargetVessel:geoposition:heading.
          if (disengageUntil - time:seconds) > 1.2 {
            set autoSteer to mod(targetHead + (combatSideSign * 90) + 360, 360).
            brakes off.
            lock wheelthrottle to 0.65.
          } else {
            set autoSteer to mod(targetHead + 180 - (combatSideSign * 45), 360).
            brakes off.
            lock wheelthrottle to -0.75.
          }
        }

      } else if isStandoffResetActive {
        // 50M TACTICAL STANDOFF RESET MANEUVER (Match start or mid-battle reset to gain 50m space)
        if targetDist < 20.0 {
          set combatState to "RESET_TACTICAL_STANDOFF_50M".
          local targetHead is activeTargetVessel:geoposition:heading.
          local escHead is mod(targetHead + 180 + (combatSideSign * 20), 360).
          set autoSteer to escHead.

          brakes off.
          if curSpeed > maxCombatSpeed { brakes on. lock wheelthrottle to 0. }
          else { lock wheelthrottle to -1.0. } // Full power reverse drive to open 50m distance

        } else {
          // 50m Standoff space established!
          set isStandoffResetActive to false.
          set isChargingRunway to true.
        }

      } else if isBaitStopping and time:seconds < baitStopUntil {
        // ANTI-CIRCLING BAIT STOP (Slam on full brakes for 0.8s to force opponent overshoot!)
        set combatState to "BAIT_BRAKE_STOP".
        brakes on.
        lock wheelthrottle to 0.
        set autoSteer to activeTargetVessel:geoposition.

      } else if targetDist <= 6.0 and aimErr <= 45.0 and curSpeed >= 1.2 {
        // TERMINAL IMPACT LOCK: Close range (<= 6m), aligned (<= 45 deg), and carrying speed.
        // 100% Full Throttle Commitment — DO NOT CANCEL OR SWAP MANEUVERS IN TERMINAL APPROACH!
        set combatState to "TERMINAL_RAM_CHARGE".
        brakes off.
        lock wheelthrottle to 1.0. // 100% Full Power Kinetic Surge!

        if targetDist < 2.2 {
          // Pre-Impact Juke Steering (Snap 15-30 deg to clip opponent corner/wheels & flip them!)
          local jukeAngle is combatSideSign * (15.0 + floor(mod(vSeed * 100, 1.0) * 15.0)).
          local terminalHead is mod(activeTargetVessel:geoposition:heading + jukeAngle + 360, 360).
          set autoSteer to terminalHead.
        } else {
          // Drive directly along predictive lead intercept point
          local interceptPoint is getTargetInterceptVector(activeTargetVessel).
          set autoSteer to body:geopositionof(interceptPoint).
        }

      } else {
          // STOCHASTIC MANEUVER SELECTION & CHARGE DOWN OPEN RUNWAY
          if time:seconds > maneuverTimer {
            local rVal is floor(mod(random() + vSeed, 1.0) * 3). // Unique per-vessel random choice

            if targetDist < 6.0 {
              if rVal = 0 { set currentManeuver to "STRIKE_DIRECT_RAM". }
              else if rVal = 1 { set currentManeuver to "STRIKE_HOOK_TURN". }
              else { set currentManeuver to "STRIKE_JAB_AND_BACK". }
              set maneuverDuration to 2.0 + (random() * 1.5).

            } else if targetDist <= 20.0 {
              if rVal = 0 { set currentManeuver to "TACTICAL_CIRCLE_FLANK". }
              else if rVal = 1 { set currentManeuver to "CUT_INSIDE_RAM". }
              else { set currentManeuver to "TACTICAL_DIRECT_ALIGN". }
              set maneuverDuration to 2.5 + (random() * 1.5).

            } else {
              if rVal = 0 { set currentManeuver to "APPROACH_CAUTIOUS". }
              else { set currentManeuver to "APPROACH_ZIGZAG". }
              set maneuverDuration to 3.0 + (random() * 1.5).
            }

            set maneuverTimer to time:seconds + maneuverDuration.
            set combatSideSign to -combatSideSign.
          }

          set combatState to currentManeuver.
          local timeRemaining is maneuverTimer - time:seconds.

          // EXECUTE MANEUVER
          if currentManeuver = "STRIKE_DIRECT_RAM" or currentManeuver = "CUT_INSIDE_RAM" {
            local cutHead is mod(activeTargetVessel:geoposition:heading + (combatSideSign * 15) + 360, 360).
            set autoSteer to cutHead.
            brakes off.
            lock wheelthrottle to 1.0.

          } else if currentManeuver = "STRIKE_HOOK_TURN" {
            local hookHead is mod(activeTargetVessel:geoposition:heading + (combatSideSign * 45) + 360, 360).
            set autoSteer to hookHead.
            brakes off.
            lock wheelthrottle to 1.0.

          } else if currentManeuver = "STRIKE_JAB_AND_BACK" {
            set autoSteer to activeTargetVessel:geoposition.
            if timeRemaining > (maneuverDuration - 0.8) {
              brakes off.
              lock wheelthrottle to 1.0.
            } else {
              brakes off.
              lock wheelthrottle to -0.50.
            }

          } else if currentManeuver = "TACTICAL_CIRCLE_FLANK" {
            local flankHead is mod(activeTargetVessel:geoposition:heading + (combatSideSign * 60) + 360, 360).
            set autoSteer to flankHead.
            brakes off.
            lock wheelthrottle to 0.80.

          } else if currentManeuver = "TACTICAL_DIRECT_ALIGN" {
            set autoSteer to activeTargetVessel:geoposition.
            brakes off.
            lock wheelthrottle to 1.0.

          } else if currentManeuver = "APPROACH_CAUTIOUS" {
            set autoSteer to activeTargetVessel:geoposition.
            brakes off.
            lock wheelthrottle to 0.70.

          } else if currentManeuver = "APPROACH_ZIGZAG" {
            local zigHead is mod(activeTargetVessel:geoposition:heading + (combatSideSign * 30) + 360, 360).
            set autoSteer to zigHead.
            brakes off.
            lock wheelthrottle to 0.80.

          } else {
            set autoSteer to activeTargetVessel:geoposition.
            brakes off.
            lock wheelthrottle to 1.0.
          }
        }
      }
    }

  // 7. Update Robot Wars Telemetry HUD
  if (time:seconds - lastHudTime) > 0.2 {
    local modeTag is combatState.
    if activeTargetVessel <> 0 {
      set modeTag to combatState + " (" + round(ship:velocity:surface:mag, 1) + "m/s)".
    }
    drawRobotWarsHUD(activeTargetVessel, modeTag, impactCount).
    set lastHudTime to time:seconds.
  }

  wait 0.05.
}
