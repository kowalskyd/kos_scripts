runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/transfer.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

function relativeInclination {
  parameter orb1, orb2.
  local inc1 is orb1:inclination.
  local lan1 is orb1:lan.
  local inc2 is orb2:inclination.
  local lan2 is orb2:lan.
  local cos_rel is sin(inc1)*sin(inc2)*cos(lan1 - lan2) + cos(inc1)*cos(inc2).
  set cos_rel to max(-1, min(1, cos_rel)).
  return arccos(cos_rel).
}

function matchPlanes {
  parameter targetBody.

  local r_ship is ship:position - ship:body:position.
  local v_ship is ship:velocity:orbit.
  local N_ship is vcrs(r_ship, v_ship):normalized.
  
  local N_target is vcrs(targetBody:position - targetBody:body:position, targetBody:velocity:orbit):normalized.
  
  // Calculate relative inclination
  local rel_inc is vAng(N_ship, N_target).
  
  if rel_inc < 0.05 {
    logChatter("CapCom", "Planes aligned (Inc < 0.05°). Skipping change.").
    return.
  }
  
  logChatter("CapCom", "Inclination difference: " + round(rel_inc, 2) + "°").
  
  // Find AN/DN by scanning the orbit for where vdot(r, N_target) crosses zero
  // (i.e. where the ship's position enters the target orbital plane)
  local period is ship:orbit:period.
  local steps is 72.
  local dt is period / steps.
  local nodeList is list().
  
  local r0 is positionAt(ship, time:seconds) - ship:body:position.
  local prevDot is vdot(r0, N_target).
  local prevTime is time:seconds.
  
  local i is 1.
  until i > steps or nodeList:length >= 2 {
    local t is time:seconds + i * dt.
    local rPos is positionAt(ship, t) - ship:body:position.
    local curDot is vdot(rPos, N_target).
    
    if prevDot * curDot < 0 {
      // Sign change = zero crossing. Refine with bisection.
      local tLow is prevTime.
      local tHigh is t.
      local j is 0.
      until j > 20 {
        local tMid is (tLow + tHigh) / 2.
        local rMid is positionAt(ship, tMid) - ship:body:position.
        local midDot is vdot(rMid, N_target).
        if prevDot * midDot > 0 { set tLow to tMid. }
        else { set tHigh to tMid. }
        set j to j + 1.
      }
      nodeList:add((tLow + tHigh) / 2).
    }
    
    set prevDot to curDot.
    set prevTime to t.
    set i to i + 1.
  }
  
  if nodeList:length = 0 {
    logChatter("CapCom", "Error: Orbital node search failed.").
    return.
  }
  
  // Pick the earliest node; if it's too soon (<30s), use the second
  local burn_time is nodeList[0].
  if burn_time - time:seconds < 30 and nodeList:length >= 2 {
    set burn_time to nodeList[1].
  }
  local timeToNode is burn_time - time:seconds.
  
  // Simple pure normal burn: dV = 2 * v * sin(relative_inc / 2)
  local v_at_node is velocityAt(ship, burn_time):orbit:mag.
  local dv_normal is 2 * v_at_node * sin(rel_inc / 2).
  
  // Create node with +normal, then check if it moves inclination the right way
  local planeNode is node(burn_time, 0, dv_normal, 0).
  add planeNode.
  wait 0.
  
  // If +normal moved inclination AWAY from target, flip to -normal
  if relativeInclination(planeNode:orbit, targetBody:orbit) > relativeInclination(ship:orbit, targetBody:orbit) {
    set planeNode:normal to -dv_normal.
    wait 0.
  }
  
  logChatter("CapCom", "Plane alignment burn calculated.").
  hudMsg("PLANE ALIGNMENT BURN").
  wait 1.
  exeMnv().
}

if ship:status = "PRELAUNCH" or ship:status = "FLYING" or ship:orbit:periapsis < 70000 {
  clearScreen.
  print "=======================================".
  print "         MINMUS ORBIT MISSION ERROR    ".
  print "=======================================".
  print "Error: Vessel must be in a stable orbit".
  print "around Kerbin (Periapsis > 70km) to".
  print "initiate the Minmus transfer script.".
  print "---------------------------------------".
  print "Please run your launch script first.".
  print "=======================================".
  wait 5.
} else {
  runOncePath("0:/lib/hud.ks").
  initScreen("minmus_transfer").
  logChatter("CapCom", "Trans-Minmus injection sequence initiated.").
  hudMsg("MINMUS MISSION INITIATED").
  logChatter("Crew", "Deploying solar panels and antenna systems...").
  panels on.
  if antenna:length > 0 {
    deployAntenna().
  }
  wait 1.5.

  // 1. Target Minmus
  set target to BODY("Minmus").
  
  // 2. Perform Plane Change Maneuver
  set MAPVIEW to true.
  logChatter("CapCom", "Aligning orbital inclination with Minmus...").
  wait 1.
  matchPlanes(BODY("Minmus")).
  wait 1.5.

  // 3. Calculate and execute Hohmann transfer
  set MAPVIEW to true.
  logChatter("CapCom", "Calculating Hohmann transfer trajectory...").
  wait 1.
  transferToBody(BODY("Minmus"), false).
  logChatter("CapCom", "Transfer burn calculation complete.").

  // 4. Perform Mid-Course correction to tune the periapsis inside Minmus's SOI
  if not ship:orbit:hasnextpatch {
    logChatter("CapCom", "Searching for Minmus encounter...").
    
    local scanNode is node(time:seconds + 300, 0, 0, 0).
    add scanNode.
    
    local foundEncounter is false.
    
    // First: 1D prograde search (fast)
    local searchOffset is -40.
    until searchOffset > 40 or foundEncounter {
      set scanNode:prograde to searchOffset.
      if scanNode:orbit:hasnextpatch and scanNode:orbit:nextpatch:body:name = "Minmus" {
        set foundEncounter to true.
        break.
      }
      set searchOffset to searchOffset + 2.0.
    }
    
    // Second: 2D prograde-radial grid search if 1D failed
    if not foundEncounter {
      logChatter("CapCom", "Prograde search failed. Trying 2D prograde-radial search...").
      for proOffset in list(-20, -10, 0, 10, 20) {
        for radOffset in list(-15, -7.5, 7.5, 15) {
          set scanNode:prograde to proOffset.
          set scanNode:radialout to radOffset.
          if scanNode:orbit:hasnextpatch and scanNode:orbit:nextpatch:body:name = "Minmus" {
            set foundEncounter to true.
            break.
          }
        }
        if foundEncounter { break. }
      }
    }
    
    if foundEncounter {
      logChatter("CapCom", "Encounter located. Executing adjustment.").
      wait 1.
      exeMnv().
      wait 1.
    } else {
      logChatter("CapCom", "Encounter search failed. Reverting node.").
      remove scanNode.
      wait 1.
    }
  }

  if ship:orbit:hasnextpatch {
    // 5. Perform Mid-Course correction in Kerbin SOI (extremely cheap and precise)
    logChatter("CapCom", "Fine-tuning Minmus periapsis mid-course...").
    setNewPeriapsis(15000, 120, true).
    exeMnv().
    wait 1.5.

    // 6. Warp to SOI transition
    set MAPVIEW to true.
    logChatter("CapCom", "Warping to Minmus SOI transition.").
    warpto(time:seconds + ETA:transition + 120).
    wait until kuniverse:timewarp:rate = 1.
    set MAPVIEW to false.
    wait until ship:body:name = "Minmus".
    
    initScreen("minmus_encounter").
    logChatter("CapCom", "Signal acquired. Welcome to Minmus SOI.").
    hudMsg("ENTERED MINMUS SOI").
    wait 2.

    // 6. Calculate capture burn
    logChatter("CapCom", "Calculating Minmus orbit capture burn...").
    local r_pe is ship:orbit:periapsis + body:radius.
    local v_pe is sqrt(body:mu * (2/r_pe - 1/ship:orbit:semimajoraxis)).
    local v_circ is sqrt(body:mu / r_pe).
    local dv is v_circ - v_pe.

    local captureNode is node(time:seconds + ETA:periapsis, 0, 0, dv).
    add captureNode.
    wait 0.1.

    logChatter("CapCom", "Executing capture burn at periapsis.").
    hudMsg("MINMUS CAPTURE BURN ACTIVE").
    exeMnv().

    // 8. Mission summary
    initScreen("minmus_orbit").
    logChatter("CapCom", "Mission summary: Minmus orbit stabilized.").
    logChatter("Crew", "We are safely in Minmus orbit. The surface is glowing green!").
    hudMsg("MINMUS ORBIT ESTABLISHED").
    playOrbitScene().
  } else {
    logChatter("CapCom", "Error: Transfer failed to establish encounter.").
  }

  unlock steering.
  unlock throttle.
  set ship:control:pilotMainThrottle to 0.
    if not (defined automatedMission) {
    until false {
      updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
      wait 1.0.
    }
  } else {
    wait 5.
  }
}
