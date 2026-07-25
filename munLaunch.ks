runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

local targetOrbit is 35000.

if ship:body:name <> "Mun" {
  clearScreen.
  print "=======================================".
  print "      MUN LAUNCH SCRIPT ERROR          ".
  print "=======================================".
  print "Error: Vessel is not on the Mun.".
  print "Currently at: " + ship:body:name.
  print "=======================================".
  wait 5.
} else if ship:status <> "LANDED" and ship:status <> "PRELAUNCH" {
  clearScreen.
  print "=======================================".
  print "      MUN LAUNCH SCRIPT ERROR          ".
  print "=======================================".
  print "Error: Vessel is not landed on the Mun.".
  print "Status: " + ship:status.
  print "=======================================".
  wait 5.
} else {
  runOncePath("0:/lib/hud.ks").
  initScreen("mun_ascent").
  logChatter("CapCom", "Mun launch sequence initiated.").
  hudMsg("MUN ASCENT PREPARATION").

  // Check TWR on the Mun
  local gMun is body:mu / body:radius^2.

  // Make sure we have thrust
  if ship:maxthrust = 0 {
    logChatter("KAL-9000", "Staging to activate engine...").
    until ship:maxthrust > 0 or stage:number = 0 {
      wait until stage:ready.
      stage.
      wait 0.5.
    }
  }

  local twrMun is 0.
  if ship:maxthrust > 0 {
    set twrMun to (ship:maxthrust / ship:mass) / gMun.
  } else {
    logChatter("CapCom", "ERROR: No thrust available! Aborting.").
    wait 5.
    reboot.
  }

  logChatter("CapCom", "Local TWR: " + round(twrMun, 2)).
  if twrMun < 1.5 {
    logChatter("CapCom", "WARNING: Low TWR profile detected.").
    wait 2.
  }
  wait 1.

  // -------------------------------------------
  // STEP 1: Vertical ascent to clear terrain
  // -------------------------------------------
  logChatter("CapCom", "Step 1: Commencing liftoff burn.").
  hudMsg("LIFTOFF").
  playLunarLaunchScene(45).

  sas off. rcs on.
  lock throttle to 1.
  lock steering to up.
  wait 1.5.
  wait until vAng(ship:facing:vector, up:vector) < 5.

  // Rise straight up until we have clearance
  until alt:radar > 200 {
    updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
    wait 0.
  }

  logChatter("Crew", "Clearance height achieved. Starting pitchover.").
  wait 0.5.

  // -------------------------------------------
  // STEP 2: Pitch over and burn to raise apoapsis
  // -------------------------------------------
  logChatter("CapCom", "Step 2: Pitching over to raise Apoapsis.").
  lock steering to heading(90, 70).
  wait 3.

  SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
  SET KUNIVERSE:TIMEWARP:RATE TO 2.
  local lastChatTime is time:seconds.
  until ship:orbit:apoapsis >= targetOrbit {
    local pitchAngle is 90 - vAng(up:vector, srfPrograde:vector).
    lock steering to srfPrograde.

    updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
    
    if time:seconds - lastChatTime > 15 {
      randomChatter("ascent").
      set lastChatTime to time:seconds.
    }
    wait 0.
  }

  lock throttle to 0.
  SET KUNIVERSE:TIMEWARP:RATE TO 1.
  SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
  logChatter("Crew", "Apoapsis target achieved. Engine cutoff.").
  hudMsg("APOAPSIS REACHED").
  wait 1.

  // -------------------------------------------
  // STEP 3: Coast to apoapsis
  // -------------------------------------------
  logChatter("CapCom", "Step 3: Coasting to Apoapsis circularization point.").
  
  if ship:altitude < 5000 {
    logChatter("CapCom", "Coasting to safe warp altitude (5000m)...").
    wait until ship:altitude >= 5000.
  }

  local warpMargin is max(30, min(70, ship:mass / 5 + 10)).
  if ETA:apoapsis > warpMargin + 30 {
    logChatter("CapCom", "Warping to Apoapsis...").
    warpto(time:seconds + ETA:apoapsis - warpMargin).
    wait until kuniverse:timewarp:rate = 1.
  }

  // -------------------------------------------
  // STEP 4: Circularize at apoapsis
  // -------------------------------------------
  initScreen("circularization").
  logChatter("CapCom", "Step 4: Preparing circularization burn.").
  wait 1.

  local r_ap is ship:orbit:apoapsis + body:radius.
  local v_ap is sqrt(body:mu * (2/r_ap - 1/ship:orbit:semimajoraxis)).
  local v_circ is sqrt(body:mu / r_ap).
  local dv_circ is v_circ - v_ap.

  logChatter("CapCom", "Burn dV: " + round(dv_circ, 1) + " m/s").

  local circNode is node(time:seconds + ETA:apoapsis, 0, 0, dv_circ).
  add circNode.
  wait 0.1.

  hudMsg("CIRCULARIZING").
  exeMnv().
  wait 1.

  // -------------------------------------------
  // STEP 5: Verify orbit and clean up
  // -------------------------------------------
  if ship:orbit:periapsis < targetOrbit * 0.8 {
    logChatter("CapCom", "Periapsis low. Performing minor correction.").
    wait 1.
    goToFrom(targetOrbit, "AP").
    exeMnv().
    wait 1.
  }

  unlock steering.
  unlock throttle.
  set ship:control:pilotMainThrottle to 0.
  rcs off.
  sas on.

  initScreen("orbit_locked").
  logChatter("CapCom", "Mission summary: Mun orbit established.").
  logChatter("Crew", "Orbit stabilized. Ready for return to Kerbin.").
  hudMsg("ORBIT STABILIZED").
  playOrbitScene().
  if not (defined automatedMission) {
    until false {
      updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
      wait 1.0.
    }
  } else {
    wait 5.
  }
}
