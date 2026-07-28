runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/camera_director.ks").

wait 0.1.

clearScreen.
print "=== Curiosity-Class Autonomous Rover Mission Initiated ===".
print "Booting up, please wait...".



panels on.
if antenna:length > 0 {
  deployAntenna().

}

// Start continuous cinematic camera director cuts around the rover
playRoverCinematicScene(200).

// Get starting position
local startGeo is ship:geoposition.
local bodyRadius is ship:body:radius.

// Helper function to calculate offset coordinates (North/East in meters)
function getOffsetCoordinates {
  parameter offsetN.
  parameter offsetE.
  
  local latDegrees is (offsetN / bodyRadius) * (180 / constant:pi).
  local lngDegrees is (offsetE / (bodyRadius * cos(startGeo:lat))) * (180 / constant:pi).
  
  return list(startGeo:lat + latDegrees, startGeo:lng + lngDegrees).
}

// Generate exploration waypoints dynamically with terrain hazard filter
local waypointIndex is 1.
local currentOffsetN is 0.
local currentOffsetE is 0.

until false {
  // Generate candidate macro-waypoint coordinates with terrain safety check
  local nextWp is list().
  local attempts is 0.
  until attempts >= 15 {
    local stepN is (random() * 2000) - 1000.
    local stepE is (random() * 2000) - 1000.
    
    local candN is currentOffsetN + stepN.
    local candE is currentOffsetE + stepE.
    set nextWp to getOffsetCoordinates(candN, candE).
    
    local candGeo is latlng(nextWp[0], nextWp[1]).
    local macroSlope is getSCANsatSlope(candGeo:lat, candGeo:lng).

    // Avoid deep liquid oceans, high mountain faces, and steep crater walls (>14 deg slope)
    if candGeo:terrainheight > 15 and macroSlope < 14 {
      set currentOffsetN to candN.
      set currentOffsetE to candE.
      break.
    }
    set attempts to attempts + 1.
  }
  
  local distFromStart is sqrt(currentOffsetN^2 + currentOffsetE^2).
  
  // Ensure daylight and full battery before driving
  waitForSunlight().
  waitForFullEC().

  // Drive to destination using Curiosity Autonav (Cruise speed: 4.0 m/s, Arrival radius: 120 m)
  driveToCoordinates(nextWp[0], nextWp[1], 8.0, 120.0, false, waypointIndex, startGeo).
  
  // Arrived at waypoint - deploy & transmit science suite
  runScienceExperiments().
  wait 1.
  waitForFullEC().
  
  set waypointIndex to waypointIndex + 1.
}
