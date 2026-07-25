runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/transfer.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

if ship:status = "PRELAUNCH" or ship:status = "FLYING" or ship:orbit:periapsis < 70000 {
  clearScreen.
  print "=======================================".
  print "          MUN ORBIT MISSION ERROR      ".
  print "=======================================".
  print "Error: Vessel must be in a stable orbit".
  print "around Kerbin (Periapsis > 70km) to".
  print "initiate the Mun transfer script.".
  print "---------------------------------------".
  print "Please run your launch script first.".
  print "=======================================".
  wait 5.
} else {
  runOncePath("0:/lib/hud.ks").
  initScreen("mun_transfer").
  logChatter("CapCom", "Trans-Munar injection sequence initiated.").
  hudMsg("MUN MISSION INITIATED").
  logChatter("Crew", "Deploying solar panels and antenna systems...").
  panels on.
  if antenna:length > 0 {
    deployAntenna().
  }
  wait 1.5.

  // 1. Establish target and plan Hohmann transfer
  set target to BODY("Mun").
  logChatter("CapCom", "Calculating Hohmann transfer trajectory...").
  wait 1.
  set MAPVIEW to true. // Switch to Map View for the planning
  transferToBody(BODY("Mun"), false). // Do NOT warp immediately
  wait 1.5.

  // 2. Perform Mid-Course correction in Kerbin SOI (extremely cheap and precise)
  logChatter("CapCom", "Fine-tuning Mun periapsis mid-course...").
  setNewPeriapsis(55000, 120, true).
  exeMnv().
  wait 1.5.

  // 3. Warp to Mun SOI transition
  logChatter("CapCom", "Warping to Mun SOI transition.").
  set MAPVIEW to true.
  if ETA:transition > 30 {
    warpto(time:seconds + ETA:transition - 15).
    wait until kuniverse:timewarp:rate = 1.
  }
  wait until ship:body:name = "Mun".
  set MAPVIEW to false.
  
  initScreen("mun_encounter").
  logChatter("CapCom", "Signal acquired. Entered Mun sphere of influence.").
  hudMsg("ENTERED MUN SOI").
  wait 2.

  // 4. Calculate capture burn
  logChatter("CapCom", "Calculating Mun orbit capture burn...").
  local r_pe is ship:orbit:periapsis + body:radius.
  local v_pe is sqrt(body:mu * (2/r_pe - 1/ship:orbit:semimajoraxis)).
  local v_circ is sqrt(body:mu / r_pe).
  local dv is v_circ - v_pe.

  local captureNode is node(time:seconds + ETA:periapsis, 0, 0, dv).
  add captureNode.
  wait 0.1.

  logChatter("CapCom", "Executing Mun capture burn at periapsis.").
  hudMsg("MUN CAPTURE BURN ACTIVE").
  exeMnv().

  // 6. Mission summary
  initScreen("mun_orbit").
  logChatter("CapCom", "Mission summary: Mun orbit stabilized.").
  logChatter("Crew", "We are safely in Mun orbit. Beautiful view out here.").
  hudMsg("MUN ORBIT ESTABLISHED").
  playOrbitScene().
  
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
