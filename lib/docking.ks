runOncePath("0:/lib/misc.ks").

// ============================================================
//  DOCKING GUIDANCE SYSTEM v4
//  - Interactive target port selection
//  - Route planning for ANY port orientation (front/side/rear)
//  - Main engine approach with retrograde braking
//  - RCS for rotation and micro corrections only
//  - Automatic obstacle avoidance around target vessel
//  - Physics warp during long-range cruise
// ============================================================

// -----------------------------------------------------------
//  UTILITY: clamp value between low and high
// -----------------------------------------------------------
function clamp {
  parameter val, low, high.
  return min(max(val, low), high).
}

// -----------------------------------------------------------
//  PORT SELECTION: interactive terminal menu
//  Returns the chosen DockingPort part.
//  portList = list of ready ports on a vessel.
// -----------------------------------------------------------
function selectPort {
  parameter portList.
  parameter vesselName.

  clearScreen.
  print "╔══════════════════════════════════════════╗".
  print "║     SELECT DOCKING PORT ON " + vesselName.
  print "╠══════════════════════════════════════════╣".

  local idx is 0.
  for p in portList {
    set idx to idx + 1.
    local tagStr is choose " [" + p:tag + "]" if p:tag <> "" else "".
    print "║ " + idx + ") " + p:name + tagStr + " (" + p:nodeType + ")".
  }
  print "╠══════════════════════════════════════════╣".
  print "║ 0) Auto-select (best-facing port)       ║".
  print "╚══════════════════════════════════════════╝".
  print " ".
  print "Enter port number: ".

  // Flush any stale input
  until not terminal:input:haschar { terminal:input:getchar(). }

  // Read user input (single digit for simplicity)
  local choice is -1.
  until choice >= 0 and choice <= portList:length {
    if terminal:input:haschar {
      local ch is terminal:input:getchar().
      // Convert ASCII character to number
      local num is ch:tonumber(-1).
      if num >= 0 and num <= portList:length {
        set choice to num.
      } else {
        print "Invalid choice. Try again: ".
      }
    }
    wait 0.
  }

  if choice = 0 {
    return 0.  // signal auto-select
  }
  return portList[choice - 1].
}

// -----------------------------------------------------------
//  FIND COMPATIBLE PORTS (with interactive selection)
//  Returns list(targetPort, shipPort).
// -----------------------------------------------------------
function findCompatiblePorts {
  parameter t.
  parameter interactiveSelect is true.

  local targetPort is 0.
  local shipPort is 0.

  // --- TARGET PORT ---
  if t:istype("DockingPort") {
    set targetPort to t.
  } else {
    // Gather ready ports
    local readyPorts is list().
    for p in t:dockingports {
      if p:state = "Ready" { readyPorts:add(p). }
    }

    if readyPorts:length = 0 {
      return list(0, 0).
    }

    if readyPorts:length = 1 {
      set targetPort to readyPorts[0].
      print "Only one target port available: " + targetPort:name.
    } else if interactiveSelect {
      local chosen is selectPort(readyPorts, t:name).
      if chosen = 0 {
        // Auto-select: pick best-facing port
        set targetPort to autoSelectTargetPort(readyPorts).
      } else {
        set targetPort to chosen.
      }
    } else {
      set targetPort to autoSelectTargetPort(readyPorts).
    }
  }

  if targetPort = 0 { return list(0, 0). }

  // --- SHIP PORT ---
  local bestScore is -9999.
  for p in ship:dockingports {
    if p:state = "Ready" and p:nodeType = targetPort:nodeType {
      local score is 0.
      // Current control part has highest priority
      if ship:hasSuffix("controlpart") and ship:controlpart = p {
        set score to score + 1000.
      }
      // Standard tags
      local tagLower is p:tag:tolower().
      if tagLower = "active" or tagLower = "dock" or tagLower = "main" {
        set score to score + 100.
      }
      // Alignment with ship facing
      set score to score + vDot(p:portfacing:forevector, ship:facing:forevector) * 10000.

      if score > bestScore {
        set bestScore to score.
        set shipPort to p.
      }
    }
  }

  return list(targetPort, shipPort).
}

// -----------------------------------------------------------
//  AUTO-SELECT: pick the target port that faces our ship best
// -----------------------------------------------------------
function autoSelectTargetPort {
  parameter portList.
  local bestScore is -9999.
  local bestPort is portList[0].
  for p in portList {
    local score is 0.
    local tagLower is p:tag:tolower().
    if tagLower = "active" or tagLower = "dock" or tagLower = "main" {
      set score to score + 100.
    }
    set score to score + vDot(p:portfacing:forevector, -p:position:normalized) * 10.
    if score > bestScore {
      set bestScore to score.
      set bestPort to p.
    }
  }
  return bestPort.
}

// -----------------------------------------------------------
//  PD TRANSLATION CONTROLLER
//  Computes and applies ship:control:translation using a
//  proportional-derivative approach to track a position error.
//    errX/Y/Z  = position error in port-local frame
//    Kp        = proportional gain (target vel = error * Kp)
//    Kd        = derivative gain  (thrust = vel_error * Kd)
//    maxVel    = maximum velocity to command
//    refPort   = reference docking port (defines local frame)
//    relVel    = relative velocity vector (ship - target)
// -----------------------------------------------------------
function controlTranslationPD {
  parameter errX, errY, errZ.
  parameter Kp, Kd, maxVel.
  parameter refPort, relVel.

  // Desired velocity proportional to error, clamped
  local targetVelX is clamp(errX * Kp, -maxVel, maxVel).
  local targetVelY is clamp(errY * Kp, -maxVel, maxVel).
  local targetVelZ is clamp(errZ * Kp, -maxVel, maxVel).

  // Current velocity in port-local frame
  local curVelX is vDot(relVel, refPort:portfacing:rightvector).
  local curVelY is vDot(relVel, refPort:portfacing:upvector).
  local curVelZ is vDot(relVel, refPort:portfacing:forevector).

  // Velocity error * derivative gain = thrust command
  local transX is clamp((targetVelX - curVelX) * Kd, -1, 1).
  local transY is clamp((targetVelY - curVelY) * Kd, -1, 1).
  local transZ is clamp((targetVelZ - curVelZ) * Kd, -1, 1).

  set ship:control:translation to V(transX, transY, transZ).
}

// -----------------------------------------------------------
//  ZERO RELATIVE VELOCITY
//  Brings relative velocity to near-zero using RCS.
// -----------------------------------------------------------
function zeroRelVel {
  parameter vesselTarget.
  parameter threshold is 0.08.
  parameter timeout is 30.

  local t0 is time:seconds.
  until (ship:velocity:orbit - vesselTarget:velocity:orbit):mag < threshold {
    if time:seconds - t0 > timeout { break. }
    local relVel is ship:velocity:orbit - vesselTarget:velocity:orbit.
    local transX is clamp(-vDot(relVel, ship:facing:rightvector) * 3.0, -1, 1).
    local transY is clamp(-vDot(relVel, ship:facing:upvector) * 3.0, -1, 1).
    local transZ is clamp(-vDot(relVel, ship:facing:forevector) * 3.0, -1, 1).
    set ship:control:translation to V(transX, transY, transZ).
    wait 0.
  }
  set ship:control:translation to V(0, 0, 0).
}

// ============================================================
//  ENGINE APPROACH: Reusable fly-to-waypoint using main engine.
//
//  Aligns toward a dynamic target position, accelerates with
//  main engine, coasts (physics warp if far), flips retrograde
//  to brake, then zeros velocity with RCS.
//
//  getTargetPos: delegate returning the current waypoint
//                position vector (relative to ship).
//  vesselTarget: the target vessel (for relative velocity).
//  label:        display label for HUD.
//  maxSpeed:     max approach speed in m/s.
//  arrivalMargin: extra margin added to braking distance.
// ============================================================
function engineApproach {
  parameter vesselTarget.
  parameter getTargetPos.
  parameter label is "Waypoint".
  parameter maxSpeed is 3.0.
  parameter arrivalMargin is 15.

  local targetPos is getTargetPos().
  local dist is targetPos:mag.

  if dist < 8 { return. }  // already close enough

  clearScreen.
  print "═══ " + label + " ═══" at (0, 0).

  local tset is 0.
  lock throttle to tset.

  // --- Align toward target ---
  local approachDir is targetPos:normalized.
  lock steering to lookDirUp(approachDir, ship:up:vector).

  print "Aligning..." at (0, 2).
  local t0 is time:seconds.
  until vAng(ship:facing:forevector, approachDir) < 3 or (time:seconds - t0 > 25) {
    set targetPos to getTargetPos().
    set approachDir to targetPos:normalized.
    wait 0.
  }

  // --- Accelerate ---
  local brakeThrottle is 0.1.
  local brakeAccel is max(ship:availableThrust * brakeThrottle / ship:mass, 0.01).
  local flipTime is 10.

  set targetPos to getTargetPos().
  set dist to targetPos:mag.
  local maxSafeSpeed is sqrt(2 * brakeAccel * max(dist - arrivalMargin, 5) * 0.4).
  local desiredSpeed is clamp(min(dist * 0.03, min(maxSafeSpeed, maxSpeed)), 0.5, maxSpeed).

  local relVel is ship:velocity:orbit - vesselTarget:velocity:orbit.
  local closingSpeed is vDot(relVel, approachDir).

  print "Accelerating..." at (0, 2).
  until closingSpeed >= desiredSpeed * 0.9 {
    set targetPos to getTargetPos().
    set approachDir to targetPos:normalized.
    set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.
    set closingSpeed to vDot(relVel, approachDir).
    set tset to clamp((desiredSpeed - closingSpeed) * 0.3, 0, 0.15).

    print "Speed:    " + round(closingSpeed, 2) + " / " + round(desiredSpeed, 1) + " m/s   " at (0, 3).
    print "Throttle: " + round(tset * 100, 1) + "%       " at (0, 4).
    wait 0.
  }
  set tset to 0.

  // --- Coast (physics warp for long distances) ---
  set targetPos to getTargetPos().
  set dist to targetPos:mag.

  if dist > 250 {
    set kuniverse:timewarp:mode to "PHYSICS".
    set kuniverse:timewarp:rate to 3.
    print "Physics warp engaged..." at (0, 6).
  }

  print "Coasting..." at (0, 2).
  until false {
    set targetPos to getTargetPos().
    set dist to targetPos:mag.
    set approachDir to targetPos:normalized.
    set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.
    set closingSpeed to vDot(relVel, targetPos:normalized).

    local brakeDist is closingSpeed^2 / (2 * max(brakeAccel, 0.01)).
    local flipDist is abs(closingSpeed) * flipTime.
    local startBrakeAt is brakeDist + flipDist + arrivalMargin.

    local projDist is dist.
    if relVel:mag > 0.05 {
      set projDist to vDot(targetPos, relVel:normalized).
    }

    // Drop warp before braking
    if projDist < startBrakeAt + 100 and kuniverse:timewarp:rate > 1 {
      set kuniverse:timewarp:rate to 1.
      wait until kuniverse:timewarp:issettled.
      print "Warp disengaged.           " at (0, 6).
    }

    print "Distance:  " + round(dist, 1) + " m      " at (0, 3).
    print "Speed:     " + round(closingSpeed, 2) + " m/s   " at (0, 4).
    print "Brake at:  " + round(startBrakeAt, 0) + " m      " at (0, 5).

    if projDist <= startBrakeAt { break. }
    // Safety: if we somehow passed it
    if projDist < 0 { break. }
    wait 0.
  }

  // Ensure warp is off
  if kuniverse:timewarp:rate > 1 {
    set kuniverse:timewarp:rate to 1.
    wait until kuniverse:timewarp:issettled.
  }

  // --- Brake to stop ---
  set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.

  if relVel:mag > 2.0 {
    // High speed: flip retrograde and engine brake.
    // Only fire engine when aimed within 5° to prevent torque-induced spins.
    print "Flipping retrograde..." at (0, 2).
    local retroDir is -relVel:normalized.
    lock steering to lookDirUp(retroDir, ship:up:vector).

    local flipT0 is time:seconds.
    until vAng(ship:facing:forevector, retroDir) < 5 or (time:seconds - flipT0 > 20) {
      set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.
      if relVel:mag > 0.5 { set retroDir to -relVel:normalized. }
      wait 0.
    }

    print "Braking..." at (0, 2).
    until relVel:mag < 0.5 {
      set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.
      if relVel:mag > 0.5 { set retroDir to -relVel:normalized. }

      // ONLY fire when aimed correctly — off-axis thrust causes spins
      local steerErr is vAng(ship:facing:forevector, retroDir).
      if steerErr < 5 {
        set tset to clamp(relVel:mag * 0.3, 0, brakeThrottle).
      } else {
        set tset to 0.
      }

      set targetPos to getTargetPos().
      print "Distance:  " + round(targetPos:mag, 1) + " m      " at (0, 3).
      print "Speed:     " + round(relVel:mag, 2) + " m/s   " at (0, 4).
      print "Steer Err: " + round(steerErr, 1) + " deg     " at (0, 5).
      print "Throttle:  " + round(tset * 100, 1) + "%       " at (0, 6).
      wait 0.
    }
    set tset to 0.
  } else {
    print "Low speed — RCS braking..." at (0, 2).
  }

  // RCS zeros whatever remains (handles low-speed cases entirely)
  print "Zeroing velocity (RCS)..." at (0, 7).
  zeroRelVel(vesselTarget, 0.1, 20).
}

// ============================================================
//  MAIN DOCKING FUNCTION
//
//  Philosophy: Main engines for all significant velocity
//  changes. RCS for rotation and micro lateral corrections.
//  Coast whenever possible.
//
//  Route planning handles ANY port orientation:
//  - Front-facing ports: direct approach
//  - Side/rear-facing ports: routes around the station first
//    to reach the approach side of the port
//
//  With controlfrom(port):
//    ship:facing:forevector = port forward = engine thrust dir
//    lock steering to V  -> port faces V, engine pushes toward V
// ============================================================
function dockToTarget {
  parameter vesselTarget is target.
  parameter selectedPort is 0.

  if vesselTarget:istype("DockingPort") {
    set selectedPort to vesselTarget.
    set vesselTarget to vesselTarget:ship.
  }

  clearScreen.
  print "--- Docking System v4 Initialized ---" at (0, 0).

  // --- Port discovery ---
  local ports is 0.
  if selectedPort:istype("DockingPort") {
    set ports to findCompatiblePorts(selectedPort, false).
  } else {
    set ports to findCompatiblePorts(vesselTarget, true).
  }

  local targetPort is ports[0].
  local shipPort is ports[1].

  if targetPort = 0 or shipPort = 0 {
    clearScreen.
    print "ERROR: No compatible docking ports found!" at (0, 2).
    print "Ensure both vessels have open, matching ports." at (0, 3).
    return.
  }

  shipPort:controlfrom().
  set target to targetPort.
  sas off.
  rcs on.

  local tset is 0.
  lock throttle to tset.

  clearScreen.
  print "╔══════════════════════════════════════════╗" at (0, 0).
  print "║         DOCKING GUIDANCE ACTIVE          ║" at (0, 1).
  print "╠══════════════════════════════════════════╣" at (0, 2).
  print "║ Target Port: " + targetPort:name at (0, 3).
  print "║   Ship Port: " + shipPort:name at (0, 4).
  print "╚══════════════════════════════════════════╝" at (0, 5).
  wait 2.

  // ========================================================
  //  ROUTE PLANNING
  //
  //  Determine if we can approach the corridor directly or
  //  if the path to the standoff point goes through the
  //  target vessel (side/rear-facing port). If blocked,
  //  compute clearance waypoints to route AROUND the station.
  //
  //  Geometry:
  //    portAxis = direction the target port faces (outward)
  //    approachSide = dot(-shipToPort, portAxis)
  //      > 0 means we can "see" the port face (correct side)
  //      < 0 means the port faces away from us (wrong side)
  //
  //  If on the wrong side, the route is:
  //    1. Fly to a clearance waypoint perpendicular to the
  //       port axis, at safe distance from the station center
  //    2. Fly to the corridor entry point on the approach side
  //    3. Normal corridor descent + final approach
  // ========================================================
  local portAxis is targetPort:portfacing:forevector.
  local shipToPort is targetPort:position.

  // How far we are on the approach side (positive = correct side)
  local approachSide is vDot(-shipToPort, portAxis).

  // Estimate station size: distance from center to port + margin
  local portFromCenter is (targetPort:position - vesselTarget:position):mag.
  local clearance is max(portFromCenter + 20, 30).

  // Corridor entry distance: far enough to clear the entire station
  local corridorEntryDist is max(clearance, 40).

  clearScreen.
  print "Planning approach route..." at (0, 0).
  print "  Port axis check: " + round(approachSide, 1) at (0, 2).
  print "  Clearance radius: " + round(clearance, 0) + " m" at (0, 3).

  // --- Check if we need to go around the station ---
  local needsRouteAround is approachSide < clearance * 0.3.

  if needsRouteAround {
    print "  Route: AROUND station (port faces away)" at (0, 5).
    wait 2.

    // Compute the perpendicular direction to escape the port axis.
    // Use our current offset from the port axis as the escape
    // direction (go outward from our current side), so the shortest
    // path around the station is chosen.
    local shipRelTarget is -vesselTarget:position.
    local perpComp is shipRelTarget - vDot(shipRelTarget, portAxis) * portAxis.

    // If we're directly on the axis (no perpendicular offset),
    // pick an arbitrary perpendicular direction.
    if perpComp:mag < 3 {
      set perpComp to vCrs(portAxis, ship:up:vector).
      if perpComp:mag < 0.1 { set perpComp to vCrs(portAxis, V(1, 0, 0)). }
    }
    local perpDir is perpComp:normalized.

    // --- Clearance waypoint ---
    // Fly perpendicular to port axis to get "to the side" of the
    // station. From there, the diagonal to a far corridor entry
    // point clears the station body.
    engineApproach(vesselTarget, {
      return vesselTarget:position + perpDir * (clearance + 15).
    }, "Going around station", 3.0, 10).

    // Extend corridor entry distance so the diagonal from our
    // perpendicular position clears the station.
    set corridorEntryDist to max(clearance * 1.8, 60).
  } else {
    print "  Route: DIRECT (port faces toward us)" at (0, 5).
    wait 1.
  }

  // --- Corridor entry: aligned with port axis, far enough out ---
  local corridorEntryPos is targetPort:position + portAxis * corridorEntryDist.
  if corridorEntryPos:mag > 10 {
    engineApproach(vesselTarget, {
      return targetPort:position + targetPort:portfacing:forevector * corridorEntryDist.
    }, "Corridor entry", 3.0, 10).
  }

  // ========================================================
  //  PHASE 2: Corridor Alignment
  //  We are now at the corridor entry point, on the correct
  //  approach side. Align anti-parallel and descend along
  //  the corridor axis to the 15m standoff point.
  //  Engine for Z-axis closing, RCS for lateral.
  // ========================================================
  clearScreen.
  print "═══ Phase 2: Corridor Alignment ═══" at (0, 0).
  lock throttle to tset.

  shipPort:controlfrom().
  lock steering to lookDirUp(-targetPort:portfacing:forevector, targetPort:portfacing:upvector).

  print "Aligning with port axis..." at (0, 2).
  local alignT0 is time:seconds.
  until vAng(shipPort:portfacing:forevector, -targetPort:portfacing:forevector) < 5 or (time:seconds - alignT0 > 25) {
    wait 0.
  }

  local standoffDist is 15.
  local phase2start is time:seconds.
  local phase2timeout is 120.

  until false {
    local goalPos is targetPort:position + targetPort:portfacing:forevector * standoffDist.
    local errorVec is goalPos - shipPort:position.

    local errorX is vDot(errorVec, shipPort:portfacing:rightvector).
    local errorY is vDot(errorVec, shipPort:portfacing:upvector).
    local errorZ is vDot(errorVec, shipPort:portfacing:forevector).
    local errorMag is errorVec:mag.

    local relVel is ship:velocity:orbit - vesselTarget:velocity:orbit.
    local curVelX is vDot(relVel, shipPort:portfacing:rightvector).
    local curVelY is vDot(relVel, shipPort:portfacing:upvector).
    local curVelZ is vDot(relVel, shipPort:portfacing:forevector).
    local steerError is vAng(shipPort:portfacing:forevector, -targetPort:portfacing:forevector).

    local maxLatVel is clamp(errorMag * 0.12, 0.05, 0.6).

    print "Corridor Dist: " + round(errorMag, 2) + " m    " at (0, 2).
    print "  Error X/Y/Z: " + round(errorX,1) + "/" + round(errorY,1) + "/" + round(errorZ,1) + " m  " at (0, 3).
    print "Steer Error:   " + round(steerError, 1) + " deg    " at (0, 4).
    print "Rel Velocity:  " + round(relVel:mag, 3) + " m/s   " at (0, 5).

    if errorMag < 1.0 and steerError < 3 and relVel:mag < 0.15 {
      print "Status: Standoff reached!                " at (0, 7).
      break.
    }
    if time:seconds - phase2start > phase2timeout and errorMag < 3.0 {
      print "Status: Timeout — proceeding              " at (0, 7).
      break.
    }

    if steerError > 10 {
      set ship:control:translation to V(0, 0, 0).
      set tset to 0.
      print "Status: Aligning...                       " at (0, 7).
    } else {
      // Z-axis: engine and RCS for closing, RCS for braking/reversing
      local targetVelZ is clamp(errorZ * 0.1, -0.5, 0.5).
      local velErrorZ is targetVelZ - curVelZ.

      if velErrorZ > 0.05 and errorZ > 0.5 {
        set tset to clamp(velErrorZ * 1.5, 0, 1.0).
        if ship:availablethrust = 0 {
          for eng in ship:engines {
            if not eng:ignition { eng:activate(). }
          }
        }
      } else {
        set tset to 0.
      }

      // X/Y: RCS lateral corrections
      local targetVelX is clamp(errorX * 0.2, -maxLatVel, maxLatVel).
      local targetVelY is clamp(errorY * 0.2, -maxLatVel, maxLatVel).
      local transX is clamp((targetVelX - curVelX) * 3.0, -1, 1).
      local transY is clamp((targetVelY - curVelY) * 3.0, -1, 1).

      local transZ is clamp(velErrorZ * 3.0, -1, 1).

      set ship:control:starboard to transX.
      set ship:control:top to transY.
      set ship:control:fore to transZ.
      print "Status: Positioning... (Thr " + round(tset*100, 1) + "%)          " at (0, 7).
      print "                                                " at (0, 11).
    }
    wait 0.
  }

  set tset to 0.
  set ship:control:translation to V(0, 0, 0).
  zeroRelVel(vesselTarget, 0.1, 10).

  // ========================================================
  //  PHASE 3: Final Docking Descent
  //  Gentle engine pulse to start closing, then coast in.
  //  RCS handles lateral micro-corrections only.
  // ========================================================
  clearScreen.
  print "═══ Phase 3: Final Descent ═══" at (0, 0).
  lock throttle to tset.

  lock steering to lookDirUp(-targetPort:portfacing:forevector, targetPort:portfacing:upvector).

  local alignT0 is time:seconds.
  until vAng(shipPort:portfacing:forevector, -targetPort:portfacing:forevector) < 2 or (time:seconds - alignT0 > 10) {
    wait 0.
  }

  // Gentle engine pulse to ~0.3 m/s
  local relVel is ship:velocity:orbit - vesselTarget:velocity:orbit.
  local closingVel is vDot(relVel, shipPort:portfacing:forevector).

  print "Starting approach..." at (0, 2).
  until closingVel >= 0.25 {
    set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.
    set closingVel to vDot(relVel, shipPort:portfacing:forevector).
    set tset to clamp((0.3 - closingVel) * 1.0, 0, 0.5).
    wait 0.
  }
  set tset to 0.

  // Coast with lateral corrections until docked
  until shipPort:state = "Docked" or shipPort:state = "PreAttached" or not HASTARGET {
    local errorVec is targetPort:position - shipPort:position.
    local errorX is vDot(errorVec, shipPort:portfacing:rightvector).
    local errorY is vDot(errorVec, shipPort:portfacing:upvector).
    local errorZ is vDot(errorVec, shipPort:portfacing:forevector).

    set relVel to ship:velocity:orbit - vesselTarget:velocity:orbit.
    local steerError is vAng(shipPort:portfacing:forevector, -targetPort:portfacing:forevector).
    local lateralError is sqrt(errorX^2 + errorY^2).
    local approachVel is vDot(relVel, shipPort:portfacing:forevector).

    print "Distance:       " + round(errorZ, 2) + " m      " at (0, 2).
    print "Lateral Offset: " + round(lateralError, 3) + " m   " at (0, 3).
    print "Steer Error:    " + round(steerError, 1) + " deg   " at (0, 4).
    print "Approach Speed: " + round(approachVel, 3) + " m/s   " at (0, 5).
    print "Port State:     " + shipPort:state + "       " at (0, 7).

    if steerError > 15 or lateralError > 1.5 {
      set tset to 0.
      local curVelX is vDot(relVel, shipPort:portfacing:rightvector).
      local curVelY is vDot(relVel, shipPort:portfacing:upvector).
      local curVelZ is vDot(relVel, shipPort:portfacing:forevector).
      local latTargVelX is clamp(errorX * 0.3, -0.3, 0.3).
      local latTargVelY is clamp(errorY * 0.3, -0.3, 0.3).
      set ship:control:translation to V(
        clamp((latTargVelX - curVelX) * 3.0, -1, 1),
        clamp((latTargVelY - curVelY) * 3.0, -1, 1),
        clamp((0 - curVelZ) * 3.0, -1, 1)
      ).
      if steerError > 15 {
        print "Status: HOLD — Correcting orientation     " at (0, 9).
      } else {
        print "Status: HOLD — Correcting lateral drift   " at (0, 9).
      }
    } else {
      local targetSpeed is clamp(errorZ * 0.05, -0.5, 0.5).
      if abs(targetSpeed) < 0.05 {
        set targetSpeed to 0.05 * (choose 1 if errorZ >= 0 else -1).
      }
      if lateralError > 0.5 {
        set targetSpeed to targetSpeed * 0.3.
      }

      if approachVel < targetSpeed - 0.03 {
        set tset to clamp((targetSpeed - approachVel) * 1.0, 0, 0.2).
      } else {
        set tset to 0.
      }

      local curVelX is vDot(relVel, shipPort:portfacing:rightvector).
      local curVelY is vDot(relVel, shipPort:portfacing:upvector).
      local latTargVelX is clamp(errorX * 0.3, -0.3, 0.3).
      local latTargVelY is clamp(errorY * 0.3, -0.3, 0.3).

      local transZ is clamp((targetSpeed - approachVel) * 3.0, -1, 1).

      set ship:control:starboard to clamp((latTargVelX - curVelX) * 3.0, -1, 1).
      set ship:control:top to clamp((latTargVelY - curVelY) * 3.0, -1, 1).
      set ship:control:fore to transZ.
      
      print "Status: Approaching (RCS Z: " + round(transZ, 2) + ")            " at (0, 9).
    }
    wait 0.
  }

  // ========================================================
  //  CLEANUP
  // ========================================================
  set tset to 0.
  set ship:control:translation to V(0, 0, 0).
  unlock steering.
  unlock throttle.
  rcs off.
  clearScreen.
  print "╔═════════════════════════════════════╗".
  print "║        DOCKING SUCCESSFUL!          ║".
  print "╚═════════════════════════════════════╝".
  print " ".
  print "Welcome aboard.".
  wait 3.
}
