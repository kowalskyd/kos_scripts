//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROVER CONTROL AND NAVIGATION LIBRARY
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

global function driveToCoordinates {
  parameter targetLat.
  parameter targetLng.
  parameter maxSpeed is 6. // m/s
  parameter arrivalRadius is 12. // meters

  local targetGeo is latlng(targetLat, targetLng).
  
  hudText("Heading to waypoint: Lat " + round(targetLat, 4) + ", Lng " + round(targetLng, 4), 3, 2, 20, rgb(0.2, 0.8, 0.2), false).
  
  brakes off.
  
  // Set up kOS steering and throttle manager for rovers
  local targetThrottle is 0.
  lock wheelsteering to targetGeo.
  lock wheelthrottle to targetThrottle.
  
  until false {
    local dist is targetGeo:distance.
    local curSpeed is ship:groundspeed.
    local bearingTo is targetGeo:bearing. // relative angle to target (-180 to 180)
    
    // Arrival condition
    if dist < arrivalRadius {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      hudText("Arrived at waypoint!", 3, 2, 20, rgb(0.2, 0.8, 0.2), false).
      break.
    }
    
    // Pitch: nose-up/down tilt relative to horizontal
    local currentPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
    // Total tilt: tilt of the rover's roof relative to vertical
    local currentTilt is vAng(ship:up:vector, ship:facing:topvector).
    
    // Safety check: check tilt/pitch for tipping
    if abs(currentPitch) > 25 or currentTilt > 25 {
      brakes on.
      set targetThrottle to 0.
      hudText("HAZARD DETECTED: Steep incline! Stopping.", 5, 2, 25, rgb(1, 0, 0), false).
      wait until abs(90 - vAng(ship:up:vector, ship:facing:forevector)) <= 20 and vAng(ship:up:vector, ship:facing:topvector) <= 20.
      brakes off.
    }
    
    // Throttle logic
    // Reduce throttle if speed is close to max, or if we need to make a sharp turn.
    if curSpeed < maxSpeed {
      // Scale throttle based on alignment with the target heading
      if abs(bearingTo) > 45 {
        // Sharp turn needed: slow down
        set targetThrottle to 0.15.
      } else if abs(bearingTo) > 15 {
        // Moderate turn: medium throttle
        set targetThrottle to 0.3.
      } else {
        // Well-aligned: accelerate up to max speed
        set targetThrottle to min(1.0, (maxSpeed - curSpeed) * 0.5 + 0.2).
      }
    } else {
      // Over speed limit: coast or brake slightly
      set targetThrottle to 0.
    }
    
    // Telemetry display
    print "--- Rover Telemetry ---" at (0, 4).
    print "Distance to target: " + round(dist, 1) + " m     " at (0, 5).
    print "Speed: " + round(curSpeed, 2) + " m/s / " + maxSpeed + " m/s    " at (0, 6).
    print "Bearing to target: " + round(bearingTo, 1) + " deg    " at (0, 7).
    print "Pitch: " + round(currentPitch, 1) + " / Tilt: " + round(currentTilt, 1) + "      " at (0, 8).
    
    wait 0.1.
  }
}

global function runScienceExperiments {
  hudText("Deploying science experiments...", 3, 2, 20, rgb(0.2, 0.6, 1.0), false).
  
  local experimentsList is list().
  for p in ship:parts {
    for m in p:modules {
      if m = "ModuleScienceExperiment" {
        experimentsList:add(p:getModule("ModuleScienceExperiment")).
      }
    }
  }
  
  if experimentsList:length = 0 {
    print "No science experiments found on this vessel." at (0, 10).
    return.
  }
  
  for exp in experimentsList {
    // If the experiment already has data, try to transmit it if online
    if exp:hasdata and ship:connection:isconnected {
      exp:transmit().
      wait 0.5.
    }
    
    // Deploy the experiment if it has no data
    if not exp:hasdata {
      exp:deploy().
      local startWait is time:seconds.
      wait until exp:hasdata or (time:seconds - startWait > 6).
    }
    
    // Transmit if connected, otherwise leave it stored on the sensor
    if exp:hasdata {
      if ship:connection:isconnected {
        print "Transmitting: " + exp:part:title + "      " at (0, 11).
        exp:transmit().
        wait 1.5.
      } else {
        print "Stored on part: " + exp:part:title + "     " at (0, 11).
      }
    }
  }
  
  // Try to collect all stored data into the ship's science container
  // to reset the individual science parts for the next waypoint.
  local containerList is ship:modulesNamed("ModuleScienceContainer").
  if containerList:length > 0 {
    print "Collecting data to science container..." at (0, 12).
    containerList[0]:doEvent("collect all").
    wait 1.0.
    print "                                        " at (0, 12).
  }
  
  hudText("All experiments processed!", 3, 2, 20, rgb(0.2, 0.6, 1.0), false).
}
