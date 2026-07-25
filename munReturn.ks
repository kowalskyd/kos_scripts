runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

local targetKerbinPe is 30000.  // Safe reentry periapsis

if ship:body:name <> "Mun" {
  clearScreen.
  print "=======================================".
  print "      MUN RETURN SCRIPT ERROR          ".
  print "=======================================".
  print "Error: Vessel is not orbiting the Mun.".
  print "Currently at: " + ship:body:name.
  print "=======================================".
  wait 5.
} else if ship:status = "LANDED" or ship:status = "PRELAUNCH" {
  clearScreen.
  print "=======================================".
  print "      MUN RETURN SCRIPT ERROR          ".
  print "=======================================".
  print "Error: Vessel is still on the surface.".
  print "Run munLaunch first.".
  print "=======================================".
  wait 5.
} else {
  runOncePath("0:/lib/hud.ks").
  initScreen("mun_return").
  logChatter("CapCom", "Trans-Kerbin return sequence initiated.").
  hudMsg("RETURN SEQUENCE ACTIVE").

  sas off.
  rcs on.
  lock steering to prograde.
  wait 2.
  wait until vAng(ship:facing:vector, prograde:vector) < 5.
  logChatter("Crew", "Spacecraft stabilized on prograde escape vector.").

  // -------------------------------------------
  // STEP 1: Calculate ejection burn
  // -------------------------------------------
  logChatter("CapCom", "Step 1: Calculating optimal ejection window...").
  wait 1.

  // Calculate escape velocity from current Mun orbit
  local r_orbit is ship:orbit:semimajoraxis.
  local v_current is ship:velocity:orbit:mag.
  local v_escape is sqrt(2 * body:mu / r_orbit).
  local dv_escape is v_escape - v_current + 50.

  local bestTime is time:seconds + ETA:periapsis.
  local bestScore is 999999999.
  local bestDv is dv_escape.
  local foundValidPatch is false.
  local period is ship:orbit:period.
  local steps is 24.
  local dt is period / steps.

  local i is 0.
  until i >= steps {
    local t is time:seconds + 60 + i * dt.
    for testDv in list(dv_escape - 25, dv_escape, dv_escape + 25, dv_escape + 50) {
      local testNode is node(t, 0, 0, testDv).
      add testNode.
      wait 0.
      
      if testNode:orbit:hasnextpatch {
        local nextBody is testNode:orbit:nextpatch:body:name.
        if nextBody = "Kerbin" {
          local pe is testNode:orbit:nextpatch:periapsis.
          local score is abs(pe - targetKerbinPe).
          if score < bestScore {
            set bestScore to score.
            set bestTime to t.
            set bestDv to testDv.
            set foundValidPatch to true.
          }
        }
      }
      remove testNode.
      wait 0.
    }
    set i to i + 1.
  }

  // Fallback to simple vector search if conics prediction found nothing
  if not foundValidPatch {
    logChatter("CapCom", "WARNING: Conics prediction failed. Using vector fallback.").
    set bestTime to time:seconds + ETA:periapsis.
    local bestVectorScore is 99999.
    set i to 0.
    until i >= steps {
      local t is time:seconds + i * dt.
      local shipVel is velocityAt(ship, t):orbit.
      local munVel is body:velocity:orbit.
      local kerbinVel is shipVel + munVel.
      local progDir is shipVel:normalized.
      local kerbinVelAfterBurn is kerbinVel + progDir * dv_escape.
      local score is kerbinVelAfterBurn:mag.
      if score < bestVectorScore {
        set bestVectorScore to score.
        set bestTime to t.
      }
      set i to i + 1.
    }
    set bestDv to dv_escape.
  }

  local timeToNode is bestTime - time:seconds.
  if timeToNode < 30 {
    set bestTime to bestTime + period.
    set timeToNode to bestTime - time:seconds.
  }

  logChatter("CapCom", "Ejection burn calculated in " + round(timeToNode) + " s.").
  wait 1.

  // -------------------------------------------
  // STEP 2: Create and execute ejection burn
  // -------------------------------------------
  initScreen("return_ejection").
  logChatter("CapCom", "Step 2: Commencing ejection burn refinement...").
  wait 1.

  local ejectionNode is node(bestTime, 0, 0, bestDv).
  add ejectionNode.
  wait 0.

  if ejectionNode:orbit:hasnextpatch {
    local bestDv is dv_escape.
    local bestPeDiff is abs(ejectionNode:orbit:nextpatch:periapsis - targetKerbinPe).

    local searchDv is dv_escape - 30.
    until searchDv > dv_escape + 80 {
      set ejectionNode:prograde to searchDv.
      wait 0.
      if ejectionNode:orbit:hasnextpatch {
        local peDiff is abs(ejectionNode:orbit:nextpatch:periapsis - targetKerbinPe).
        if peDiff < bestPeDiff {
          set bestPeDiff to peDiff.
          set bestDv to searchDv.
        }
      }
      set searchDv to searchDv + 1.
    }
    set ejectionNode:prograde to bestDv.
    wait 0.

    set searchDv to bestDv - 2.
    until searchDv > bestDv + 2 {
      set ejectionNode:prograde to searchDv.
      wait 0.
      if ejectionNode:orbit:hasnextpatch {
        local peDiff is abs(ejectionNode:orbit:nextpatch:periapsis - targetKerbinPe).
        if peDiff < bestPeDiff {
          set bestPeDiff to peDiff.
          set bestDv to searchDv.
        }
      }
      set searchDv to searchDv + 0.1.
    }
    set ejectionNode:prograde to bestDv.
    wait 0.
  }

  logChatter("CapCom", "Ejection burn dV: " + round(ejectionNode:deltav:mag, 1) + " m/s").
  hudMsg("EJECTION BURN").
  exeMnv().
  wait 1.

  rcs on.
  sas off.
  lock steering to prograde.
  wait 2.
  wait until vAng(ship:facing:vector, prograde:vector) < 5.
  logChatter("Crew", "Stabilized on prograde escape trajectory.").

  // -------------------------------------------
  // STEP 3: Mid-course correction (if needed)
  // -------------------------------------------
  if ship:body:name = "Mun" {
    logChatter("CapCom", "Step 3: Coasting out of Mun's sphere of influence...").
    lock steering to prograde.
    set MAPVIEW to true.
    warpto(time:seconds + ETA:transition + 30).
    wait until kuniverse:timewarp:rate = 1.
    wait until ship:body:name = "Kerbin".
    set MAPVIEW to false.
    
    initScreen("kerbin_soi").
    logChatter("CapCom", "Entered Kerbin's Sphere of Influence.").
    hudMsg("ENTERED KERBIN SOI").
    wait 2.
  }

  local kerbinPe is ship:orbit:periapsis.
  logChatter("CapCom", "Checking trajectory. Current Kerbin Pe: " + round(kerbinPe / 1000, 1) + " km").

  if kerbinPe > 50000 or kerbinPe < 20000 {
    logChatter("CapCom", "Correcting reentry periapsis to 30km...").
    wait 1.
    setNewPeriapsis(targetKerbinPe, 120, false).
    wait 1.
    exeMnv().
    wait 1.
    lock steering to prograde.
    wait 2.
  } else {
    logChatter("CapCom", "Reentry trajectory is nominal. Skipping correction.").
  }

  lock steering to prograde.

  // -------------------------------------------
  // STEP 4: Warp to Kerbin atmosphere
  // -------------------------------------------
  initScreen("kerbin_coast").
  logChatter("CapCom", "Step 4: Warping to atmospheric interface.").
  
  lock steering to prograde.
  if ETA:periapsis > 200 {
    set MAPVIEW to true.
    warpto(time:seconds + ETA:periapsis - 100).
    wait until kuniverse:timewarp:rate = 1.
    set MAPVIEW to false.
  }

  logChatter("CapCom", "Approaching atmosphere. Waiting altitude 100k.").
  wait until ship:altitude <= 100000.

  // -------------------------------------------
  // STEP 5: Reentry preparation (100k)
  // -------------------------------------------
  initScreen("reentry_prep").
  logChatter("CapCom", "Step 5: Commencing reentry preparation sequence.").
  hudMsg("REENTRY PREPARATION").
  playDescendScene().

  rcs on.
  lock steering to retrograde.
  logChatter("Crew", "Aligning space capsule retrograde for service module separation...").
  wait until vAng(ship:facing:vector, retrograde:vector) < 5.

  if ship:maxthrust > 0 {
    logChatter("CapCom", "Dumping remaining fuel retrograde...").
    lock throttle to 1.0.
    local doneBurning is false.
    until doneBurning {
      if ship:maxthrust = 0 or ship:availablethrust = 0 {
        set doneBurning to true.
      }
      if ship:altitude <= 75000 {
        logChatter("KAL-9000", "Altitude threshold reached! Cutting throttle.").
        set doneBurning to true.
      }
      local engines is list().
      list engines in engines.
      for eng in engines {
        if eng:flameout {
          set doneBurning to true.
        }
      }
      updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
      wait 0.1.
    }
    lock throttle to 0.
  }

  logChatter("KAL-9000", "Staging service module. Separating capsule...").
  hudMsg("SERVICE MODULE DETACHED").
  stage.
  wait 1.5.

  lock steering to srfretrograde.
  wait 2.
  wait until vAng(ship:facing:vector, srfretrograde:vector) < 10.
  logChatter("Crew", "Holding surface retrograde for atmospheric interface.").

  wait until ship:altitude < 70000.
  logChatter("CapCom", "Atmospheric entry confirmed. Communications black-out imminent.").
  hudMsg("ATMOSPHERIC ENTRY", rgb(1,0,0)).
  playReentryScene().

  // -------------------------------------------
  // STEP 6: Descent and parachute deployment
  // -------------------------------------------
  local lastChatTime is time:seconds.
  until ship:altitude < 30000 {
    lock steering to srfretrograde.
    updateTelemetry(ship:velocity:surface:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
    if time:seconds - lastChatTime > 15 {
      randomChatter("return").
      set lastChatTime to time:seconds.
    }
    wait 0.5.
  }

  
  stage.
  playChuteScene().
  wait 0.5.
  chutes on.

  local heatshieldJettisoned is false.
  
  until ship:velocity:surface:mag < 200 or ship:altitude < 5000 {
    lock steering to srfretrograde.
    updateTelemetry(ship:velocity:surface:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
    if not heatshieldJettisoned and ship:altitude < 10000 {
      logChatter("KAL-9000", "Jettisoning heat shield...").
      hudMsg("HEAT SHIELD JETTISONED").
      for p in ship:parts {
        if p:name:contains("HeatShield") {
          for mName in p:modules {
            local m is p:getmodule(mName).
            for ev in m:allEventNames {
              if ev:tolower():contains("jettison") or ev:tolower():contains("decouple") {
                m:doevent(ev).
              }
            }
          }
        }
      }
      set heatshieldJettisoned to true.
    }
    wait 0.5.
  }

  if not heatshieldJettisoned {
    wait until ship:altitude < 10000.
    logChatter("KAL-9000", "Jettisoning heat shield...").
    hudMsg("HEAT SHIELD JETTISONED").
    for p in ship:parts {
      if p:name:contains("HeatShield") {
        for mName in p:modules {
          local m is p:getmodule(mName).
          for ev in m:allEventNames {
            if ev:tolower():contains("jettison") or ev:tolower():contains("decouple") {
              m:doevent(ev).
            }
          }
        }
      }
    }
    set heatshieldJettisoned to true.
  }
  unlock steering.
  unlock throttle.
  set ship:control:pilotMainThrottle to 0.
  sas on.

  logChatter("CapCom", "Waiting for capsule touchdown/splashdown.").

  wait until ship:status = "LANDED" or ship:status = "SPLASHED".

  initScreen("welcome_home").
  logChatter("CapCom", "Welcome home, Kerbonauts! Mission completed!").
  hudMsg("WELCOME HOME!", rgb(0,1,0)).
  stopCameraScene().
  if not (defined automatedMission) {
    until false {
      updateTelemetry(ship:velocity:surface:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
      wait 1.0.
    }
  } else {
    wait 5.
  }
}
