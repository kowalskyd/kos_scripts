//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 AUTONAMOUS FRONTIER EXPLORATION MISSION
// (Costmaps, Dynamic Gravity Limits, Ridge Perpendicular Climb & Crater Rim Bypass)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

set CONFIG:IPU to 1000.

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").
runOncePath("0:/lib/ros_nav2.ks").

// Optional cinematic camera director integration
if exists("0:/lib/camera_director.ks") {
  runOncePath("0:/lib/camera_director.ks").
}

wait 0.1.

// Reset spatial memory lists for fresh exploration run
set rosVisitedSectors to list().
set rosBlacklistedSectors to list().
set rosZoneAnchorGeo to ship:geoposition.
set rosActiveTargetGeo to 0.

clearScreen.
print "==================================================".
print "=== ROS 2 NAV2 AUTONAV ROVER MISSION INITIALIZATION ===".
print "==================================================".
print "Booting up system parameters & costmap engine...".

// System deployment
panels on.
if antenna:length > 0 {
  deployAntenna().
}

// Start cinematic camera director scene if function exists
if defined playRoverCinematicScene {
  playRoverCinematicScene(200).
}

local frontierIndex is 1.

until false {
  // 1. Ensure full battery power and daylight before departing
  waitForSunlight().
  waitForFullEC().

  set rosCurrentFrontier to frontierIndex.

  // 2. Compute optimal information-gain frontier target using ROS 2 spatial evaluator
  local targetGeo is rosSelectFrontierTarget(ship:geoposition, 250).

  hudText("ROS 2 Nav2: Selected Frontier #" + frontierIndex + " [Lat: " + round(targetGeo:lat, 2) + ", Lng: " + round(targetGeo:lng, 2) + "]", 5, 2, 25, rgb(0.2, 0.8, 1.0), true).

  // 3. Drive Eastward toward target Zone using Nav2 Costmaps & DWA local planner
  // Cruise speed: 6.0 m/s (auto-scaled by surface gravity), Arrival radius: 25.0m
  local arrivalSuccess is rosDriveToCoordinates(targetGeo:lat, targetGeo:lng, 6.0, 25.0, true).

  if arrivalSuccess {
    // 4. Arrived in new Zone! Update zone anchor & deploy science ONCE per Zone entry
    set rosZoneAnchorGeo to targetGeo.
    runScienceExperiments().
    wait 1.0.
    waitForFullEC().
    set frontierIndex to frontierIndex + 1.
  } else {
    // 5. Barrier Encountered: Execute 2.5D Cell-Stepping Detour (1 cell North/South)
    rosCellSteppingDetour().
  }
}
