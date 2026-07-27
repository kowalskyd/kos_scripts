runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/camera_director.ks").

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

// Start continuous cinematic camera director cuts around the rover
playRoverCinematicScene(600).

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
  // Generate candidate waypoint coordinates with terrain safety check
  local nextWp is list().
  local attempts is 0.
  until attempts >= 10 {
    local stepN is (random() * 2000) - 1000.
    local stepE is (random() * 2000) - 1000.
    
    local candN is currentOffsetN + stepN.
    local candE is currentOffsetE + stepE.
    set nextWp to getOffsetCoordinates(candN, candE).
    
    // Terrain height check: avoid targeting deep crater interiors
    local candGeo is latlng(nextWp[0], nextWp[1]).
    if candGeo:terrainheight > 50 {
      set currentOffsetN to candN.
      set currentOffsetE to candE.
      break.
    }
    set attempts to attempts + 1.
  }
  
  local distFromStart is sqrt(currentOffsetN^2 + currentOffsetE^2).
  
  clearScreen.
  print "=== Biome Exploration Active ===".
  print "Current Biome: " + getCurrentBiome().
  print "Targeting Waypoint #" + waypointIndex.
  print "Distance from base: " + round(distFromStart, 1) + " m".
  print "---------------------------------".
  
  // Ensure daylight and full battery before driving
  waitForSunlight().
  waitForFullEC().

  // Drive to destination with dynamic cruising speed up to 8 m/s
  // (Auto-collects science whenever crossing into a NEW biome during transit)
  driveToCoordinates(nextWp[0], nextWp[1], 8, 15, true).
  
  // Arrived at waypoint - deploy & transmit science suite
  runScienceExperiments().
  wait 1.
  waitForFullEC().
  
  set waypointIndex to waypointIndex + 1.
}
