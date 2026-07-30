//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 KOS MASTER BATTLE ORCHESTRATOR & COMMAND CONSOLE
// (Orchestrates All Slave Rovers & Displays Fleet Telemetry)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

switch to 0.

set CONFIG:IPU to 1000.

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/ros_battle_ai.ks").

clearScreen.
print "==================================================".
print "=== ROS 2 KOS MASTER BATTLE ORCHESTRATOR CONSOLE =".
print "==================================================".

// 1. Create global Battle Start signal files on shared Archive drive (0:/)
log "START" to "0:/battle_start.txt".
writeJson("START", "0:/battle_start.json").

// 2. Scan for all loaded rovers in physics bubble
local slaveFleet is list().
local targetList is list().
list targets in targetList.

for v in targetList {
  if v:typename = "Vessel" and v <> ship and isVesselOperational(v) {
    local vName is v:name.
    if not (vName:contains("Master") or vName:contains("master") or vName:contains("Command") or vName:contains("command") or vName:contains("Carrier") or vName:contains("carrier")) {
      slaveFleet:add(v).
    }
  }
}

// 3. Send direct inter-vessel messages to ALL slave rovers!
for r in slaveFleet {
  r:connection:sendmessage("START").
}

// 4. Broadcast Action Group 10
AG10 ON.
wait 0.2.
AG10 OFF.

hudText("MASTER COMMANDER: BATTLE SIGNAL SENT TO ALL FLEET UNITS!", 5, 2, 25, rgb(0.2, 1.0, 0.4), true).

// 5. MASTER TACTICAL FLEET COMMANDER HUD
local lastMasterHud is 0.

until false {
  if (time:seconds - lastMasterHud) > 0.4 {
    clearScreen.
    print "==================================================" at (0, 0).
    print "=== ROS 2 MASTER FLEET COMMANDER TELEMETRY HUD ==" at (0, 1).
    print "==================================================" at (0, 2).
    print "SLAVE FLEET STATUS (" + slaveFleet:length + " UNITS ENGAGED):" at (0, 3).
    print "--------------------------------------------------" at (0, 4).

    local line is 5.
    local activeCount is 0.

    for r in slaveFleet {
      local statusStr is "OPERATIONAL".
      if not isVesselOperational(r) {
        set statusStr to "INCAPACITATED".
      } else {
        set activeCount to activeCount + 1.
      }

      local infoLine is " " + padRight(r:name, 18) + " | " + padRight(statusStr, 14) + " | " + round(r:distance, 1) + "m".
      print infoLine at (0, line).
      set line to line + 1.
    }

    print "--------------------------------------------------" at (0, line).
    set line to line + 1.
    print "ACTIVE COMBATANTS: " + activeCount + " / " + slaveFleet:length at (0, line).
    set line to line + 1.
    print "==================================================" at (0, line).

    set lastMasterHud to time:seconds.
  }

  wait 0.1.
}
