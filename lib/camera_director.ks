// =============================================
//      CINEMATIC CAMERA DIRECTOR LIBRARY
// =============================================
// Uses kOS-StockCamera addon to automate multi-cut camera sequences.
// Safe to run even if the addon is not installed (falls back silently).

global hasCameraAddon is addons:available("camera").
global activeCameraCuts is list().
global activeCutIndex is 0.
global activeCutStartTime is 0.
global cameraDirectorActive is true.
global currentStageNum is stage:number.
global stagingCutsEnabled is true.

// Helper to get the Sun's heading relative to the ship's current local frame
global function getSunHeading {
  local localSun is BODY("Sun"):position - ship:position.
  local northVec is heading(0, 0):vector.
  local eastVec is heading(90, 0):vector.
  local sunH is arctan2(vdot(eastVec, localSun), vdot(northVec, localSun)).
  if sunH < 0 { set sunH to sunH + 360. }
  return sunH.
}

// Helper to get the ship's compass heading relative to local horizon
global function getShipHeading {
  local shipFwd is ship:facing:vector.
  local northVec is heading(0, 0):vector.
  local eastVec is heading(90, 0):vector.
  local horizFwd is shipFwd - vdot(shipFwd, up:vector) * up:vector.
  if horizFwd:mag < 0.001 { set horizFwd to shipFwd. }
  local shipH is arctan2(vdot(eastVec, horizFwd), vdot(northVec, horizFwd)).
  if shipH < 0 { set shipH to shipH + 360. }
  return shipH.
}

if hasCameraAddon {
  // 1. Auto-Staging Detection Trigger
  when stage:number < currentStageNum then {
    if cameraDirectorActive and stagingCutsEnabled {
      playStagingScene(8).
    }
    set currentStageNum to stage:number.
    preserve.
  }

  // 2. Background camera update loop
  when cameraDirectorActive then {
    if activeCameraCuts:length > 0 and activeCutIndex < activeCameraCuts:length {
      // --- TIMEWARP SAFETY ---
      // During active ON-RAILS timewarp (>1x), hold a smooth, steady wide pan at real-time rates
      // and reset cut timer so camera cuts don't finish instantly or spin violently.
      // Physics warp (during launch/ascent) is excluded so ground cameras work unimpeded.
      if kuniverse:timewarp:mode = "RAILS" and kuniverse:timewarp:rate > 1 {
        if not MAPVIEW {
          set addons:camera:flightcamera:heading to addons:camera:flightcamera:heading + 0.02.
          if addons:camera:flightcamera:pitch < 15 { set addons:camera:flightcamera:pitch to 15. }
          if addons:camera:flightcamera:distance < 60 { set addons:camera:flightcamera:distance to 60. }
        }
        set activeCutStartTime to time:seconds. // Hold cut timer during on-rails warp
      } else {
        local cut is activeCameraCuts[activeCutIndex].
        
        // Initialize start altitude for ground flyby if specified
        if cut:haskey("groundOffset") and not cut:haskey("startAlt") {
          set cut["startAlt"] to ship:altitude.
        }
        
        // Resolve static position at the start of the cut if offset is specified
        if cut:haskey("offset") and not cut:haskey("staticPos") {
          set cut["staticPos"] to ship:position + cut["offset"].
        }

        // Resolve orbitOffset if specified
        if cut:haskey("orbitOffset") and not cut:haskey("startBodyPos") {
          set cut["startVel"] to ship:velocity:orbit.
          set cut["offsetVec"] to cut["orbitOffset"].
          set cut["startBodyPos"] to body:position.
        }
        
        local elapsed is time:seconds - activeCutStartTime.
        local duration is cut["duration"].
        local t is elapsed / duration.
        
        // Check if current cut has finished
        if t >= 1 {
          // Set camera to final cut state (only if endH exists)
          if cut:haskey("endH") {
            set addons:camera:flightcamera:heading to cut["endH"].
            set addons:camera:flightcamera:pitch to cut["endP"].
            set addons:camera:flightcamera:distance to cut["endD"].
          }
          
          // Move to next cut
          set activeCutIndex to activeCutIndex + 1.
          if activeCutIndex < activeCameraCuts:length {
            set activeCutStartTime to time:seconds.
            local nextCut is activeCameraCuts[activeCutIndex].
            if nextCut:haskey("target") {
              set addons:camera:flightcamera:target to nextCut["target"].
            }
            if nextCut:haskey("offset") {
              set nextCut["staticPos"] to ship:position + nextCut["offset"].
            }
            if nextCut:haskey("orbitOffset") {
              set nextCut["startVel"] to ship:velocity:orbit.
              set nextCut["offsetVec"] to nextCut["orbitOffset"].
              set nextCut["startBodyPos"] to body:position.
            }
            if nextCut:haskey("groundOffset") {
              set nextCut["startAlt"] to ship:altitude.
            }
          } else {
            stopCameraScene(). // Completed all cuts in the scene
          }
        } else {
          if cut:haskey("staticPos") or cut:haskey("groundOffset") or cut:haskey("startBodyPos") or cut:haskey("bodyBackground") {
            local v_sc is v(0,0,0).
            if cut:haskey("groundOffset") {
              local height is ship:altitude - cut["startAlt"].
              set v_sc to -height * up:vector + cut["groundOffset"].
            } else if cut:haskey("startBodyPos") {
              set v_sc to body:position - cut["startBodyPos"] + (cut["startVel"] * elapsed) + cut["offsetVec"].
            } else if cut:haskey("bodyBackground") {
              local sunDir is (BODY("Sun"):position - ship:position):normalized.
              set v_sc to (-body:position:normalized + sunDir * 0.4):normalized * cut["distance"].
            } else {
              set v_sc to cut["staticPos"] - ship:position.
            }
            
            local northVec is heading(0,0):vector.
            local eastVec is heading(90,0):vector.
            local horizVec is v_sc - vdot(v_sc, up:vector) * up:vector.
            local h is arctan2(vdot(eastVec, horizVec), vdot(northVec, horizVec)).
            if h < 0 { set h to h + 360. }
            local p is 90 - vAng(up:vector, v_sc).
            local d is v_sc:mag.
            
            local maxD is 300.
            if cut:haskey("groundOffset") { set maxD to 500. }
            
            if d > maxD { set d to maxD. }
            if d < 5 { set d to 5. }
            if p < -85 { set p to -85. }
            if p > 85 { set p to 85. }
            
            set addons:camera:flightcamera:heading to h.
            set addons:camera:flightcamera:pitch to p.
            set addons:camera:flightcamera:distance to d.
          } else {
            // Smooth Ease-InOut interpolation (cosine)
            local smoothT is (1 - cos(t * 180)) / 2.
            
            if cut:haskey("endH") {
              local hDiff is cut["endH"] - cut["startH"].
              set addons:camera:flightcamera:heading to cut["startH"] + smoothT * hDiff.

              local pDiff is cut["endP"] - cut["startP"].
              set addons:camera:flightcamera:pitch to cut["startP"] + smoothT * pDiff.

              local dDiff is cut["endD"] - cut["startD"].
              set addons:camera:flightcamera:distance to cut["startD"] + smoothT * dDiff.
            }
          }
        }
      }
    } else {
      // Fallback Slow Orbital Pan: ensure view is never completely static in Flight view
      if not MAPVIEW and kuniverse:timewarp:rate = 1 {
        set addons:camera:flightcamera:heading to addons:camera:flightcamera:heading + 0.03.
        
        // Keep pitch and distance within a cinematic sweet spot
        if addons:camera:flightcamera:pitch < 12 { set addons:camera:flightcamera:pitch to 12. }
        if addons:camera:flightcamera:pitch > 35 { set addons:camera:flightcamera:pitch to 35. }
        if addons:camera:flightcamera:distance > 100 { set addons:camera:flightcamera:distance to 100. }
        if addons:camera:flightcamera:distance < 25 { set addons:camera:flightcamera:distance to 25. }
      }
    }
    preserve.
  }
}

// Low-level function to start a multi-cut scene
global function startCameraScene {
  parameter cutsList.
  
  if not hasCameraAddon { return. }
  
  set cameraDirectorActive to true.
  set stagingCutsEnabled to true.
  activeCameraCuts:clear().
  for cut in cutsList {
    activeCameraCuts:add(cut).
  }
  
  set activeCutIndex to 0.
  set activeCutStartTime to time:seconds.
  
  // Set initial target for the first cut
  if activeCameraCuts:length > 0 {
    local firstCut is activeCameraCuts[0].
    if firstCut:haskey("target") {
      set addons:camera:flightcamera:target to firstCut["target"].
    } else {
      set addons:camera:flightcamera:target to ship.
    }
    if firstCut:haskey("offset") {
      set firstCut["staticPos"] to ship:position + firstCut["offset"].
    }
    if firstCut:haskey("orbitOffset") {
      set firstCut["startVel"] to ship:velocity:orbit.
      set firstCut["offsetVec"] to firstCut["orbitOffset"].
      set firstCut["startBodyPos"] to body:position.
    }
    if firstCut:haskey("groundOffset") {
      set firstCut["startAlt"] to ship:altitude.
    }
  }
}

// Scene 1: Launch Scene (Exhaust close-up, tower release, wide climb)
global function playLaunchScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 {
    set duration to 10.
  }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", sunH + 140, "endH", sunH + 110, "startP", 12, "endP", 8, "startD", 35, "endD", 45)
  )).
  set stagingCutsEnabled to false.
}

global function playLiftoffScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 {
    set duration to 30.
  }
  local sunH is getSunHeading().
  local camOffset is heading(sunH + 120, 2):vector * 45.
  
  startCameraScene(list(
    lexicon("duration", duration, "groundOffset", camOffset)
  )).
  set stagingCutsEnabled to false.
}

global function playLiftoffClimbScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 {
    set duration to 15.
  }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", sunH - 30, "endH", sunH - 50, "startP", 8, "endP", 15, "startD", 30, "endD", 50)
  )).
  set stagingCutsEnabled to false.
}

// Scene 2: Ascend Scene (Booster separation tracking, engine thrust sweep, ultra-slow orbital pan)
global function playAscendScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 150. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration * 0.4, "startH", sunH - 90, "endH", sunH + 10, "startP", 35, "endP", 22, "startD", 40, "endD", 55),
    lexicon("duration", duration * 0.6, "startH", sunH - 190, "endH", sunH - 10, "startP", 22, "endP", 12, "startD", 55, "endD", 85)
  )).
}

// Scene 3: Orbiting Scene (Ultra-slow cinematic planetary orbit pan - alternating subtle sweeps)
global function playOrbitScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 100. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration * 0.6, "startH", sunH - 30, "endH", sunH + 30, "startP", 25, "endP", 16, "startD", 35, "endD", 50),
    lexicon("duration", duration * 0.4, "startH", sunH + 40, "endH", sunH - 10, "startP", 40, "endP", 25, "startD", 50, "endD", 40)
  )).
}

// Alignment / Reorientation Scene (Dynamic close-up tracking RCS thruster firings & rotation)
global function playAlignScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 100. }
  local shipH is getShipHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", shipH - 25, "endH", shipH + 25, "startP", 18, "endP", 24, "startD", 25, "endD", 35)
  )).
}

// Pre-Burn Waiting Scene (High-angle tracking shot of craft coasting aligned to node)
global function playPreBurnScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 100. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", sunH + 30, "endH", sunH - 30, "startP", 25, "endP", 18, "startD", 40, "endD", 50)
  )).
}

// Scene 4: Maneuver Burn Scene (3D Ignition rear 3/4 angle zoom-out, followed by slow orbital sweep)
global function playBurnScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 {
    if hasnode {
      local max_acc is max(0.1, ship:maxthrust / ship:mass).
      set duration to (nextnode:deltav:mag / max_acc) + 15.
    } else {
      set duration to 35.
    }
  }
  set duration to max(20, duration).
  
  local sunH is getSunHeading().
  
  // Calculate 3D thrust direction vector
  local burnDir is ship:facing:vector.
  if hasnode {
    set burnDir to nextnode:deltav:normalized.
  }
  local fwd is burnDir:normalized.
  local rgt is vcrs(fwd, up:vector).
  if rgt:mag < 0.001 { set rgt to vcrs(fwd, heading(90,0):vector). }
  set rgt to rgt:normalized.
  local upV is vcrs(fwd, rgt):normalized.
  
  // Camera 3D offset: 22m behind the engine exhaust nozzle (fwd * 22), 8m to left (-rgt * 8), 4m up (+upV * 4)
  local engineRearOffset is fwd * -22 - rgt * 8 + upV * 4.
  
  local cut1_dur is max(5, min(10, duration * 0.5)).
  local cut2_dur is duration - cut1_dur.
  
  local cutsList is list().
  // Cut 1: 3D engine rear angle view — camera stays behind engine nozzle in 3D space, rocket accelerates away!
  cutsList:add(lexicon("duration", cut1_dur, "orbitOffset", engineRearOffset)).
  
  // Cut 2: Slow orbital sweep around the burning ship (clockwise)
  if cut2_dur > 0 {
    cutsList:add(lexicon("duration", cut2_dur, "startH", sunH - 30, "endH", sunH + 30, "startP", 0, "endP", 20, "startD", 15, "endD", 45)).
  }
  
  startCameraScene(cutsList).
}

// Burn Cutoff / End Scene (Wide high-angle view watching engine shutdown & orbit release)
global function playBurnEndScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 8. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", sunH - 30, "endH", sunH + 30, "startP", 28, "endP", 18, "startD", 45, "endD", 60)
  )).
}

// Scene 5: Reentry Scene (Atmospheric entry slow sweep, plasma close-up)
global function playReentryScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 50. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration * 0.4, "startH", sunH + 40, "endH", sunH - 20, "startP", -15, "endP", 10, "startD", 30, "endD", 45),
    lexicon("duration", duration * 0.6, "startH", sunH - 20, "endH", sunH + 25, "startP", 10, "endP", 22, "startD", 45, "endD", 65)
  )).
}

// Scene 6: Parachute / Splashdown Scene (Chute deploy close-up, low touchdown sweep)
global function playChuteScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 45. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration * 0.5, "startH", sunH - 30, "endH", sunH + 10, "startP", 50, "endP", 25, "startD", 20, "endD", 35),
    lexicon("duration", duration * 0.5, "startH", sunH + 30, "endH", sunH - 10, "startP", 25, "endP", 10, "startD", 35, "endD", 50)
  )).
}

// Scene 7: Landing Scene (Suicide burn slow sweep, low touchdown sweep <20m)
global function playLandingScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 40. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration * 0.5, "startH", sunH - 30, "endH", sunH + 10, "startP", 28, "endP", 16, "startD", 40, "endD", 28),
    lexicon("duration", duration * 0.5, "startH", sunH + 30, "endH", sunH - 10, "startP", 16, "endP", 5, "startD", 28, "endD", 15)
  )).
}

// Scene 8: Staging Separation Scene (Close-up 3Model rear offset tracking interstage separation)
global function playStagingScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 8. }
  
  local fwd is ship:facing:vector:normalized.
  local rgt is vcrs(fwd, up:vector).
  if rgt:mag < 0.001 { set rgt to vcrs(fwd, heading(90,0):vector). }
  set rgt to rgt:normalized.
  local upV is vcrs(fwd, rgt):normalized.
  
  local stagingOffset is fwd * -20 + rgt * 6 + upV * 3.
  
  startCameraScene(list(
    lexicon("duration", duration, "orbitOffset", stagingOffset)
  )).
}

// Scene 9: SOI Transition Scene (Deep-space slow boundary pan)
global function playSOITransitionScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 40. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", sunH - 30, "endH", sunH + 30, "startP", 25, "endP", 15, "startD", 50, "endD", 75)
  )).
}

// Legacy alias for reentry/descent scene
global function playDescendScene {
  parameter duration is -1.
  playReentryScene(duration).
}

// Scene 10: Flyby / Close Encounter Scene (Wide approach slow sweep, ground pass, departure pan)
global function playFlybyScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 60. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration * 0.5, "startH", sunH - 30, "endH", sunH + 10, "startP", 25, "endP", 12, "startD", 45, "endD", 75),
    lexicon("duration", duration * 0.5, "startH", sunH + 40, "endH", sunH - 10, "startP", 12, "endP", 30, "startD", 75, "endD", 110)
  )).
}

// Scene 11: Lunar Launch / Ascent Scene (Single unified ultra-slow cinematic shot for airless body ascent)
global function playLunarLaunchScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 45. }
  local sunH is getSunHeading().
  
  startCameraScene(list(
    lexicon("duration", duration, "startH", sunH - 20, "endH", sunH + 20, "startP", 15, "endP", 25, "startD", 35, "endD", 65)
  )).
  set stagingCutsEnabled to false.
}

// Helper to get the heading towards Kerbin relative to current vessel position
global function getKerbinHeading {
  local targetBody is BODY("Kerbin").
  if not (body:name = "Mun" or body:name = "Minmus") {
    set targetBody to body.
  }
  local kerbinVec is targetBody:position - ship:position.
  local northVec is heading(0, 0):vector.
  local eastVec is heading(90, 0):vector.
  local horizVec is kerbinVec - vdot(kerbinVec, up:vector) * up:vector.
  if horizVec:mag < 0.001 { set horizVec to kerbinVec. }
  local kerbinH is arctan2(vdot(eastVec, horizVec), vdot(northVec, horizVec)).
  if kerbinH < 0 { set kerbinH to kerbinH + 360. }
  return kerbinH.
}

// Scene 12: Long Cinematic Rover Scene (Full 360° orbiting sweeps, Kerbin-in-background framing, wide angle zooms)
global function playRoverCinematicScene {
  parameter duration is -1.
  if not hasCameraAddon { return. }
  if duration <= 0 { set duration to 300. } // Default 5 minutes of continuous cinematic cuts
  
  local sunH is getSunHeading().
  local kerbinH is getKerbinHeading().
  // Camera heading looking PAST the rover toward Kerbin
  local kerbinBgH is kerbinH + 180.

  local cutTime is duration / 5.

  startCameraScene(list(
    // Cut 1: Kerbin Background Framing — Low-angle wide-zoom shot with Kerbin/Sky in background
    lexicon("duration", cutTime, "startH", kerbinBgH - 45, "endH", kerbinBgH + 45, "startP", 8, "endP", 14, "startD", 35, "endD", 18),

    // Cut 2: Full 360° Continuous Orbiting Sweep — Slowly circles around the rover
    lexicon("duration", cutTime * 1.5, "startH", sunH, "endH", sunH + 360, "startP", 15, "endP", 22, "startD", 20, "endD", 28),

    // Cut 3: Ultra-Wide Horizon & Terrain Sweep — Long cinematic zoom-out showing landscape
    lexicon("duration", cutTime, "startH", sunH + 90, "endH", sunH + 210, "startP", 10, "endP", 25, "startD", 15, "endD", 65),

    // Cut 4: Low-Angle Wheel & Track Pass — Close ground level sweep as rover drives/explores
    lexicon("duration", cutTime, "startH", sunH - 120, "endH", sunH - 30, "startP", 5, "endP", 12, "startD", 12, "endD", 25),

    // Cut 5: High Satellite Observer View — High-angle bird's eye orbit
    lexicon("duration", cutTime * 0.5, "startH", kerbinBgH + 30, "endH", kerbinBgH - 30, "startP", 45, "endP", 30, "startD", 50, "endD", 30)
  )).
}

// Stop current scene and release camera to manual control
global function stopCameraScene {
  if not hasCameraAddon { return. }
  set cameraDirectorActive to false.
  set stagingCutsEnabled to true.
  activeCameraCuts:clear().
}
