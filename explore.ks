runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").

wait 0.1.

clearScreen.
print "=== Rover Exploration Mission Initiated ===".
print "Deploying communication systems and panels...".
wait 1.

// Deploy systems
panels on.
if antenna:length > 0 {
  deployAntenna().
}
wait 1.

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

// Generate exploration waypoints dynamically in an infinite mapping loop
local waypointIndex is 1.
local currentOffsetN is 0.
local currentOffsetE is 0.

until false {
  // Choose a random step size (between -1000 and +1000 meters, a factor of 10 increase)
  local stepN is (random() * 2000) - 1000.
  local stepE is (random() * 2000) - 1000.
  
  set currentOffsetN to currentOffsetN + stepN.
  set currentOffsetE to currentOffsetE + stepE.
  
  local nextWp is getOffsetCoordinates(currentOffsetN, currentOffsetE).
  local distFromStart is sqrt(currentOffsetN^2 + currentOffsetE^2).
  
  clearScreen.
  print "=== Planet Mapping Active ===".
  print "Targeting Waypoint #" + waypointIndex.
  print "Offset North: " + round(currentOffsetN, 1) + " m".
  print "Offset East:  " + round(currentOffsetE, 1) + " m".
  print "Distance from landing site: " + round(distFromStart, 1) + " m".
  print "-----------------------------".
  
  // Drive to the destination at a safe speed of 5 m/s
  driveToCoordinates(nextWp[0], nextWp[1], 5, 10).
  
  // Arrived, run experiments
  wait 1.
  runScienceExperiments().
  wait 3.
  
  set waypointIndex to waypointIndex + 1.
}
