// --- THE SIMPLIFIED PILOT-LOGIC AUTOPILOT (WITH SMART STAGING) ---
runOncePath("0:/lib/hud.ks").
runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/camera_director.ks").
initScreen("launch").

// 1. Core Target Values
SET TARGET_ALT TO 120000. // Clean 125km target boundary

// Background trigger to deploy procedural fairings at 75,000m altitude
WHEN SHIP:ALTITUDE > 75000 THEN {
    PRINT "Passing 75k altitude - Deploying fairings...".
    FOR P IN SHIP:PARTS {
        IF P:HASMODULE("ModuleProceduralFairing") {
            LOCAL M IS P:GETMODULE("ModuleProceduralFairing").
            IF M:HASEVENT("deploy") {
                M:DOEVENT("deploy").
            }
        }
    }
}

FUNCTION FORCE_TOP_CONTROL {
    LIST PARTS IN ALL_PARTS.
    FOR P IN ALL_PARTS { IF P:HASMODULE("ModuleCommand") { P:CONTROLFROM(). BREAK. } }
}
FORCE_TOP_CONTROL().
// 2. Launch Sequence
playLaunchScene(10).
local count is 10.
until count = 0 {
    logChatter("CapCom", "T-Minus " + count + "s...").
    
    wait 1.
    set count to count - 1.
}
logChatter("CapCom", "All systems nominal. Commencing ignition.").
hudMsg("IGNITION SEQUENCE START").
playLiftoffScene().
LOCK THROTTLE TO 1.0. STAGE. WAIT 1.5. STAGE. 
LOCK STEERING TO HEADING(90, 90). // Start straight up
logChatter("Crew", "We have liftoff! Ascent program engaged.").

WHEN SHIP:ALTITUDE > 5000 THEN {
    playLiftoffClimbScene().
}
WHEN SHIP:ALTITUDE > 15000 THEN {
    playAscendScene().
}
WHEN SHIP:ALTITUDE > 35000 THEN {
    playFlybyScene(15).
    local resumeTime is time:seconds + 15.
    WHEN TIME:SECONDS > resumeTime THEN {
        playAscendScene().
    }
}

// 3. Ascent & Smooth Gravity Turn
SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
SET KUNIVERSE:TIMEWARP:RATE TO 2.
local lastChatTime is time:seconds.
local myPitch is 90.
LOCK STEERING TO HEADING(90, myPitch).

UNTIL SHIP:APOAPSIS >= TARGET_ALT {
    
    // SMART ENGINE STAGING: Drops side boosters if ANY active engine flames out
    LIST ENGINES IN ALL_ENGINES.
    FOR ENG IN ALL_ENGINES {
        IF ENG:FLAMEOUT {
            logChatter("KAL-9000", "Booster burnout! Separating...").
            hudMsg("STAGING BOOSTERS").
            STAGE.
            WAIT 1.5. // Wait for empty boosters to clear before checking again
            FORCE_TOP_CONTROL().
            BREAK.
        }
    }
    // Backup staging for total thrust loss
    IF MAXTHRUST = 0 {
        logChatter("KAL-9000", "Total thrust loss! Staging...").
        STAGE. WAIT 1.5. FORCE_TOP_CONTROL().
    }

    // Smooth mathematical gravity turn profile
    if ship:altitude > 1000 {
        set myPitch to 90 - 80 * (((ship:altitude - 1000) / 59000) ^ 0.35).
        set myPitch to max(10, min(90, myPitch)).
    }
    
    if time:seconds - lastChatTime > 18 {
      randomChatter("launch").
      set lastChatTime to time:seconds.
    }
    updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
    WAIT 0.1.
}
// 4. Coast into Space
LOCK THROTTLE TO 0.
LOCK STEERING TO SHIP:PROGRADE.
rcs off. // Turn off RCS to save monopropellant
PRINT "Target Apoapsis reached. Coasting out of atmosphere...".

// Engage physics warp for coast out of atmosphere
IF SHIP:ALTITUDE < 70000 {
    SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
    SET KUNIVERSE:TIMEWARP:RATE TO 4.
}

UNTIL SHIP:ALTITUDE > 70000 {
    WAIT 0.5.
}
SET KUNIVERSE:TIMEWARP:RATE TO 1. // Stop physics warp
SET KUNIVERSE:TIMEWARP:MODE TO "RAILS". // Reset time warp mode to rails for space travel

// 5. PRECISE CIRCULARIZATION BURN (vis-viva maneuver node)
initScreen("insertion").
logChatter("CapCom", "Orbit insertion program active.").

// Turn to face prograde early during coast
LOCK STEERING TO SHIP:PROGRADE.
rcs on. // Re-enable RCS for attitude adjustment

// Warp to near apoapsis
local warpMargin is max(30, min(70, ship:mass / 5 + 10)).
IF ETA:APOAPSIS > warpMargin + 10 {
    logChatter("CapCom", "Warping to Apoapsis insertion window.").
    rcs off.
    set MAPVIEW to true.
    WARPTO(TIME:SECONDS + ETA:APOAPSIS - warpMargin).
    WAIT UNTIL KUNIVERSE:TIMEWARP:RATE = 1.
    set MAPVIEW to false.
    rcs on.
}

// Compute exact circularization dV using vis-viva equation
local r_ap is ship:orbit:apoapsis + body:radius.
local v_ap is sqrt(body:mu * (2/r_ap - 1/ship:orbit:semimajoraxis)).
local v_circ is sqrt(body:mu / r_ap).
local dv_circ is v_circ - v_ap.

logChatter("CapCom", "Circularization dV: " + round(dv_circ, 1) + " m/s").

// Create and execute a precise maneuver node at apoapsis
local circNode is node(time:seconds + ETA:apoapsis, 0, 0, dv_circ).
add circNode.
wait 0.1.

hudMsg("CIRCULARIZATION BURN").
exeMnv().
wait 1.

logChatter("Crew", "Engines shut down. Orbit locked.").
hudMsg("ORBIT ESTABLISHED").
WAIT 2.

// 6. OPTIONAL CORRECTION (only if circularization was significantly off)
if ship:orbit:periapsis < TARGET_ALT * 0.8 {
    logChatter("CapCom", "Periapsis low. Performing minor correction.").
    wait 1.
    goToFrom(TARGET_ALT, "AP").
    exeMnv().
    wait 1.
} else {
    logChatter("CapCom", "Orbit profile nominal. No correction needed.").
}

// 9. Full Shutdown
LOCK THROTTLE TO 0. UNLOCK STEERING. UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
initScreen("orbit_locked").
logChatter("CapCom", "Mission Control: Orbit successfully locked!").
logChatter("Crew", "Copy that. Flight computer entering standby mode.").
hudMsg("ORBIT LOCKED: " + ROUND(OBT:APOAPSIS / 1000, 1) + "k x " + ROUND(OBT:PERIAPSIS / 1000, 1) + "k").
playOrbitScene().

// Keep telemetry displayed
if not (defined automatedMission) {
  until false {
    updateTelemetry(ship:velocity:orbit:mag, ship:altitude, ship:orbit:apoapsis, ship:orbit:periapsis, eta:apoapsis, eta:periapsis).
    WAIT 1.0.
  }
} else {
  wait 5.
}
