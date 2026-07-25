// ======================================================
//    KERBAL AIRWAYS - IN-FLIGHT ENTERTAINMENT (IFE-9000)
// ======================================================
// Standalone script for secondary kOS processors.
// Features:
//   1. Flight Tracker & Destination Guide + Snack Bar Status
//   2. Live 2D Orbital Radar Map (Kerbin, Mun, Vessel)
//   3. Animated Spinning Kerbin & Mun ASCII Visualizer
//   4. IPC Message Listener for Flight Computer Alerts
// ======================================================

set config:obeyhideui to false.
if config:hasSuffix("term") and config:term:hasSuffix("hideborder") {
  set config:term:hideborder to true.
}
set terminal:width to 50.
set terminal:height to 24.
clearScreen.

// State variables
local currentScreen is 1. // 1: Tracker, 2: Radar, 3: Visualizer
local lastRenderedScreen is 0.
local lastScreenSwitch is time:seconds.
local autoCycle is true.
local frameCount is 0.
local startTime is time:seconds.

local prevMunX is 0.
local prevMunY is 0.

// Function to format seconds into HH:MM:SS
function formatTime {
  parameter tSec.
  local s is floor(mod(tSec, 60)).
  local m is floor(mod(tSec / 60, 60)).
  local h is floor(tSec / 3600).
  
  local sStr is "" + s.
  if s < 10 { set sStr to "0" + s. }
  local mStr is "" + m.
  if m < 10 { set mStr to "0" + m. }
  local hStr is "" + h.
  if h < 10 { set hStr to "0" + h. }
  
  return hStr + ":" + mStr + ":" + sStr.
}

// Function to pad strings for neat table layout
function padRightStr {
  parameter str, totalLen.
  local outStr is "" + str.
  until outStr:length >= totalLen {
    set outStr to outStr + " ".
  }
  return outStr:substring(0, totalLen).
}

// Draw static outer frame
function drawFrame {
  print "+--------------------------------------------------+" at (0,0).
  print "| KERBAL AIRWAYS - IN-FLIGHT ENTERTAINMENT IFE-900 |" at (0,1).
  print "+--------------------------------------------------+" at (0,2).
  
  print "+--------------------------------------------------+" at (0,20).
  print "| [1] Tracker  [2] Radar Map  [3] Orbit Visualizer |" at (0,21).
  print "| Press 1-3 to switch view | Mode: Auto-Cycling    |" at (0,22).
  print "+--------------------------------------------------+" at (0,23).
}

// Render Screen 1: Flight Tracker & Passenger Info
function renderTracker {
  print "=== PASSENGER FLIGHT TRACKER ===" at (2,3).
  
  // Mission Clock & Location
  local met is time:seconds - startTime.
  print "MISSION CLOCK (MET): " + padRightStr(formatTime(met), 20) at (2,4).
  print "CURRENT SOI:         " + padRightStr(ship:body:name, 20) at (2,5).
  print "VESSEL SPEED:        " + padRightStr(round(ship:velocity:orbit:mag) + " m/s", 20) at (2,6).
  print "ALTITUDE:            " + padRightStr(round(ship:altitude / 1000, 1) + " km", 20) at (2,7).
  
  print "--- DESTINATION GUIDE ----------------------------" at (2,9).
  local targetName is "Mun".
  if hasTarget {
    set targetName to target:name.
  }
  print "TARGET DESTINATION:  " + padRightStr(targetName, 20) at (2,10).
  
  local targetDistStr is "N/A".
  if hasTarget {
    set targetDistStr to round((target:position - ship:position):mag / 1000) + " km".
  } else if ship:body:name = "Kerbin" {
    set targetDistStr to round((body("Mun"):position - ship:position):mag / 1000) + " km (Mun)".
  }
  print "DISTANCE TO TARGET:  " + padRightStr(targetDistStr, 20) at (2,11).
  
  // Destination weather / atmosphere report
  local weatherStr is "Airless Vacuum | Temp: -50C to 120C".
  if targetName = "Minmus" {
    set weatherStr to "Mint Flats | Vacuum | Clear Skies!".
  } else if targetName = "Kerbin" {
    set weatherStr to "Dense Atm (1.0atm) | Temp: 15C".
  }
  print "ENVIRONMENT REPORT:  " + padRightStr(weatherStr, 27) at (2,12).
  
  print "--- GALLEY & CABIN COMFORT -----------------------" at (2,14).
  print "SNACK BAR STATUS:    OPERATIONAL (98% Stocked)" at (2,15).
  print "TODAY'S MENU:        Kermin-O's & Hot Cocoa" at (2,16).
  local localG is (body:mu / (body:radius + ship:altitude)^2) / 9.80665.
  local gDesc is "Microgravity".
  if localG > 0.8 { set gDesc to "Earth-like". }
  else if localG > 0.15 { set gDesc to "Low-G". }
  print "CABIN GRAVITY:       " + padRightStr(round(localG, 2) + " G (" + gDesc + ")", 24) at (2,17).
  print "SAFETY STATUS:       ALL SYSTEMS NOMINAL" at (2,18).
}

// Render Screen 2: 2D Orbital Radar Map
function renderRadar {
  print "=== 2D ORBITAL RADAR MAP ===" at (2,3).
  print "Scale: 1 char = ~3,000 km | Center: Kerbin (O)" at (2,4).
  
  // Draw radar box frame (width 36, height 13)
  local startX is 7.
  local startY is 5.
  
  print "+-----------------------------------+" at (startX, startY).
  local rRow is 1.
  until rRow >= 12 {
    print "|                                   |" at (startX, startY + rRow).
    set rRow to rRow + 1.
  }
  print "+-----------------------------------+" at (startX, startY + 12).
  
  // Center of box (Kerbin)
  local centerX is startX + 18.
  local centerY is startY + 6.
  print "O" at (centerX, centerY). // Kerbin
  
  // Compute positions relative to Kerbin
  local kPos is ship:body:position.
  if ship:body:name <> "Kerbin" {
    set kPos to body("Kerbin"):position.
  }
  
  // Ship relative to Kerbin in orbital plane
  local shipRel is ship:position - kPos.
  local scaleFactor is 3000000. // 3,000 km per char
  
  local shipX is centerX + round(shipRel:x / scaleFactor).
  local shipY is centerY + round(shipRel:z / scaleFactor).
  
  // Clamp within box bounds
  set shipX to max(startX + 1, min(startX + 35, shipX)).
  set shipY to max(startY + 1, min(startY + 11, shipY)).
  
  // Draw Ship
  print "*" at (shipX, shipY).
  
  // Draw Mun
  local munRel is body("Mun"):position - kPos.
  local munX is centerX + round(munRel:x / scaleFactor).
  local munY is centerY + round(munRel:z / scaleFactor).
  set munX to max(startX + 1, min(startX + 35, munX)).
  set munY to max(startY + 1, min(startY + 11, munY)).
  
  if munX <> centerX or munY <> centerY {
    print "o" at (munX, munY).
  }
  
  // Legend at bottom
  print "Legend: (O) Kerbin  (o) Mun  (*) Ship" at (7, 18).
  print "Ship Alt: " + round(ship:altitude / 1000) + "km | Speed: " + round(ship:velocity:orbit:mag) + "m/s" at (7, 19).
}

// Render Screen 3: ASCII Animated Spinning Kerbin & Mun Visualizer
function renderVisualizer {
  print "=== ORBITAL VISUALIZER (3D ASCII) ===" at (2,3).
  
  local centerX is 24.
  local centerY is 11.
  
  // Spinning globe frames (8 frames of continent movement)
  local globes is list(
    list("  /~~@~~\\  ", " (  @#~~@ ) ", " (  ~~@#~ ) ", "  \\__~~__/  "),
    list("  /~@~~@~\\  ", " (  #~~@# ) ", " (  ~@#~~ ) ", "  \\__~~__/  "),
    list("  /~~~@~~\\  ", " (  ~~#~~ ) ", " (  @#~~@ ) ", "  \\__~~__/  "),
    list("  /~~@~~~\\  ", " (  ~#~~@ ) ", " (  #~~@# ) ", "  \\__~~__/  "),
    list("  /@~~~@~\\  ", " (  #~~@~ ) ", " (  ~~#~~ ) ", "  \\__~~__/  "),
    list("  /~@~~~@\\  ", " (  ~@~~# ) ", " (  ~#~~@ ) ", "  \\__~~__/  "),
    list("  /~~@~~@\\  ", " (  ~~#~~ ) ", " (  #~~@~ ) ", "  \\__~~__/  "),
    list("  /~~~@~~\\  ", " (  ~#~~@ ) ", " (  ~@~~# ) ", "  \\__~~__/  ")
  ).
  
  local fIdx is mod(frameCount, 8).
  local curGlobe is globes[fIdx].
  
  // Draw Kerbin Globe
  print curGlobe[0] at (centerX - 5, centerY - 2).
  print curGlobe[1] at (centerX - 6, centerY - 1).
  print curGlobe[2] at (centerX - 6, centerY).
  print curGlobe[3] at (centerX - 5, centerY + 1).
  print "KERBIN" at (centerX - 3, centerY + 2).
  
  // Draw Mun revolving around Kerbin in a circle
  local angle is frameCount * 15.
  local munX is centerX + round(14 * cos(angle)).
  local munY is centerY + round(5 * sin(angle)).
  
  if prevMunX >= 2 and prevMunX <= 46 and prevMunY >= 5 and prevMunY <= 17 {
    if prevMunX <> munX or prevMunY <> munY {
      print "       " at (prevMunX, prevMunY).
    }
  }
  set prevMunX to munX.
  set prevMunY to munY.

  if munX >= 2 and munX <= 44 and munY >= 5 and munY <= 17 {
    print "(o) MUN" at (munX, munY).
  }
  
  print "Orbital Mode: Active | Synced with KAL-9000" at (5, 18).
  print "Enjoy your flight with Kerbal Airways!" at (7, 19).
}

// Check for Inter-Process Communication (IPC) messages from primary CPU
function checkIPCMessages {
  if core:hasSuffix("messages") {
    if not (core:messages:empty) {
      local msg is core:messages:pop():content.
      print "+--------------------------------------------------+" at (0,18).
      print "| ALERT: " + padRightStr("" + msg, 40) + " |" at (0,19).
    }
  }
}

// Main Entertainment Loop
drawFrame().

until false {
  // Check user keypress (1, 2, 3)
  if terminal:input:haschar {
    local ch is terminal:input:getchar().
    if ch = "1" { set currentScreen to 1. set autoCycle to false. }
    else if ch = "2" { set currentScreen to 2. set autoCycle to false. }
    else if ch = "3" { set currentScreen to 3. set autoCycle to false. }
  }
  
  // Auto-cycle screen every 8 seconds if enabled
  if autoCycle and (time:seconds - lastScreenSwitch > 8) {
    set currentScreen to mod(currentScreen, 3) + 1.
    set lastScreenSwitch to time:seconds.
  }
  
  // Clear main content area ONLY when changing screens
  if currentScreen <> lastRenderedScreen {
    local rowNum is 3.
    until rowNum >= 20 {
      print "                                                  " at (0, rowNum).
      set rowNum to rowNum + 1.
    }
    set lastRenderedScreen to currentScreen.
    set prevMunX to 0.
    set prevMunY to 0.
  }
  
  // Render active screen
  if currentScreen = 1 {
    renderTracker().
  } else if currentScreen = 2 {
    renderRadar().
  } else if currentScreen = 3 {
    renderVisualizer().
  }
  
  checkIPCMessages().
  
  set frameCount to frameCount + 1.
  wait 0.25. // Smooth 4 FPS refresh for ASCII animation
}
