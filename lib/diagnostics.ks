// =============================================
//      KAL-9000 PRE-FLIGHT DIAGNOSTICS SYSTEM
// =============================================

// Helper function to extract max thrust of unignited engines
local function getEngineMaxThrust {
  parameter eng.
  local thrustVal is 0.
  
  if eng:hasSuffix("possiblethrust") {
    set thrustVal to eng:possiblethrust.
  }
  if thrustVal = 0 and eng:hasSuffix("maxthrust") {
    set thrustVal to eng:maxthrust.
  }
  
  // If still 0, query KSP fields from modules directly
  if thrustVal = 0 {
    if eng:part:hasmodule("ModuleEnginesFX") {
      set thrustVal to eng:part:getmodule("ModuleEnginesFX"):getfield("maxThrust").
    } else if eng:part:hasmodule("ModuleEngines") {
      set thrustVal to eng:part:getmodule("ModuleEngines"):getfield("maxThrust").
    }
  }
  
  return thrustVal.
}

global function runPreFlightChecks {
  // Set terminal dimensions
  set terminal:width to 50.
  set terminal:height to 24.
  clearScreen.

  // -------------------------------------------
  // 1. Define Mission Threshold Requirements
  // -------------------------------------------
  local reqEC is 200.
  local reqSolar is 1.
  local reqChutes is 1.
  local reqAblator is 100.
  local reqAntenna is 1.
  local reqLegs is 3.
  local reqRCS is 4.
  local reqDeltav is 5500.
  local reqTWR is 1.15.

  // -------------------------------------------
  // 2. Gather Resource Data (Total Ship)
  // -------------------------------------------
  local totalEC is 0.
  local maxEC is 0.
  local totalLF is 0.
  local maxLF is 0.
  local totalOX is 0.
  local maxOX is 0.
  local totalAblator is 0.
  local maxAblator is 0.

  for res in ship:resources {
    if res:name = "ElectricCharge" {
      set totalEC to res:amount.
      set maxEC to res:capacity.
    }
    if res:name = "LiquidFuel" {
      set totalLF to res:amount.
      set maxLF to res:capacity.
    }
    if res:name = "Oxidizer" {
      set totalOX to res:amount.
      set maxOX to res:capacity.
    }
    if res:name = "Ablator" {
      set totalAblator to res:amount.
      set maxAblator to res:capacity.
    }
  }

  // -------------------------------------------
  // 3. Gather Part & Module Data
  // -------------------------------------------
  local panelCount is 0.
  local chuteCount is 0.
  local antennaCount is 0.
  local legCount is 0.
  local shieldCount is 0.
  local rcsCount is 0.

  for p in ship:parts {
    if p:hasmodule("ModuleDeployableSolarPanel") or p:hasmodule("ModuleSolarPanel") or p:name:contains("solar") or p:name:contains("panel") {
      set panelCount to panelCount + 1.
    }
    if p:hasmodule("ModuleParachute") or p:name:contains("parachute") or p:name:contains("chute") {
      set chuteCount to chuteCount + 1.
    }
    // Antenna: count dedicated antennas only (exclude command pods)
    if not p:hasmodule("ModuleCommand") {
      if p:hasmodule("ModuleDeployableAntenna") or p:hasmodule("ModuleDataTransmitter") or p:hasmodule("ModuleRealAntenna") or p:name:contains("antenna") or p:name:contains("dish") {
        set antennaCount to antennaCount + 1.
      }
    }
    if p:hasmodule("ModuleWheelDeployment") or p:name:contains("landingLeg") or p:name:contains("miniLeg") or p:name:contains("foot") or p:name:contains("leg") {
      set legCount to legCount + 1.
    }
    if p:hasmodule("ModuleHeatShield") or p:name:contains("heatshield") or p:name:contains("shield") {
      set shieldCount to shieldCount + 1.
    }
    if p:hasmodule("ModuleRCS") or p:hasmodule("ModuleRCSFX") or p:name:contains("rcs") {
      set rcsCount to rcsCount + 1.
    }
  }

  // -------------------------------------------
  // 4. Gather Physics & Propulsion Data
  // -------------------------------------------
  local gKerbin is 9.81.
  local launchTwr is 0.
  local enginesList is list().
  list engines in enginesList.
  
  local maxEngStage is -1.
  for eng in enginesList {
    if eng:stage > maxEngStage {
      set maxEngStage to eng:stage.
    }
  }
  
  local launchThrust is 0.
  local detailsStr is "No engines found.".
  if maxEngStage >= 0 {
    local count is 0.
    for eng in enginesList {
      if eng:stage = maxEngStage {
        local engThrust to getEngineMaxThrust(eng).
        set launchThrust to launchThrust + engThrust.
        set count to count + 1.
      }
    }
    set detailsStr to count + " eng (" + round(launchThrust) + "kN)".
  }
  
  if ship:mass > 0 {
    set launchTwr to launchThrust / (ship:mass * gKerbin).
  }

  // Calculate Delta-V
  local totalDeltav is 0.
  local dvSource is "kOS DeltaV".
  if ship:hasSuffix("deltav") {
    set totalDeltav to ship:deltav:vacuum.
  }
  if totalDeltav = 0 {
    set dvSource to "Est. ISP/Mass".
    local totalWet is ship:mass.
    local totalDry is ship:drymass.
    local avgIsp is 320.
    local count is 0.
    local sumIsp is 0.
    for eng in enginesList {
      local engIsp is 0.
      if eng:isp > 0 {
        set engIsp to eng:isp.
      } else {
        set engIsp to 320. // Standard vacuum ISP fallback
      }
      set sumIsp to sumIsp + engIsp.
      set count to count + 1.
    }
    if count > 0 {
      set avgIsp to sumIsp / count.
    }
    set totalDeltav to avgIsp * 9.81 * ln(totalWet / max(0.1, totalDry)).
  }

  // -------------------------------------------
  // 5. Draw UI Framework & Borders
  // -------------------------------------------
  print "+--------------------------------------------------+" at (0,0).
  print "| KAL-9000 PRE-FLIGHT SYSTEMS DIAGNOSTICS          |" at (0,1).
  print "+--------------------------------------------------+" at (0,2).
  print "|                                                  |" at (0,3).
  print "|   SYSTEMS RUNNING:                               |" at (0,4).

  // Print skeleton helper
  local function printSkeleton {
    parameter name, row.
    local displayName is name.
    if displayName:length > 21 {
      set displayName to displayName:substring(0, 21).
    }
    print " [ . ] " + displayName at (2, row).
  }

  printSkeleton("Electrical Power", 5).
  printSkeleton("Solar Generation", 6).
  printSkeleton("Aerodynamic Recovery", 7).
  printSkeleton("Thermal Shielding", 8).
  printSkeleton("Telemetry & Comms", 9).
  printSkeleton("Munar Landing Gear", 10).
  printSkeleton("RCS Control System", 11).
  printSkeleton("Liquid Fuel/Oxidizer", 12).
  printSkeleton("Total Mission dV", 13).
  printSkeleton("Launch TWR (Pad)", 14).

  print "+--------------------------------------------------+" at (0,15).
  print "| DIAGNOSTIC REPORTS & REMEDIAL ACTIONS            |" at (0,16).
  print "+--------------------------------------------------+" at (0,17).

  local clearIdx is 18.
  until clearIdx >= 21 {
    print "|                                                  |" at (0, clearIdx).
    set clearIdx to clearIdx + 1.
  }
  print "+--------------------------------------------------+" at (0,21).
  print "| STATUS: INITIATING SEQUENTIAL CHECKS...          |" at (0,22).
  print "+--------------------------------------------------+" at (0,23).

  // Check results helper
  local function printCheckResult {
    parameter name, chkStatus, infoStr, row.
    local statusStr is " [  OK  ] ".
    if chkStatus = 1 { set statusStr to " [ WARN ] ". }
    if chkStatus = 2 { set statusStr to " [ FAIL ] ". }
    
    local displayName is name.
    if displayName:length > 21 {
      set displayName to displayName:substring(0, 21).
    }
    
    // Clear check line columns 1 to 48
    print "                                                " at (1, row).
    print statusStr + displayName at (2, row).
    print infoStr at (33, row).
  }

  local totalErrors is 0.
  local totalWarnings is 0.
  local activeReportType is 0. // 0 = none, 1 = warn, 2 = fail

  local function updateReportPanel {
    parameter sysName, statusType, desc, remedy.
    if statusType >= activeReportType {
      set activeReportType to statusType.
      local clearIdx is 18.
      until clearIdx >= 21 {
        print "                                                " at (1, clearIdx).
        set clearIdx to clearIdx + 1.
      }
      local typeStr is "WARN".
      if statusType = 2 { set typeStr to "FAIL". }
      
      print " SYSTEM: " + sysName at (2, 18).
      print " STATUS: [" + typeStr + "] " + desc at (2, 19).
      print " REMEDY: " + remedy at (2, 20).
    }
  }

  // -------------------------------------------
  // 6. Execute Sequential Checks
  // -------------------------------------------

  // Check 1: EPS
  wait 0.4.
  local epsStatus is 0.
  local pctEC is round(totalEC / reqEC * 100).
  local epsDesc is "EC: " + round(totalEC) + "/" + reqEC + " req (" + pctEC + "%)".
  local epsRemedy is "Charge batteries or add solar panels.".
  if maxEC = 0 or totalEC < 50 {
    set epsStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Electrical Power", 2, epsDesc, epsRemedy).
  } else if totalEC < reqEC {
    set epsStatus to 1.
    set totalWarnings to totalWarnings + 1.
    updateReportPanel("Electrical Power", 1, epsDesc, epsRemedy).
  }
  printCheckResult("Electrical Power", epsStatus, round(totalEC) + " EC (" + pctEC + "%)", 5).

  // Check 2: Solar
  wait 0.4.
  local solarStatus is 0.
  local pctSolar is round(panelCount / reqSolar * 100).
  local solarDesc is "Solar Panels: " + panelCount + "/" + reqSolar + " req (" + pctSolar + "%)".
  local solarRemedy is "Add solar panels to recharge batteries.".
  if panelCount = 0 {
    set solarStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Solar Generation", 2, solarDesc, solarRemedy).
  }
  printCheckResult("Solar Generation", solarStatus, panelCount + " panels (" + pctSolar + "%)", 6).

  // Check 3: Chutes
  wait 0.4.
  local chuteStatus is 0.
  local pctChutes is round(chuteCount / reqChutes * 100).
  local chuteDesc is "Parachutes: " + chuteCount + "/" + reqChutes + " req (" + pctChutes + "%)".
  local chuteRemedy is "Attach parachutes for Kerbin return.".
  if chuteCount = 0 {
    set chuteStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Aerodynamic Recovery", 2, chuteDesc, chuteRemedy).
  }
  printCheckResult("Aerodynamic Recovery", chuteStatus, chuteCount + " chutes (" + pctChutes + "%)", 7).

  // Check 4: Shield
  wait 0.4.
  local shieldStatus is 0.
  local pctAblator is 0.
  if maxAblator > 0 { set pctAblator to round(totalAblator / maxAblator * 100). }
  local shieldDesc is "Ablator: " + round(totalAblator) + "/" + reqAblator + " req (" + pctAblator + "%)".
  local shieldRemedy is "Add heat shield under capsule.".
  if shieldCount = 0 {
    set shieldStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Thermal Shielding", 2, shieldDesc, shieldRemedy).
  } else if totalAblator < reqAblator {
    set shieldStatus to 1.
    set totalWarnings to totalWarnings + 1.
    updateReportPanel("Thermal Shielding", 1, shieldDesc, shieldRemedy).
  }
  printCheckResult("Thermal Shielding", shieldStatus, round(totalAblator) + " Abl (" + pctAblator + "%)", 8).

  // Check 5: Antenna
  wait 0.4.
  local antennaStatus is 0.
  local pctAntenna is round(antennaCount / reqAntenna * 100).
  local antennaDesc is "Dedicated Antennas: " + antennaCount + "/" + reqAntenna + " req".
  local antennaRemedy is "Attach antennas to establish comms.".
  if antennaCount = 0 {
    set antennaStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Telemetry & Comms", 2, antennaDesc, antennaRemedy).
  }
  printCheckResult("Telemetry & Comms", antennaStatus, antennaCount + " antennas (" + pctAntenna + "%)", 9).

  // Check 6: Legs
  wait 0.4.
  local legStatus is 0.
  local pctLegs is round(legCount / reqLegs * 100).
  local legDesc is "Landing Legs: " + legCount + "/" + reqLegs + " req (" + pctLegs + "%)".
  local legRemedy is "Attach 3-4 landing legs to lander stage.".
  if legCount = 0 {
    set legStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Munar Landing Gear", 2, legDesc, legRemedy).
  } else if legCount < reqLegs {
    set legStatus to 1.
    set totalWarnings to totalWarnings + 1.
    updateReportPanel("Munar Landing Gear", 1, legDesc, legRemedy).
  }
  printCheckResult("Munar Landing Gear", legStatus, legCount + " legs (" + pctLegs + "%)", 10).

  // Check 7: RCS
  wait 0.4.
  local rcsStatus is 0.
  if rcsCount > 0 and not rcs {
    rcs on.
  }
  local rcsState is "OFF".
  if rcs { set rcsState to "ON". }
  local pctRCS is round(rcsCount / reqRCS * 100).
  local rcsDesc is "RCS state: " + rcsState + " (" + rcsCount + "/" + reqRCS + " req)".
  local rcsRemedy is "Turn RCS ON (press R).".
  if rcsCount = 0 {
    set rcsStatus to 2.
    set totalErrors to totalErrors + 1.
    set rcsDesc to "No RCS thruster blocks installed".
    set rcsRemedy to "Add RCS blocks for translation control.".
    updateReportPanel("RCS Control System", 2, rcsDesc, rcsRemedy).
  } else if not rcs {
    set rcsStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("RCS Control System", 2, rcsDesc, rcsRemedy).
  }
  printCheckResult("RCS Control System", rcsStatus, rcsCount + " blk (" + rcsState + ")", 11).

  // Check 8: Fuel
  wait 0.4.
  local fuelStatus is 0.
  local pctLF is 0.
  if maxLF > 0 { set pctLF to round(totalLF / maxLF * 100). }
  local fuelDesc is "Liquid Fuel: " + pctLF + "% full (" + round(totalLF) + "/" + round(maxLF) + ")".
  local fuelRemedy is "Fill all liquid fuel and oxidizer tanks.".
  if maxLF = 0 or maxOX = 0 or totalLF < 10 or totalOX < 10 {
    set fuelStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Liquid Fuel/Oxidizer", 2, fuelDesc, fuelRemedy).
  } else if totalLF / maxLF < 0.95 or totalOX / maxOX < 0.95 {
    set fuelStatus to 1.
    set totalWarnings to totalWarnings + 1.
    updateReportPanel("Liquid Fuel/Oxidizer", 1, fuelDesc, fuelRemedy).
  }
  
  local fuelStr is "".
  if totalLF > 1000 {
    set fuelStr to round(totalLF/1000, 1) + "k LF".
  } else {
    set fuelStr to round(totalLF) + " LF".
  }
  printCheckResult("Liquid Fuel/Oxidizer", fuelStatus, fuelStr + " (" + pctLF + "%)", 12).

  // Check 9: Delta-V
  wait 0.4.
  local deltavStatus is 0.
  local pctDeltav is round(totalDeltav / reqDeltav * 100).
  local deltavDesc is "Delta-V: " + round(totalDeltav) + "/" + reqDeltav + " req (" + pctDeltav + "%)".
  local deltavRemedy is "Add fuel capacity or use efficient engines.".
  if totalDeltav < reqDeltav {
    set deltavStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Total Mission dV", 2, deltavDesc, deltavRemedy).
  } else if totalDeltav < 6200 {
    set deltavStatus to 1.
    set totalWarnings to totalWarnings + 1.
    updateReportPanel("Total Mission dV", 1, deltavDesc, deltavRemedy).
  }
  printCheckResult("Total Mission dV", deltavStatus, round(totalDeltav) + " m/s (" + pctDeltav + "%)", 13).

  // Check 10: TWR
  wait 0.4.
  local twrStatus is 0.
  local pctTWR is round(launchTwr / reqTWR * 100).
  local twrDesc is "Launch TWR: " + round(launchTwr, 2) + "/" + reqTWR + " req (" + pctTWR + "%)".
  local twrRemedy is "Add boosters/engines or reduce mass.".
  if launchTwr < reqTWR {
    set twrStatus to 2.
    set totalErrors to totalErrors + 1.
    updateReportPanel("Launch TWR (Pad)", 2, twrDesc, twrRemedy).
  } else if launchTwr > 2.2 {
    set twrStatus to 1.
    set totalWarnings to totalWarnings + 1.
    set twrRemedy to "TWR high! Consider limiting launch throttle.".
    updateReportPanel("Launch TWR (Pad)", 1, twrDesc, twrRemedy).
  }
  printCheckResult("Launch TWR (Pad)", twrStatus, "TWR: " + round(launchTwr, 2) + " (" + pctTWR + "%)", 14).

  // Clear prompt status line
  print "                                                " at (1, 22).

  // -------------------------------------------
  // 7. Prompt User
  // -------------------------------------------
  if totalErrors > 0 {
    print "| STATUS: CRITICAL FAILURES! OVERRIDE? [Y] / [N]   |" at (0,22).
    
    terminal:input:clear().
    until false {
      if terminal:input:haschar {
        local ch is terminal:input:getchar():toLower().
        if ch = "y" {
          print "| STATUS: MISSION OVERRIDDEN BY PILOT. LAUNCHING.  |" at (0,22).
          wait 1.5.
          return true.
        }
        if ch = "n" {
          print "| STATUS: MISSION ABORTED. SHUTTING DOWN SEQUENCER.|" at (0,22).
          wait 1.5.
          return false.
        }
      }
      wait 0.1.
    }
  } else if totalWarnings > 0 {
    print "| STATUS: WARNINGS DETECTED. PROCEED? [Y] / [N]     |" at (0,22).
    
    terminal:input:clear().
    until false {
      if terminal:input:haschar {
        local ch is terminal:input:getchar():toLower().
        if ch = "y" {
          print "| STATUS: ALL OK. PROCEEDING TO LAUNCH IN 3S...   |" at (0,22).
          wait 3.
          return true.
        }
        if ch = "n" {
          print "| STATUS: MISSION ABORTED BY USER.                 |" at (0,22).
          wait 1.5.
          return false.
        }
      }
      wait 0.1.
    }
  } else {
    print "| STATUS: ALL SYSTEMS GO! PRESS [Y] TO LAUNCH      |" at (0,22).
    terminal:input:clear().
    until false {
      if terminal:input:haschar {
        local ch is terminal:input:getchar():toLower().
        if ch = "y" {
          print "| STATUS: LAUNCH COMMENCING IN 3S...               |" at (0,22).
          wait 3.
          return true.
        }
      }
      wait 0.1.
    }
  }
}
