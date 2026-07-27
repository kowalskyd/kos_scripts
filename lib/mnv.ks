runOncePath("0:/lib/misc.ks").
runOncePath("0:/lib/camera_director.ks").

//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// COMPUTE VELOCITY AT A GIVEN ALTITUDE OF AN ORBIT
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global function computeVelocity {
  parameter per, apo, shipAlt.
  local bMu is ship:body:mu.
  local bRadius is ship:body:radius.
  local SA is shipAlt + bRadius.
  local RP is bRadius + per.
  local RA is bRadius + apo.
  local SMA is (RP + RA) / 2.

  return sqrt(bMu * (2 / SA - 1 / SMA)).
}

//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// HOHMANN TRANSFER
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global function hTrans {
  parameter shipAlt, targetAlt.
  local initialVel is 0.
  local finalVel is 0.
  local deltaVneeded is 0.

  set initialVel to computeVelocity(ship:orbit:periapsis, ship:orbit:apoapsis, shipAlt).
  if shipAlt < targetAlt {
    set finalVel to computeVelocity(shipAlt, targetAlt, shipAlt).
  }
  else {
    set finalVel to computeVelocity(targetAlt, shipAlt, shipAlt).
  }

  set deltaVneeded to finalVel - initialVel.

  print "---".
  print "initial vel: " + round(initialVel, 2) + " m/s ".
  print "  final vel: " + round(finalVel, 2) + " m/s ".
  print "    delta-v: " + round(deltaVneeded, 2) + " m/s ".
  print "---".

  return deltaVneeded.
}

//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// GO TO FROM AP or PE
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global function goToFrom {
  parameter targetAlt, fromAlt is "AP".
  local newDV is 0.
  local newNode is node(0,0,0,0).

  if fromAlt = "AP" {
    set newDV to hTrans(ship:orbit:apoapsis, targetAlt).
    set newNode to node(time:seconds + ETA:apoapsis, 0, 0, newDV).
  }
  else {
    set newDV to hTrans(ship:orbit:periapsis, targetAlt).
    set newNode to node(time:seconds + ETA:periapsis, 0, 0, newDV).
  }
  add newNode.
}

//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// EXECUTE MANEUVER
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global function exeMnv { 
  parameter deltaTime is -1. 
  if hasNode {
    set myNode to nextNode.
    set tset to 0.
    lock throttle to tset.

    if ship:maxthrust = 0 {
      for eng in ship:engines {
        if not eng:ignition { eng:activate(). }
      }
      wait 0.
    }
    local function applyGForceLimit {
      if not (defined mnvMaxG) {
        global mnvMaxG is 3.0.
      }
      local maxAccLimit is mnvMaxG * 9.80665.
      local targetThrust is maxAccLimit * ship:mass.
      local totalPossible is 0.
      for eng in ship:engines {
        if eng:ignition {
          set totalPossible to totalPossible + eng:possiblethrust.
        }
      }
      if totalPossible > 0 {
        local limitPercent is (targetThrust / totalPossible) * 100.
        set limitPercent to max(5, min(100, limitPercent)).
        for eng in ship:engines {
          if eng:ignition {
            set eng:thrustlimit to limitPercent.
          }
        }
      }
    }

    applyGForceLimit().

    set max_acc to max(0.001, ship:maxthrust/ship:mass).
    set burn_duration to myNode:deltav:mag/max_acc.

    local wasMap is MAPVIEW.
    local leadTime is max(20, burn_duration / 2 + 24).
    if myNode:ETA > leadTime + 5 {
      set MAPVIEW to true.
      kuniverse:timewarp:warpto(time:seconds + myNode:ETA - leadTime).
      wait until kuniverse:timewarp:issettled or kuniverse:timewarp:rate = 1.
      if not wasMap { set MAPVIEW to false. }
    }

    lock steering to myNode:deltav.
    if defined hudActive {
      logChatter("CapCom", "Aligning spacecraft with maneuver node...").
    }
    local alignTimeout is time:seconds + 12.
    until vAng(ship:facing:vector, myNode:deltav) < 2.0 or time:seconds > alignTimeout or myNode:ETA <= (burn_duration / 2 + 1) {
      wait 0.1.
    }
    global mnvSteer is myNode:deltav.
    lock steering to mnvSteer.

    local burnSceneDur is max(5, myNode:eta - (burn_duration/2) + burn_duration).
    playBurnScene(burnSceneDur).

    until myNode:eta <= (burn_duration/2) {
      if defined hudActive {
        updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
      } else {
        print "Maneuver in: " + round(myNode:ETA - burn_duration/2, 2) + " s      " at (0,6).
      }
      wait 0.1.
    }

    local function checkPeReached {
      if not (defined mnvTargetPe) { return false. }
      local livePe is -1.
      if (defined mnvDoNextPatch) and mnvDoNextPatch and ship:orbit:hasnextpatch {
        set livePe to ship:orbit:nextpatch:periapsis.
      } else if (defined mnvDoNextPatch) and not mnvDoNextPatch {
        set livePe to ship:orbit:periapsis.
      }
      if livePe = -1 { return false. }

      local peErrorRatio is abs(livePe - mnvTargetPe) / mnvTargetPe.
      local reached is false.
      if peErrorRatio <= 0.10 {
        set reached to true.
      } else if (defined mnvInitialPe) and mnvInitialPe > mnvTargetPe and livePe <= mnvTargetPe {
        set reached to true.
      } else if (defined mnvInitialPe) and mnvInitialPe < mnvTargetPe and livePe >= mnvTargetPe {
        set reached to true.
      }

      if reached {
        if defined hudActive {
          logChatter("KAL-9000", "Target Periapsis reached (" + round(livePe/1000, 1) + " km). Terminating burn.").
        } else {
          print "Target Periapsis reached (" + round(livePe/1000, 1) + " km). Terminating burn.".
        }
        return true.
      }
      return false.
    }

    // PRE-BURN AUTO-STAGE CHECK: For small/correction burns (< 100 m/s), stage first if current stage fuel is low
    if myNode:deltav:mag < 100 {
      local stageDV is 999999.
      if ship:hasSuffix("stagedeltav") {
        set stageDV to ship:stagedeltav(ship:stagenum):current.
      }
      if stageDV < (myNode:deltav:mag + 30) or ship:maxthrust = 0 {
        if defined hudActive {
          logChatter("KAL-9000", "Pre-burn check: stage fuel low for small burn. Auto-staging...").
        } else {
          print "Pre-burn check: stage fuel low. Auto-staging...".
        }
        set tset to 0.
        stage.
        wait 1.5.
        applyGForceLimit().
      }
    }

    set done to False.
    //initial deltav
    set dv0 to myNode:deltav.
    local thrustLimited is false.
    until done
    {
      if vdot(dv0, myNode:deltav) < 0.0 or myNode:deltav:mag < 0.02 or checkPeReached()
      {
          if defined hudActive {
              logChatter("KAL-9000", "Burn complete. Remaining dV: " + round(myNode:deltav:mag, 3) + " m/s").
          } else {
              print "End burn, remain dv " + round(myNode:deltav:mag, 3) + " m/s".
          }
          set tset to 0.
          lock throttle to 0.
          set done to True.
          break.
      }

      // STAGING CHECK: If an engine has flamed out, stage to the next one
      local needsStage is false.
      for eng in ship:engines {
        if eng:flameout {
          set needsStage to true.
          break.
        }
      }
      if needsStage or ship:maxthrust = 0 {
        if defined hudActive {
          logChatter("KAL-9000", "Stage burnout during maneuver! Staging...").
        } else {
          print "Stage burnout! Staging...".
        }
        set tset to 0.
        wait 0.
        stage.
        wait 1.0.
        set thrustLimited to false. // Reset flag to recalculate for new stage engines

        // Update steering target to true node vector post-staging
        set mnvSteer to myNode:deltav.
        lock steering to mnvSteer.

        // Wait until vessel re-aligns facing vector with maneuver node after stage separation
        local stageAlignTimeout is time:seconds + 10.
        until vAng(ship:facing:vector, myNode:deltav) < 1.5 or time:seconds > stageAlignTimeout {
          wait 0.1.
        }

        if myNode:deltav:mag > 0.3 {
          applyGForceLimit().
        } else {
          local targetAcc is max(0.1, min(2.0, myNode:deltav:mag / 1.5)).
          local targetThrust is targetAcc * ship:mass.
          local totalPossible is 0.
          for eng in ship:engines {
            if eng:ignition {
              set totalPossible to totalPossible + eng:possiblethrust.
            }
          }
          if totalPossible > 0 {
            local limitPercent is (targetThrust / totalPossible) * 100.
            set limitPercent to max(5, min(100, limitPercent)).
            for eng in ship:engines {
              if eng:ignition {
                set eng:thrustlimit to limitPercent.
              }
            }
            set thrustLimited to true.
          }
        }
        // Re-check thrust after staging
        if ship:maxthrust = 0 {
          if defined hudActive {
            logChatter("KAL-9000", "WARNING: No thrust after staging!").
          } else {
            print "WARNING: No thrust after staging!".
          }
        }

        if vdot(dv0, myNode:deltav) < 0.0 or myNode:deltav:mag < 0.02 or checkPeReached() {
          set tset to 0.
          lock throttle to 0.
          set done to True.
          break.
        }
      }

      // Freeze steering and limit thrust during final portion of the burn to prevent flips and wobble
      if myNode:deltav:mag > 0.6 {
        set mnvSteer to myNode:deltav.
      } else {
        if not thrustLimited {
          // Limit acceleration based on remaining delta-V to ensure the burn takes at least 1.5s, capped at 1.0 m/s^2
          local targetAcc is max(0.1, min(1.0, myNode:deltav:mag / 1.5)).
          local targetThrust is targetAcc * ship:mass.
          local totalPossible is 0.
          for eng in ship:engines {
            if eng:ignition {
              set totalPossible to totalPossible + eng:possiblethrust.
            }
          }
          if totalPossible > 0 {
            local limitPercent is (targetThrust / totalPossible) * 100.
            set limitPercent to max(5, min(100, limitPercent)).
            for eng in ship:engines {
              if eng:ignition {
                set eng:thrustlimit to limitPercent.
              }
            }
            set thrustLimited to true.
          }
        }
      }

      set max_acc to max(0.001, ship:maxthrust/ship:mass).
      // Scale throttle down smoothly in the last 1.5 seconds of the burn, clamped to min 5% or 15% depending on TWR
      set tset to min(1.0, myNode:deltav:mag / max(0.01, max_acc * 1.5)).
      local minThrottle is 0.15.
      if max_acc > 5.0 { set minThrottle to 0.05. }
      set tset to max(minThrottle, tset).

      if defined hudActive {
        updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
      }
      wait 0.
    }

    // Restore thrust limits of all engines to 100%
    for eng in ship:engines {
      set eng:thrustlimit to 100.
    }

    wait 0.
    remove myNode.
  }
  else {
    print("No existing maneuver").
  }

  unlock steering.
  if defined mnvSteer { unset mnvSteer. }
  if defined mnvTargetPe { unset mnvTargetPe. }
  if defined mnvTargetPeMargin { unset mnvTargetPeMargin. }
  if defined mnvDoNextPatch { unset mnvDoNextPatch. }
  if defined mnvInitialPe { unset mnvInitialPe. }
  unlock throttle.
  stopCameraScene().
  wait 0.
  set ship:control:pilotMainThrottle to 0.
}

//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// CHANGE ENGINE'S THRUST LIMIT
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global function limitThrust {
  parameter perc.
  for eng in ship:engines {
    if eng:ignition {set eng:thrustLimit to perc.}
  }
  print ("Thrust power at ") + round(perc,1) + (" %.            ") at (0,25).
}


//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// CHANGE THE PERIAPSIS OF THE NEXT ORBIT AFTER A BURN
// (AND POSSIBLY AFTER A CHANGE OF SOI)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

function setNewPeriapsis {
  parameter wantedPeriapsis, newTime, doNextPatch is true, marginValue is 5000, deltaChange is 0.1.

  local prevMap is MAPVIEW.
  set MAPVIEW to false.
  if defined playOrbitScene {
    playOrbitScene(60).
  }

  local currentPe is -1.
  if doNextPatch {
    if ship:orbit:hasnextpatch {
      set currentPe to ship:orbit:nextpatch:periapsis.
    }
  } else {
    set currentPe to ship:orbit:periapsis.
  }

  if currentPe <> -1 {
    local peErrorRatio is abs(currentPe - wantedPeriapsis) / wantedPeriapsis.
    if peErrorRatio <= 0.10 {
      if defined hudActive {
        local msg is "Current Pe " + round(currentPe/1000, 1) + "km is within 10% of target (" + round(wantedPeriapsis/1000, 1) + "km). Skipping correction.".
        logChatter("CapCom", msg).
      } else {
        print "Periapsis within 10% of target. Skipping correction.".
      }
      return.
    }
  }

  if not (defined hudActive) {
    clearScreen.
  }
  local correctNode is node(time:seconds + newTime, 0, 0, 0).
  add correctNode.

  // Safe periapsis reader that won't crash if next patch disappears or targets wrong body
  local function getPe {
    if doNextPatch {
      if correctNode:orbit:hasnextpatch {
        local np is correctNode:orbit:nextpatch.
        if hasTarget and target:istype("Body") {
          if np:body <> target { return -1. }
        }
        return np:periapsis.
      } else {
        return -1. // Signal: no encounter exists
      }
    } else {
      return correctNode:orbit:periapsis.
    }
  }

  local newValue is list().
  local oldPeriapsis is getPe().

  // If doNextPatch but no encounter exists at all, abort early
  if doNextPatch and oldPeriapsis = -1 {
    if defined hudActive {
      logChatter("KAL-9000", "No SOI encounter found. Skipping periapsis tuning.").
    } else {
      print "No SOI encounter found. Skipping periapsis tuning.".
    }
    remove correctNode.
    wait 0.5.
    return.
  }

  // Use a function instead of lock to safely handle missing patches
  local function getError {
    local pe is getPe().
    if pe = -1 { return 9999999. } // Huge error if encounter lost — steers solver back
    return abs(wantedPeriapsis - pe).
  }

  local maxStep is 3.0.
  local stepSize is deltaChange.

  // Dynamically scale step size and max step for distant targets like Minmus (SMA > 20,000 km)
  if hasTarget and target:istype("Body") and target:orbit:semimajoraxis > 20000000 {
    set stepSize to min(stepSize, 0.1).
    set maxStep to 0.5.
  }

  local iterations is 0.
  local maxIterations is 2000.

  until abs(oldPeriapsis - wantedPeriapsis) <= marginValue or iterations >= maxIterations or stepSize < 0.0001 {
    local currentError is getError().
    local errors is list().

    changeRadialOut(correctNode, stepSize).
    errors:add(getError()). changeRadialIn(correctNode, stepSize).
    changeRadialIn(correctNode, stepSize).
    errors:add(getError()). changeRadialOut(correctNode, stepSize).

    changeNormal(correctNode, stepSize).
    errors:add(getError()). changeAntiNormal(correctNode, stepSize).
    changeAntiNormal(correctNode, stepSize).
    errors:add(getError()). changeNormal(correctNode, stepSize).

    changePrograde(correctNode, stepSize).
    errors:add(getError()). changeRetrograde(correctNode, stepSize).
    changeRetrograde(correctNode, stepSize).
    errors:add(getError()). changePrograde(correctNode, stepSize).

    local bestError is minOf(errors).
    local bestIndex is errors:indexOf(bestError).

    if bestError < currentError {
      if bestIndex = 0 {changeRadialOut(correctNode, stepSize).}
      else if bestIndex = 1 {changeRadialIn(correctNode, stepSize).}
      else if bestIndex = 2 {changeNormal(correctNode, stepSize).}
      else if bestIndex = 3 {changeAntiNormal(correctNode, stepSize).}
      else if bestIndex = 4 {changePrograde(correctNode, stepSize).}
      else if bestIndex = 5 {changeRetrograde(correctNode, stepSize).}
      
      set oldPeriapsis to getPe().
      set stepSize to min(maxStep, stepSize * 1.2).
    } else {
      set stepSize to stepSize / 2.
    }

    // If encounter was lost during solving, bail out
    if doNextPatch and oldPeriapsis = -1 {
      if defined hudActive {
        logChatter("KAL-9000", "SOI encounter lost during solve. Using current node.").
      } else {
        print "SOI encounter lost. Using current node.".
      }
      break.
    }
    set iterations to iterations + 1.
    wait 0.
  }
  if iterations >= maxIterations {
    if defined hudActive {
      logChatter("KAL-9000", "Periapsis solver: best achievable Pe " + round(oldPeriapsis) + "m (target " + round(wantedPeriapsis) + "m). Proceeding.").
    } else {
      print "Solver limit reached. Pe: " + round(oldPeriapsis) + "m".
    }
  }
  global mnvTargetPe is wantedPeriapsis.
  global mnvTargetPeMargin is marginValue.
  global mnvDoNextPatch is doNextPatch.
  global mnvInitialPe is currentPe.

  set MAPVIEW to prevMap.
  wait 0.5.
}


//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// CHANGE THE INCLINATION OF THE NEXT ORBIT AFTER A BURN
// (AND POSSIBLY AFTER A CHANGE OF SOI)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

function setNewInclination {
  parameter wantedInclination, newTime, doNextPatch is true, marginValue is 0.05, deltaChange is 0.1.
  
  local prevMap is MAPVIEW.
  set MAPVIEW to false.
  if defined playOrbitScene {
    playOrbitScene(60).
  }
  clearScreen.
  local correctNode is node(time:seconds + newTime, 0, 0, 0).
  add correctNode.
  
  // Safe inclination reader that won't crash if next patch disappears or targets wrong body
  local function getInc {
    if doNextPatch {
      if correctNode:orbit:hasnextpatch {
        local np is correctNode:orbit:nextpatch.
        if hasTarget and target:istype("Body") {
          if np:body <> target { return -1. }
        }
        return np:inclination.
      } else {
        return -1.
      }
    } else {
      return correctNode:orbit:inclination.
    }
  }

  local function getError {
    local inc is getInc().
    if inc = -1 { return 9999999. }
    return abs(wantedInclination - inc).
  }

  local newValue is list().
  local oldInclination is getInc().

  if doNextPatch and oldInclination = -1 {
    print "No SOI encounter found. Skipping inclination tuning.".
    remove correctNode.
    wait 0.5.
    return.
  }

  local iterations is 0.
  local maxIterations is 2000.
  local stepSize is deltaChange.

  until abs(oldInclination - wantedInclination) <= marginValue or iterations >= maxIterations or stepSize < 0.0001 {
    local currentError is getError().
    local errors is list().

    changeRadialOut(correctNode, stepSize).
    errors:add(getError()). changeRadialIn(correctNode, stepSize).
    changeRadialIn(correctNode, stepSize).
    errors:add(getError()). changeRadialOut(correctNode, stepSize).

    changeNormal(correctNode, stepSize).
    errors:add(getError()). changeAntiNormal(correctNode, stepSize).
    changeAntiNormal(correctNode, stepSize).
    errors:add(getError()). changeNormal(correctNode, stepSize).

    changePrograde(correctNode, stepSize).
    errors:add(getError()). changeRetrograde(correctNode, stepSize).
    changeRetrograde(correctNode, stepSize).
    errors:add(getError()). changePrograde(correctNode, stepSize).

    local bestError is minOf(errors).
    local bestIndex is errors:indexOf(bestError).

    if bestError < currentError {
      if bestIndex = 0 {changeRadialOut(correctNode, stepSize).}
      else if bestIndex = 1 {changeRadialIn(correctNode, stepSize).}
      else if bestIndex = 2 {changeNormal(correctNode, stepSize).}
      else if bestIndex = 3 {changeAntiNormal(correctNode, stepSize).}
      else if bestIndex = 4 {changePrograde(correctNode, stepSize).}
      else if bestIndex = 5 {changeRetrograde(correctNode, stepSize).}
      
      set oldInclination to getInc().
      set stepSize to min(2.0, stepSize * 1.2).
    } else {
      set stepSize to stepSize / 2.
    }

    if doNextPatch and oldInclination = -1 {
      print "SOI encounter lost. Using current node.".
      break.
    }
    set iterations to iterations + 1.
    wait 0.
  }
  if iterations >= maxIterations {
    print "Solver limit reached. Inc: " + round(oldInclination, 2) + "°".
  }
  set MAPVIEW to prevMap.
  wait 0.5.
}

function changeRadialOut
  {parameter aNode, deltaChange. set aNode:radialout to aNode:radialOut + deltaChange.}
function changeRadialIn
  {parameter aNode, deltaChange. set aNode:radialOut to aNode:radialOut - deltaChange.}
function changeNormal
  {parameter aNode, deltaChange. set aNode:normal to aNode:normal + deltaChange.}
function changeAntiNormal
  {parameter aNode, deltaChange. set aNode:normal to aNode:normal - deltaChange.}
function changePrograde
  {parameter aNode, deltaChange. set aNode:prograde to aNode:prograde + deltaChange.}
function changeRetrograde
  {parameter aNode, deltaChange. set aNode:prograde to aNode:prograde - deltaChange.}
function addNodeTime
  {parameter aNode, deltaChange. set aNode:time to aNode:time + deltaChange.}
function subNodeTime
  {parameter aNode, deltaChange. set aNode:time to aNode:time - deltaChange.}


global function normalVector {
  parameter dir is 1.
  local normVec to dir * vectorCrossProduct(body:position, prograde:vector):normalized.
  return normVec.
}

global function radialVector {
  parameter dir is 1.
  local radVec to dir *  vectorCrossProduct(prograde:vector, normalVector):normalized.
  return radVec.
}