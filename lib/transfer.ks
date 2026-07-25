runOncePath("0:/lib/mnv.ks").

global function transferToBody {
  parameter targetBody, doWarp is false.
  set target to targetBody.

  local targetAngle is 180 - computeTargetAngle(target).
  local phaseAngle is computePhaseAngle(target).
  
  local travelAngle is phaseAngle - targetAngle.
  until travelAngle >= 0 { set travelAngle to travelAngle + 360. }
  
  local synodicPeriod is (ship:orbit:period * target:orbit:period) / (target:orbit:period - ship:orbit:period).
  local deltaTime is travelAngle * synodicPeriod / 360.

  if deltaTime > 45 {
    logChatter("CapCom", "Warping to transfer window...").
    set MAPVIEW to true.
    warpto(time:seconds + deltaTime - 30).
    wait until kuniverse:timewarp:rate = 1.
    set MAPVIEW to false.
    wait 0.5. // Allow physics to settle
    
    // Recalculate precisely after warp to handle any eccentricity or drift
    set phaseAngle to computePhaseAngle(target).
    set travelAngle to phaseAngle - targetAngle.
    until travelAngle >= 0 { set travelAngle to travelAngle + 360. }
    set synodicPeriod to (ship:orbit:period * target:orbit:period) / (target:orbit:period - ship:orbit:period).
    set deltaTime to travelAngle * synodicPeriod / 360.
  }

  clearScreen.
  local deltaV is hTrans(ship:altitude, targetBody:orbit:apoapsis - targetBody:radius - 30000).
  add node(time:seconds + deltaTime, 0, 0, deltaV).
  
  exeMnv().

  if ship:orbit:hasnextpatch and orbit:nextpatch:periapsis < 2000 {
    lock steering to retrograde.
    set canStage to false.
    local lim is max(0.5, abs(orbit:nextpatch:periapsis/50_000)).
    limitThrust(lim).
    wait 0.
    wait until vAng(ship:facing:vector, retrograde:vector) < 1.
    until orbit:nextpatch:periapsis > 10000 {
      lock throttle to 1.
    }
  }
  lock throttle to 0.
  limitThrust(100).
  set canStage to true.

  wait 2.

  if doWarp {
    set MAPVIEW to true.
    warpto(time:seconds + ETA:transition + 120).
    wait until kuniverse:timewarp:rate = 1.
    set MAPVIEW to false.
  }
}

function computeTargetAngle {
  parameter targetBody.
  local nextPe is ship:apoapsis.
  local semiMajorAxis is (body:radius + nextPe + body:radius + targetBody:orbit:apoapsis) / 2.
  local semiPeriod is constant:pi * sqrt(semiMajorAxis^3 / body:mu).
  local targetBodyPeriod is targetBody:orbit:period.
  return semiPeriod * 360 / targetBodyPeriod.  
}

function computePhaseAngle {
  parameter targetBody.
  
  local shipAngle is vernalAngle().
  local targetAngle is vernalAngle(targetBody).

  local diffAngle is targetAngle - shipAngle.
  return diffAngle - 360 * floor(diffAngle/360).
}

function vernalAngle {
  parameter Obj is ship.
  local angle is Obj:orbit:lan + Obj:orbit:argumentofperiapsis + Obj:orbit:trueanomaly.
  return angle - 360*floor(angle / 360).
}