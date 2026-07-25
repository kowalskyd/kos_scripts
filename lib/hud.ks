// =============================================
//      KAL-9000 HUD & TELEMETRY LIBRARY
// =============================================

global chatterQueue is list().
set config:obeyhideui to false.
if config:hasSuffix("term") and config:term:hasSuffix("hideborder") {
  set config:term:hideborder to true.
}

// Initialize terminal screen with borders and section dividers
global function initScreen {
  parameter programName.
  global hudActive is true.
  clearScreen.
  
  // Set terminal dimensions if supported (default width 50, height 24)
  set terminal:width to 50.
  set terminal:height to 24.

  print "+--------------------------------------------------+" at (0,0).
  print "| KAL-9000 AUTOMATED SYSTEM                        |" at (0,1).
  print "+--------------------------------------------------+" at (0,2).
  
  // Draw layout dividers
  print " PROGRAM: " + programName at (2,1).
  
  // Draw vertical split for Telemetry vs Resources
  local row is 3.
  until row >= 14 {
    print "|" at (27, row).
    set row to row + 1.
  }
  
  print "+--------------------------------------------------+" at (0,14).
  print "| COMM LINK (RADIO LOG)                            |" at (0,15).
  print "+--------------------------------------------------+" at (0,16).
  
  local chatterRow is 17.
  until chatterRow >= 23 {
    print "|" at (0, chatterRow).
    print "|" at (49, chatterRow).
    set chatterRow to chatterRow + 1.
  }
  print "+--------------------------------------------------+" at (0,23).
  
  // Clear the chatter queue on initialization
  chatterQueue:clear().
}

// Update orbital telemetry on the left column
global function updateTelemetry {
  parameter vesselSpeed, altReal, ap, pe, etaAp, etaPe.
  
  print "=== TELEMETRY ===" at (2,3).
  print "ALTITUDE:  " + padRight(round(altReal) + " m", 14) at (2,5).
  print "SPEED:     " + padRight(round(vesselSpeed) + " m/s", 14) at (2,6).
  print "APOAPSIS:  " + padRight(round(ap/1000, 1) + " km", 14) at (2,8).
  print "PERIAPSIS: " + padRight(round(pe/1000, 1) + " km", 14) at (2,9).
  
  if etaAp > 0 and etaAp < 100000 {
    print "ETA AP:    " + padRight(round(etaAp) + " s", 14) at (2,11).
  } else {
    print "ETA AP:    " + padRight("N/A", 14) at (2,11).
  }
  
  if etaPe > 0 and etaPe < 100000 {
    print "ETA PE:    " + padRight(round(etaPe) + " s", 14) at (2,12).
  } else {
    print "ETA PE:    " + padRight("N/A", 14) at (2,12).
  }
  
  // Update resources on the right column
  updateResources().
}

// Update landing-specific telemetry
global function updateLandingTelemetry {
  parameter phaseName, radarAlt, stopDist, throttleVal, vSpd, hSpd.
  
  print "=== LANDING CONTROL ===" at (2,3).
  print "PHASE:     " + padRight(phaseName:toUpper(), 14) at (2,5).
  print "ALT(AGL):  " + padRight(round(radarAlt) + " m", 14) at (2,6).
  print "STOP DIST: " + padRight(round(stopDist) + " m", 14) at (2,7).
  print "THROTTLE:  " + padRight(round(throttleVal * 100) + " %", 14) at (2,8).
  print "V.SPEED:   " + padRight(round(vSpd, 1) + " m/s", 14) at (2,10).
  print "H.SPEED:   " + padRight(round(hSpd, 1) + " m/s", 14) at (2,11).
  
  // Render a suicide burn warning/progress bar if in landing mode
  print "SUICIDE BURN RADAR:" at (2,12).
  local barWidth is 23.
  local ratio is 0.
  if radarAlt > 0 {
    set ratio to stopDist / radarAlt.
  }
  local fillWidth is min(barWidth, max(0, round(ratio * barWidth))).
  local barStr is "".
  local j is 0.
  until j >= barWidth {
    if j < fillWidth {
      set barStr to barStr + "█".
    } else {
      set barStr to barStr + "░".
    }
    set j to j + 1.
  }
  print "[" + barStr + "]" at (2,13).
  
  updateResources().
}

// Update vessel resources on the right column
global function updateResources {
  print "=== RESOURCES ===" at (29,3).
  
  // Get resources
  local lf is ship:liquidfuel.
  local ox is ship:oxidizer.
  local mono is ship:monopropellant.
  local ec is ship:electriccharge.
  local crewCount is ship:crew:length.
  
  print "LIQ FUEL:  " + padRight(round(lf), 8) at (29,5).
  print "OXIDIZER:  " + padRight(round(ox), 8) at (29,6).
  print "MONOPROP:  " + padRight(round(mono), 8) at (29,8).
  print "E.CHARGE:  " + padRight(round(ec), 8) at (29,9).
  
  if crewCount > 0 {
    print "CREW SIZE: " + padRight(crewCount, 8) at (29,11).
    // Print first crew name
    local kName is ship:crew[0]:name:split(" ")[0].
    print "PILOT:     " + padRight(kName, 8) at (29,12).
  } else {
    print "CREW SIZE: " + padRight("UNCREWED", 8) at (29,11).
    print "PILOT:     " + padRight("AUTO", 8) at (29,12).
  }
}
// Log radio chatter into the circular comm-link queue at the bottom
global function logChatter {
  parameter sender, message.
  
  // Mute all pilot, crew, and probe-core chatter
  local isCrew is false.
  if ship:crew:length > 0 {
    for c in ship:crew {
      if c:name:split(" ")[0] = sender { set isCrew to true. }
    }
  }
  if sender = "Crew" or sender = "Pilot" or sender = "Probe-Core" or isCrew {
    return.
  }
  
  local prefix is "[" + sender + "]: ".
  local prefixLen is prefix:length.
  local maxLen is 47. // Usable terminal width columns 1-48
  
  if (prefixLen + message:length) <= maxLen {
    chatterQueue:add(prefix + message).
  } else {
    local firstLineSpace is maxLen - prefixLen.
    local firstLine is prefix + message:substring(0, firstLineSpace).
    chatterQueue:add(firstLine).
    
    local remaining is message:substring(firstLineSpace, message:length - firstLineSpace).
    until remaining:length = 0 {
      local nextLen is min(maxLen - 4, remaining:length).
      chatterQueue:add("    " + remaining:substring(0, nextLen)).
      set remaining to remaining:substring(nextLen, remaining:length - nextLen).
    }
  }
  
  // Manage chatter queue size (fits rows 17 to 22 inclusive, which is 6 lines)
  until chatterQueue:length <= 6 {
    chatterQueue:remove(0).
  }
  
  // Clear print area for chatter
  local chatterRow is 17.
  until chatterRow >= 23 {
    print "                                                " at (1, chatterRow).
    set chatterRow to chatterRow + 1.
  }
  
  // Print active messages from queue
  local idx is 0.
  until idx >= chatterQueue:length {
    print chatterQueue[idx] at (1, 17 + idx).
    set idx to idx + 1.
  }
}

// Post a random chatter dialog based on current flight phase
global function randomChatter {
  parameter phaseName.
  
  local speakers is list().
  if ship:crew:length > 0 {
    for c in ship:crew {
      speakers:add(c:name:split(" ")[0]).
    }
  } else {
    speakers:add("Probe-Core").
  }
  
  local mainPilot is speakers[0].
  local randomCrew is speakers[floor(random() * speakers:length)].
  
  local lines is list().
  if phaseName = "launch" {
    set lines to list(
      list("CapCom", "Ignition confirmed. Hold onto your hats!"),
      list(mainPilot, "Wow, the G-forces are pinning me back!"),
      list("CapCom", "Max-Q passed. Aerodynamic pressures dropping."),
      list(randomCrew, "I think I left the stove on back at KSC...")
    ).
  } else if phaseName = "orbit" {
    set lines to list(
      list(mainPilot, "Orbit established! Smooth sailing from here."),
      list("CapCom", "Radar lock verified. Welcome to space."),
      list(randomCrew, "Can I unbuckle my harness to get a snack?"),
      list("CapCom", "Snack locker authorized for zero-G consumption.")
    ).
  } else if phaseName = "transfer" {
    set lines to list(
      list(mainPilot, "Transfer burn starting. Ejecting from orbit."),
      list("CapCom", "Good burn, KAL-9000. Trajectory looks clean."),
      list(randomCrew, "The destination is getting bigger in the window!")
    ).
  } else if phaseName = "landing" {
    set lines to list(
      list("CapCom", "Deorbit burn starting. Watch your suicide radar!"),
      list(mainPilot, "Suicide burn started. Hold on tight!"),
      list(randomCrew, "Ahhh! The ground is coming up way too fast!"),
      list(mainPilot, "Engine cutoff. Touchdown! We are on the surface!")
    ).
  } else if phaseName = "ascent" {
    set lines to list(
      list(mainPilot, "Launching from surface. Engines hot!"),
      list("CapCom", "Lander liftoff confirmed. Re-entering orbit."),
      list(randomCrew, "Goodbye local hills, back to space!")
    ).
  } else if phaseName = "return" {
    set lines to list(
      list(mainPilot, "Kerbin return burn completed. Going home!"),
      list("CapCom", "We have a recovery team waiting on you."),
      list(randomCrew, "It is getting hot in here! Shield is glowing!"),
      list(mainPilot, "Parachutes deployed. Touchdown in sight.")
    ).
  }
  
  // Pick a random chat dialog
  local chat is lines[floor(random() * lines:length)].
  logChatter(chat[0], chat[1]).
}

// Perform sequential diagnostic checks at startup with checkmarks
global function runDiagnostics {
  parameter labels.
  
  print "=== DIAGNOSTICS ===" at (2,3).
  local idx is 0.
  until idx >= labels:length {
    print "[ ] " + padRight(labels[idx], 18) at (2, 5 + idx).
    set idx to idx + 1.
  }
  
  set idx to 0.
  until idx >= labels:length {
    wait 0.6.
    print "✔" at (3, 5 + idx).
    set idx to idx + 1.
  }
  wait 0.5.
}

// Display screen center overlay message (redirected to radio comms log to prevent main screen clutter)
global function hudMsg {
  parameter msg, colorVal is rgb(0, 1, 0).
  logChatter("System", msg).
}

// Suffix helper for padding
local function padRight {
  parameter str, length.
  local padded is "" + str.
  until padded:length >= length {
    set padded to padded + " ".
  }
  return padded.
}
