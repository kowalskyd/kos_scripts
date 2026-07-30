//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 NAV2 & FRONTIER EXPLORATION LIBRARY FOR kOS
// (Dynamic Gravity Scaling, Surface Normal Gradient Engine,
//  Positive Ridge Perpendicular Alignment, Negative Crater Drop-off Detection)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/rover.ks").

global rosVisitedSectors is list().
global rosBlacklistedSectors is list().
global rosCurrentFrontier is 0.
global rosCostmap is list().
global rosBestOffset is 0.
global rosLowestCost is 0.
global rosCurrentStatus is "Initializing ROS 2 Nav2 Engine...".
global rosZoneAnchorGeo is 0.
global rosActiveTargetGeo is 0.

// Blacklists an unnavigable sector key (ocean, steep wall, or unreachable target)
global function rosBlacklistSector {
  parameter key.
  parameter reason is "Hazard / Unreachable".
  if not rosBlacklistedSectors:contains(key) {
    rosBlacklistedSectors:add(key).
  }
}

// Helper to pad/truncate text to exact 50-char terminal width
global function padRight {
  parameter str, length is 50.
  local padded is "" + str.
  if padded:length > length {
    return padded:substring(0, length).
  }
  until padded:length >= length {
    set padded to padded + " ".
  }
  return padded.
}

//_________________________________________________
// 1. DYNAMIC GRAVITY SCALING HELPERS
//_________________________________________________

// Calculates local surface gravity (m/s^2)
global function rosGetSurfaceG {
  return ship:body:mu / (ship:body:radius^2).
}

// Calculates gravity ratio relative to Earth/Kerbin (1.0 = 9.81 m/s^2)
global function rosGetGravityRatio {
  return rosGetSurfaceG() / 9.81.
}

// Dynamic maximum climb angle scaled by surface gravity
// Low gravity (Minmus ~0.05g) -> max climb ~20 deg
// Standard gravity (Kerbin 1.0g) -> max climb up to 24 deg
global function rosGetMaxClimbAngle {
  local gRatio is rosGetGravityRatio().
  return max(20.0, min(25.0, 18.0 + (6.0 * gRatio))).
}

// Dynamic maximum safe speed scaled by sqrt(gravity ratio)
global function rosGetDynamicMaxSpeed {
  parameter baseSpeed is 5.0.
  local gFactor is sqrt(max(0.1, rosGetGravityRatio())).
  local bodyCap is max(1.5, min(baseSpeed, baseSpeed * gFactor)).
  return bodyCap.
}

//_________________________________________________
// 2. TERRAIN SURFACE NORMAL & GRADIENT CALCULATOR
//_________________________________________________

// Calculates local surface normal vector and steepest gradient direction at offset
global function rosGetTerrainNormalAndGradient {
  parameter fwdOffset.
  parameter sideOffset.
  parameter delta is 1.5. // Probing distance for gradient cross-product

  local foreVec is ship:facing:forevector.
  local starVec is ship:facing:starvector.
  local basePos is ship:position + (foreVec * fwdOffset) + (starVec * sideOffset).

  local northVec is ship:north:vector.
  local eastVec is heading(90,0):vector.

  // Probe 4 surrounding points to compute cross-product vectors
  local posNorth is basePos + (northVec * delta).
  local posSouth is basePos - (northVec * delta).
  local posEast  is basePos + (eastVec * delta).
  local posWest  is basePos - (eastVec * delta).

  local geoN is ship:body:geopositionof(posNorth).
  local geoS is ship:body:geopositionof(posSouth).
  local geoE is ship:body:geopositionof(posEast).
  local geoW is ship:body:geopositionof(posWest).

  local vecNS is (geoN:position - geoS:position):normalized.
  local vecEW is (geoE:position - geoW:position):normalized.

  // Surface Normal Vector = Cross Product of East-West and South-North vectors
  local normalVec is vcrs(vecEW, vecNS):normalized.
  if vAng(normalVec, ship:up:vector) > 90 {
    set normalVec to -normalVec.
  }

  // Terrain inclination angle relative to gravity up vector
  local slopeAngle is vAng(normalVec, ship:up:vector).

  // Compass heading of steepest uphill gradient (safely handle flat ground)
  local projNormal is vxcl(ship:up:vector, normalVec).
  local gradientHDG is ship:heading.
  if slopeAngle > 0.1 and projNormal:mag > 0.001 {
    set projNormal to projNormal:normalized.
    set gradientHDG to mod(arctan2(vDot(projNormal, eastVec), vDot(projNormal, northVec)) + 360, 360).
  }

  return list(normalVec, slopeAngle, gradientHDG).
}

//_________________________________________________
// 3. ROS 2 MULTI-LAYER COSTMAP ENGINE
//_________________________________________________

// Samples local terrain grid, applying Ridge, Negative Drop-off, SCANsat, and LaserDist layers
global function rosSampleCostmap {
  parameter forwardSpan is 35.
  parameter sideSpan is 14.

  local grid is list().
  local roverGeo is ship:geoposition.
  local roverH is roverGeo:terrainheight.
  local foreVec is ship:facing:forevector.
  local starVec is ship:facing:starvector.

  local maxClimbAngle is rosGetMaxClimbAngle().

  // Check LaserDist addon if installed safely (gate to 35m local costmap horizon)
  local laserDistVal is 999.
  if defined addons and addons:hasSuffix("laserdist") {
    if addons:laserdist:available and addons:laserdist:all:length > 0 {
      local lPart is addons:laserdist:all[0].
      if lPart:hasSuffix("distance") and lPart:distance > 0 and lPart:distance < 35.0 {
        set laserDistVal to lPart:distance.
      }
    }
  }

  local fwdSteps is 5.
  local sideSteps is 5.
  local dFwd is forwardSpan / fwdSteps.
  local dSide is (sideSpan * 2) / (sideSteps - 1).

  from { local fwdIdx is 1. } until fwdIdx > fwdSteps step { set fwdIdx to fwdIdx + 1. } do {
    local distFwd is fwdIdx * dFwd.
    from { local sideIdx is 0. } until sideIdx >= sideSteps step { set sideIdx to sideIdx + 1. } do {
      local distSide is -sideSpan + (sideIdx * dSide).

      local cellPos is ship:position + (foreVec * distFwd) + (starVec * distSide).
      local cellGeo is ship:body:geopositionof(cellPos).
      local cellH is cellGeo:terrainheight.
      local hDiff is cellH - roverH.
      local distTotal is sqrt(distFwd^2 + distSide^2).

      // Calculate step drop relative to previous 7m row
      local prevCellH is roverH.
      if fwdIdx > 1 {
        local prevIdx is (fwdIdx - 2) * sideSteps + sideIdx.
        set prevCellH to grid[prevIdx]["cellH"].
      }
      local stepDrop is cellH - prevCellH.

      // Surface Normal & Gradient computation
      local normData is rosGetTerrainNormalAndGradient(distFwd, distSide).
      local slopeAngle is normData[1].
      local gradientHDG is normData[2].

      // Macro slope from SCANsat if installed
      local macroSlope is getSCANsatSlope(cellGeo:lat, cellGeo:lng).

      // Hazard Classification
      local isImpassable is false.
      local hazardType is "CLEAR".

      // 1. NEGATIVE OBSTACLE LAYER (True Cliffs & Crater Drop-offs)
      // Step drop > 2.2m over 7m or step slope < -27 deg indicates a true vertical cliff drop-off
      if stepDrop < -2.2 or (stepDrop / dFwd) < -0.45 {
        set isImpassable to true.
        set hazardType to "NEGATIVE_DROP".
      }
      // 2. POSITIVE RIDGE LAYER (Steep Ridge Wall vs Climbable Crest)
      // Positive ridge hazards ONLY apply to UPHILL climbs (hDiff > 0.3m or stepDrop > 0.2m)
      local isUphill is (hDiff > 0.3 or stepDrop > 0.2).

      if isUphill and (slopeAngle > maxClimbAngle or macroSlope > (maxClimbAngle + 4)) {
        set isImpassable to true.
        set hazardType to "STEEP_RIDGE".
      } else if isUphill and slopeAngle > 6.0 {
        set hazardType to "CLIMBABLE_RIDGE".
      }

      // 3. LASERDIST LAYER (Physical obstacle detected within 35m horizon)
      if laserDistVal < 35.0 and distFwd >= (laserDistVal - 2.0) and distFwd <= (laserDistVal + 3.0) and abs(distSide) < 3.0 {
        set isImpassable to true.
        set hazardType to "PHYSICAL_OBSTACLE".
      }

      // Cost Formulation
      local cellCost is (slopeAngle * 2.5) + (abs(hDiff) * 3.5) + (abs(distSide) * 0.15) + (macroSlope * 1.5).
      if isImpassable { set cellCost to 99999. }

      local cell is lexicon().
      set cell["fwd"] to distFwd.
      set cell["side"] to distSide.
      set cell["geo"] to cellGeo.
      set cell["cellH"] to cellH.
      set cell["slope"] to slopeAngle.
      set cell["hDiff"] to hDiff.
      set cell["gradientHDG"] to gradientHDG.
      set cell["hazard"] to hazardType.
      set cell["cost"] to cellCost.
      set cell["impassable"] to isImpassable.

      grid:add(cell).
    }
  }

  // Cost Inflation Pass: Inflate cost of cells adjacent to impassable hazards
  for cell in grid {
    if not cell["impassable"] {
      for checkCell in grid {
        if checkCell["impassable"] {
          local dCell is sqrt((cell["fwd"] - checkCell["fwd"])^2 + (cell["side"] - checkCell["side"])^2).
          if dCell < 6.0 {
            set cell["cost"] to cell["cost"] + (25.0 * (6.0 - dCell)).
          }
        }
      }
    }
  }

  return grid.
}

//_________________________________________________
// 4. DYNAMIC WINDOW APPROACH (DWA) & RIDGE ALIGNMENT
//_________________________________________________

// Selects candidate heading vector enforcing Perpendicular Ridge Alignment & Contour Bypass
global function rosCalculateDwaPath {
  parameter targetGeo.
  parameter grid.

  local baseHDG is targetGeo:heading.
  local candidateOffsets is list(0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75).

  local bestHDG is baseHDG.
  local bestOffset is 0.
  local lowestCost is 999999.
  local forcedGradientAlign is false.

  // First, check if rover is directly encountering a climbable ridge ahead
  local climbableCount is 0.
  local avgGradientHDG is 0.
  for cell in grid {
    if cell["fwd"] < 15 and cell["hazard"] = "CLIMBABLE_RIDGE" {
      set climbableCount to climbableCount + 1.
      set avgGradientHDG to avgGradientHDG + cell["gradientHDG"].
    }
  }

  // RULE 1: PERPENDICULAR RIDGE ALIGNMENT
  // If climbing a manageable ridge, align heading straight up the gradient vector (0 deg roll angle)
  if climbableCount >= 3 {
    set avgGradientHDG to avgGradientHDG / climbableCount.
    local angleToGoal is abs(mod(avgGradientHDG - baseHDG + 540, 360) - 180).
    if angleToGoal < 60.0 {
      set bestHDG to avgGradientHDG.
      set bestOffset to mod(avgGradientHDG - baseHDG + 540, 360) - 180.
      set lowestCost to 15.0.
      set forcedGradientAlign to true.
    }
  }

  if not forcedGradientAlign {
    for offset in candidateOffsets {
      local testHDG is mod(baseHDG + offset + 360, 360).
      local testVec is heading(testHDG, 0):vector.

      local sumCost is 0.
      local cellCount is 0.
      local isSectorBlocked is false.

      for cell in grid {
        local cellDirVec is cell["geo"]:position:normalized.
        local angleToCell is vAng(testVec, cellDirVec).

        if angleToCell < 22.0 {
          if cell["impassable"] {
            set isSectorBlocked to true.
            break.
          }
          set sumCost to sumCost + cell["cost"].
          set cellCount to cellCount + 1.
        }
      }

      if not isSectorBlocked and cellCount > 0 {
        local avgCost is sumCost / cellCount.
        local changeFromCurrent is abs(offset - rosBestOffset).
        local totalCost is avgCost + (abs(offset) * 1.8) + (changeFromCurrent * 0.8).

        if totalCost < lowestCost {
          set lowestCost to totalCost.
          set bestHDG to testHDG.
          set bestOffset to offset.
        }
      }
    }
  }

  // Fallback: If forward path blocked by negative drop-off or steep ridge, initiate contour detour turn
  if lowestCost >= 90000 {
    set bestHDG to mod(ship:heading + 80, 360).
    set bestOffset to 80.
  }

  // Flag chosen path cells for HUD map visualization
  local chosenVec is heading(bestHDG, 0):vector.
  for cell in grid {
    local cellDirVec is cell["geo"]:position:normalized.
    if vAng(chosenVec, cellDirVec) < 22.0 {
      set cell["isPath"] to true.
    }
  }

  return list(bestHDG, lowestCost, bestOffset, forcedGradientAlign).
}

//_________________________________________________
// 5. ROS 2 FRONTIER-BASED EXPLORATION ENGINE
//_________________________________________________

// Calculates gravity-scaled sector step size in meters (Kerbin 200m -> Mun 100m -> Minmus 75m)
global function rosGetGravitySectorStep {
  local gRatio is rosGetGravityRatio().
  local stepSize is round(max(75.0, min(200.0, 200.0 * sqrt(max(0.05, gRatio))))).
  return stepSize.
}

// Converts lat/lng into a coarse sector grid key prefixed by body name & dynamic step size
global function rosGetSectorKey {
  parameter geo.
  local bodyName is ship:body:name.
  local stepSize is rosGetGravitySectorStep().
  local degStep is (stepSize / ship:body:radius) * (180 / constant:pi).
  local latIdx is round(geo:lat / degStep).
  local lngIdx is round(geo:lng / degStep).
  return bodyName + "_" + latIdx + "_" + lngIdx.
}

// Macro Zone Highway Selector: Target entry cell of the next Zone to the East
global function rosSelectFrontierTarget {
  parameter currentGeo.
  parameter scanRadius is 0. // unused

  local stepSize is rosGetGravitySectorStep().
  local zoneSize is stepSize * 5.

  if rosZoneAnchorGeo = 0 {
    set rosZoneAnchorGeo to currentGeo.
  }

  local currentKey is rosGetSectorKey(currentGeo).
  if not rosVisitedSectors:contains(currentKey) {
    rosVisitedSectors:add(currentKey).
  }

  local bodyRadius is ship:body:radius.
  local maxClimb is rosGetMaxClimbAngle().

  // Primary Highway Target: Next Zone East (zoneSize meters East of current zone anchor)
  local shiftN is 0.
  local shiftE is zoneSize.

  local latDeg is (shiftN / bodyRadius) * (180 / constant:pi).
  local lngDeg is (shiftE / (bodyRadius * cos(rosZoneAnchorGeo:lat))) * (180 / constant:pi).
  local eastZoneGeo is latlng(rosZoneAnchorGeo:lat + latDeg, rosZoneAnchorGeo:lng + lngDeg).
  local eastZoneKey is rosGetSectorKey(eastZoneGeo).

  // 3-Point Elevation & Water Path Probe toward East Zone
  local pathClear is true.
  for stepFrac in list(0.33, 0.66, 1.0) {
    local pN is shiftN * stepFrac.
    local pE is shiftE * stepFrac.
    local pLat is (pN / bodyRadius) * (180 / constant:pi).
    local pLng is (pE / (bodyRadius * cos(currentGeo:lat))) * (180 / constant:pi).
    local pGeo is latlng(currentGeo:lat + pLat, currentGeo:lng + pLng).
    if pGeo:terrainheight <= 5.0 {
      set pathClear to false.
      break.
    }
  }

  // If direct East path is blocked by ocean/mountains, shift target 1 cell North or South
  if not pathClear or eastZoneGeo:terrainheight <= 5.0 or getSCANsatSlope(eastZoneGeo:lat, eastZoneGeo:lng) >= (maxClimb + 3.0) {
    rosBlacklistSector(eastZoneKey, "Water Body / Mountain Risk").
    
    // Probe North (+1 cell) vs South (-1 cell) detours
    local northLatDeg is (stepSize / bodyRadius) * (180 / constant:pi).
    local southLatDeg is ((-stepSize) / bodyRadius) * (180 / constant:pi).
    local northGeo is latlng(eastZoneGeo:lat + northLatDeg, eastZoneGeo:lng).
    local southGeo is latlng(eastZoneGeo:lat + southLatDeg, eastZoneGeo:lng).

    if northGeo:terrainheight > southGeo:terrainheight {
      return northGeo.
    } else {
      return southGeo.
    }
  }

  return eastZoneGeo.
}

// 2.5D Cell-Stepping Detour: On barrier abort, shifts 1 cell North or South to bypass obstacle
global function rosCellSteppingDetour {
  local stepSize is rosGetGravitySectorStep().
  local currentGeo is ship:geoposition.
  local bodyRadius is ship:body:radius.

  // Probe North (+1 cell) vs South (-1 cell) stepping targets
  local nLatDeg is (stepSize / bodyRadius) * (180 / constant:pi).
  local sLatDeg is ((-stepSize) / bodyRadius) * (180 / constant:pi).

  local nGeo is latlng(currentGeo:lat + nLatDeg, currentGeo:lng).
  local sGeo is latlng(currentGeo:lat + sLatDeg, currentGeo:lng).

  local nH is nGeo:terrainheight.
  local sH is sGeo:terrainheight.

  local bestHDG is 0. // North
  local detourGeo is nGeo.

  if sH > nH {
    set bestHDG to 180. // South
    set detourGeo to sGeo.
  }

  hudText("2.5D Cell Detour: Stepping 1 Cell North/South to bypass barrier...", 4, 2, 25, rgb(0.2, 0.9, 0.4), true).

  executePointTurn(bestHDG, "2.5D Cell Stepping Turn").
  rosDriveToCoordinates(detourGeo:lat, detourGeo:lng, 3.5, 8.0, false).
}

//_________________________________________________
// 6. ROS 2 NAV2 TELEMETRY & HUD ENGINE
//_________________________________________________

// Displays live ROS 2 Nav2 telemetry HUD with ASCII radar costmap
global function rosUpdateTelemetry {
  parameter targetGeo is 0.
  parameter statusMsg is "".

  local isShipGeo is false.
  if targetGeo:isType("GeoCoordinates") {
    if abs(targetGeo:lat - ship:geoposition:lat) < 0.0001 and abs(targetGeo:lng - ship:geoposition:lng) < 0.0001 {
      set isShipGeo to true.
    }
  }

  if targetGeo = 0 or isShipGeo {
    if rosActiveTargetGeo <> 0 {
      set targetGeo to rosActiveTargetGeo.
    } else {
      set targetGeo to ship:geoposition.
    }
  } else {
    set rosActiveTargetGeo to targetGeo.
  }

  // Continuous Visited Sector Painting: Log current position to rosVisitedSectors
  local currentSectorKey is rosGetSectorKey(ship:geoposition).
  if not rosVisitedSectors:contains(currentSectorKey) {
    rosVisitedSectors:add(currentSectorKey).
  }

  local curSpd is ship:groundspeed.
  local currentBiome is getCurrentBiome().
  local distTarget is targetGeo:distance.
  local targetBearing is round(targetGeo:bearing, 1).

  local currentPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
  local currentRoll  is 90 - vAng(ship:up:vector, ship:facing:starvector).

  local surfaceG is rosGetSurfaceG().
  local maxClimbAngle is rosGetMaxClimbAngle().
  local dynamicSpeedCap is rosGetDynamicMaxSpeed(5.0).

  local ecData is getECInfo().
  local ecCur is ecData[0].
  local ecMax is ecData[1].
  local ecPct is 100.
  if ecMax > 0 { set ecPct to round((ecCur / ecMax) * 100). }

  local negativeCount is 0.
  local ridgeCount is 0.
  for cell in rosCostmap {
    if cell["hazard"] = "NEGATIVE_DROP" { set negativeCount to negativeCount + 1. }
    else if cell["hazard"]:contains("RIDGE") { set ridgeCount to ridgeCount + 1. }
  }

  local pathText is "Direct".
  if rosBestOffset > 0 { set pathText to "Contour R (+" + rosBestOffset + "d)". }
  else if rosBestOffset < 0 { set pathText to "Contour L (" + rosBestOffset + "d)". }

  local macroSlope is 0.
  if defined addons and addons:hasSuffix("scansat") {
    set macroSlope to getSCANsatSlope(ship:geoposition:lat, ship:geoposition:lng).
  }

  local scansatShort is "CONNECTED (" + round(macroSlope, 1) + " deg)".
  if not (defined addons and addons:hasSuffix("scansat")) {
    set scansatShort to "NOT INSTALLED".
  }

  local laserDistShort is "kOS DEM Raycast".
  if defined addons and addons:hasSuffix("laserdist") {
    if addons:laserdist:available and addons:laserdist:all:length > 0 {
      local lPart is addons:laserdist:all[0].
      if lPart:hasSuffix("distance") and lPart:distance > 0 and lPart:distance < 900 {
        set laserDistShort to round(lPart:distance, 1) + "m Hit".
      } else {
        set laserDistShort to "Clear (>900m)".
      }
    }
  }

  local currentPitch is 90 - vAng(ship:up:vector, ship:facing:forevector).
  local currentRoll  is 90 - vAng(ship:up:vector, ship:facing:starvector).

  local stabilityTag is "[STABLE]".
  if abs(currentRoll) > 15 or abs(currentPitch) > 18 { set stabilityTag to "[HAZARD]". }

  print "==================================================" at (0, 0).
  print "=== ROS 2 NAV2 AUTONAV MISSION CONTROL ===" at (0, 1).
  print "--------------------------------------------------" at (0, 2).
  print padRight("Target:   [Lat:" + round(targetGeo:lat,2) + ", Lng:" + round(targetGeo:lng,2) + "] (" + round(distTarget,1) + "m / " + targetBearing + "d)", 50) at (0, 3).
  print padRight("Biome:    " + currentBiome + " | Surface G: " + round(surfaceG,2) + "m/s^2 (Max: " + round(maxClimbAngle,1) + "d)", 50) at (0, 4).
  print padRight("SCANsat:  " + scansatShort, 50) at (0, 5).
  print padRight("Laser:    " + laserDistShort, 50) at (0, 6).
  print padRight("Speed:    " + round(curSpd,1) + "/" + round(dynamicSpeedCap,1) + " m/s | EC Charge: " + ecPct + "%", 50) at (0, 7).
  print padRight("Angles:   Pitch: " + round(currentPitch,1) + "d | Roll: " + round(currentRoll,1) + "d " + stabilityTag, 50) at (0, 8).
  print padRight("Corridor: " + pathText + " (Cost: " + round(rosLowestCost,1) + ")", 50) at (0, 9).
  print padRight("Hazards:  " + negativeCount + " drop-offs, " + ridgeCount + " steep ridges", 50) at (0, 10).
  print "--------------------------------------------------" at (0, 11).
  print padRight("ROS 2 LOCAL COSTMAP RADAR (35m Ahead):", 50) at (0, 12).

  if rosCostmap:length >= 25 {
    from { local row is 4. } until row < 0 step { set row to row - 1. } do {
      local rowStr is "  [ ".
      from { local col is 0. } until col >= 5 step { set col to col + 1. } do {
        local cellIdx is row * 5 + col.
        local cell is rosCostmap[cellIdx].
        if cell["hazard"] = "NEGATIVE_DROP" {
          set rowStr to rowStr + "!  ".
        } else if cell["hazard"] = "STEEP_RIDGE" {
          set rowStr to rowStr + "^  ".
        } else if cell["impassable"] {
          set rowStr to rowStr + "#  ".
        } else if cell:haskey("isPath") and cell["isPath"] {
          set rowStr to rowStr + "*  ".
        } else if cell["hazard"] = "CLIMBABLE_RIDGE" {
          set rowStr to rowStr + "/  ".
        } else {
          set rowStr to rowStr + ".  ".
        }
      }
      set rowStr to rowStr + "]  " + ((row + 1) * 7) + "m".
      print padRight(rowStr, 50) at (0, 13 + (4 - row)).
    }
    print padRight("        [^]  Rover (Heading " + round(ship:heading, 1) + " deg)", 50) at (0, 18).
  } else {
    print padRight("  [ Local costmap scanning... ]", 50) at (0, 13).
    print padRight("", 50) at (0, 14).
    print padRight("", 50) at (0, 15).
    print padRight("", 50) at (0, 16).
    print padRight("", 50) at (0, 17).
    print padRight("        [^]  Rover", 50) at (0, 18).
  }

  print "--------------------------------------------------" at (0, 19).
  rosRenderGlobalFrontierMap(targetGeo).

  print "--------------------------------------------------" at (0, 28).
  if statusMsg <> "" {
    print padRight("Status: " + statusMsg, 50) at (0, 29).
  } else {
    print padRight("Status: Cruising", 50) at (0, 29).
  }
}

// Renders a 5x5 regional sector occupancy map around rover with side-by-side Zone Metrics
global function rosRenderGlobalFrontierMap {
  parameter targetGeo.

  local stepSize is rosGetGravitySectorStep().
  local zoneSize is stepSize * 5.
  local degStep is (stepSize / ship:body:radius) * (180 / constant:pi).

  local curGeo is ship:geoposition.
  local curLatIdx is round(curGeo:lat / degStep).
  local curLngIdx is round(curGeo:lng / degStep).

  local tgtLatIdx is round(targetGeo:lat / degStep).
  local tgtLngIdx is round(targetGeo:lng / degStep).

  local curBiome is getCurrentBiome().
  local distNextZone is round(targetGeo:distance, 1).

  // Right-side zone metrics lines (5 rows matching the 5 grid rows)
  local sideLines is list(
    "Zone Index:  #" + rosCurrentFrontier + " (" + ship:body:name + ")",
    "Zone Size:   " + round(zoneSize) + "m x " + round(zoneSize) + "m",
    "Next Target: " + distNextZone + "m (" + round(targetGeo:bearing,1) + "d)",
    "Sector Step: " + round(stepSize) + "m per cell",
    "Zone Biome:  " + curBiome
  ).

  local gridHeader is "GLOBAL MAP (" + round(zoneSize) + "m Grid):".
  print padRight(gridHeader + "   === ZONE METRICS ===", 50) at (0, 20).

  from { local rowIdx is 2. } until rowIdx < -2 step { set rowIdx to rowIdx - 1. } do {
    local latIdx is curLatIdx + rowIdx.
    local rowStr is "  | ".

    from { local colIdx is -2. } until colIdx > 2 step { set colIdx to colIdx + 1. } do {
      local lngIdx is curLngIdx + colIdx.
      local key is ship:body:name + "_" + latIdx + "_" + lngIdx.

      if rowIdx = 0 and colIdx = 0 {
        set rowStr to rowStr + "@  ".
      } else if latIdx = tgtLatIdx and lngIdx = tgtLngIdx {
        set rowStr to rowStr + "O  ".
      } else if rosBlacklistedSectors:contains(key) {
        set rowStr to rowStr + "!  ".
      } else if rosVisitedSectors:contains(key) {
        set rowStr to rowStr + "X  ".
      } else {
        set rowStr to rowStr + "?  ".
      }
    }
    set rowStr to rowStr + "|".

    local lineIndex is 2 - rowIdx.
    local sideText is sideLines[lineIndex].
    local fullRowStr is rowStr + " " + sideText.

    print padRight(fullRowStr, 50) at (0, 21 + lineIndex).
  }

  print padRight("  [@]Rover [X]Visited [O]Target [!]Barrier [?]Frontier", 50) at (0, 27).
}

//_________________________________________________
// 7. MAIN ROS 2 NAV2 DRIVE CONTROLLER
//_________________________________________________

// Drives vessel to target coordinate using ROS 2 Nav2 costmaps and DWA local planner
global function rosDriveToCoordinates {
  parameter targetLat.
  parameter targetLng.
  parameter baseSpeed is 5.0.
  parameter arrivalRadius is 15.0.
  parameter autoCollectBiomes is true.

  waitForSunlight().
  waitForFullEC().

  local targetGeo is latlng(targetLat, targetLng).
  local minDistToTarget is targetGeo:distance.
  local timeOfBestDist is time:seconds.
  local slipTimer is 0.

  if lastScienceBiome = "" {
    set lastScienceBiome to getCurrentBiome().
  }

  brakes off.
  sas on.

  local targetThrottle is 0.
  lock wheelsteering to targetGeo.
  lock wheelthrottle to targetThrottle.

  rosUpdateTelemetry(targetGeo, "Initializing local costmap...").

  until false {
    // 1. Instant 35m Local Costmap Radar Probing
    set rosCostmap to rosSampleCostmap(35, 14).

    // 2. Airborne check
    if not (ship:status = "LANDED" or ship:status = "SPLASHED") {
      handleAirborne().
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // 3. Power & Daylight check
    local ecCheck is getECInfo().
    if (ecCheck[1] > 0 and (ecCheck[0] / ecCheck[1]) < 0.15) or not isSunUp() {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      waitForSunlight().
      waitForFullEC().
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // 4. Science Biome Crossing Check
    local currentBiome is getCurrentBiome().
    if autoCollectBiomes and lastScienceBiome <> "" and currentBiome <> lastScienceBiome {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      runScienceExperiments().
      set lastScienceBiome to currentBiome.
      brakes off.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    local dist is targetGeo:distance.
    if dist < (minDistToTarget - 4) {
      set minDistToTarget to dist.
      set timeOfBestDist to time:seconds.
    }

    // 5. Goal Arrival Condition
    if dist < arrivalRadius {
      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      wait until ship:groundspeed < 0.2.
      if autoCollectBiomes {
        runScienceExperiments().
      }
      return true.
    }

    // 6. Stagnant Progress / Goal Unreachability Blacklisting
    local timeStagnant is time:seconds - timeOfBestDist.
    if (timeStagnant > 35 and dist < 450) or (timeStagnant > 20 and dist < 150) {
      local tgtKey is rosGetSectorKey(targetGeo).
      rosBlacklistSector(tgtKey, "Unreachable Goal").
      hudText("Goal Unreachable! Blacklisted Sector " + tgtKey + ", Turning Inland...", 4, 2, 25, rgb(1, 0.4, 0), true).

      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      wait until ship:groundspeed < 0.2.
      return false.
    }

    // 7. Bug2 Continuous Barrier & Shoreline Detection
    // Only triggers if 5+ cells in the CENTER driving corridor (abs(side) <= 7m) are blocked
    // OR if DWA cannot find any open corridor (rosLowestCost >= 90000)
    local centerBarrierCount is 0.
    for cell in rosCostmap {
      if cell["fwd"] <= 22 and abs(cell["side"]) <= 7.0 and (cell["hazard"] = "NEGATIVE_DROP" or cell["hazard"] = "STEEP_RIDGE") {
        set centerBarrierCount to centerBarrierCount + 1.
      }
    }
    if centerBarrierCount >= 5 or (rosLowestCost >= 90000 and centerBarrierCount >= 3) {
      local tgtKey is rosGetSectorKey(targetGeo).
      rosBlacklistSector(tgtKey, "Continuous Barrier Wall").
      hudText("Continuous Barrier Detected! Blacklisting Sector & Turning Inland...", 4, 2, 25, rgb(1, 0.2, 0.2), true).

      local escapeHDG is mod(ship:heading + 180, 360).
      executePointTurn(escapeHDG, "Perimeter Barrier Escape").

      brakes on.
      set targetThrottle to 0.
      unlock wheelsteering.
      unlock wheelthrottle.
      return false.
    }

    // 8. Pitch & Roll Hazard Enforcement
    local tiltHazard is checkTiltHazards().
    if tiltHazard[0] {
      if tiltHazard[1]:contains("ROLL") {
        executeRollHazardRecovery(tiltHazard[2]).
        lock wheelsteering to targetGeo.
        lock wheelthrottle to targetThrottle.
      }
    }

    // 9. Traction Loss & Wheel Slip Check
    set slipTimer to checkWheelSlip(targetThrottle, slipTimer).
    if slipTimer > 3.0 {
      executeSlipRecovery().
      set slipTimer to 0.
      lock wheelsteering to targetGeo.
      lock wheelthrottle to targetThrottle.
    }

    // 10. Execute DWA Local Planner Path Choice
    local dwaEval is rosCalculateDwaPath(targetGeo, rosCostmap).
    local desiredHDG is dwaEval[0].
    set rosLowestCost to dwaEval[1].
    set rosBestOffset to dwaEval[2].
    local isGradAlign is dwaEval[3].

    // 11. Continuous Wheel Steering & Point Turn Execution
    lock wheelsteering to desiredHDG.

    local hdgDev is abs(mod(desiredHDG - ship:heading + 540, 360) - 180).
    if (hdgDev > 36.0 and ship:groundspeed < 1.5) or (isGradAlign and hdgDev > 25.0) {
      local turnMsg is "ROS 2 Nav2 Point Turn".
      if isGradAlign { set turnMsg to "Perpendicular Ridge Align". }
      executePointTurn(desiredHDG, turnMsg).
      lock wheelsteering to desiredHDG.
      lock wheelthrottle to targetThrottle.
    }

    // 12. Dynamic Low-Gravity Speed Control & Proportional Throttle
    local dynamicMaxSpd is rosGetDynamicMaxSpeed(baseSpeed).
    local curSpd is ship:groundspeed.
    local safeSpd is dynamicMaxSpd.
    local gRatio is rosGetGravityRatio().

    if tiltHazard[3] > 10 { set safeSpd to min(safeSpd, 1.5). }

    // Proportional throttle cap scaled by surface gravity (prevents wheelspin on Mun/Minmus)
    local maxAllowedThrottle is min(1.0, max(0.12, 0.45 * gRatio)).

    // Lateral drift check
    local driftAngle is 0.
    if curSpd > 0.4 { set driftAngle to vAng(ship:velocity:surface, ship:facing:forevector). }

    if curSpd > (safeSpd + 0.8) or (curSpd > 0.6 and driftAngle > 14.0) {
      brakes on.
      set targetThrottle to 0.
    } else if curSpd < safeSpd {
      brakes off.
      set targetThrottle to min(maxAllowedThrottle, (safeSpd - curSpd) * 0.20 + 0.05).
    } else {
      brakes off.
      set targetThrottle to 0.
    }

    rosUpdateTelemetry(targetGeo, "Cruising (" + round(curSpd,1) + "/" + round(safeSpd,1) + " m/s)").
    wait 0.05.
  }

  return true.
}

// Executes a 150m inland escape drive away from water/walls to break barrier deadlock loops
global function rosEscapeInland {
  parameter escapeDist is 150.

  local currentGeo is ship:geoposition.
  local bodyRadius is ship:body:radius.
  local bestHDG is mod(ship:heading + 180, 360).
  local maxH is -99999.

  // Probe 8 directions to find heading with highest inland terrain height (away from water)
  for ang in list(0, 45, 90, 135, 180, 225, 270, 315) {
    local latDeg is ((escapeDist * cos(ang)) / bodyRadius) * (180 / constant:pi).
    local lngDeg is ((escapeDist * sin(ang)) / (bodyRadius * cos(currentGeo:lat))) * (180 / constant:pi).
    local pGeo is latlng(currentGeo:lat + latDeg, currentGeo:lng + lngDeg).
    if pGeo:terrainheight > maxH {
      set maxH to pGeo:terrainheight.
      set bestHDG to ang.
    }
  }

  hudText("Driving " + escapeDist + "m Inland Away From Barrier (HDG " + round(bestHDG) + ")...", 5, 2, 25, rgb(0.2, 0.9, 0.4), true).

  local latDeg is ((escapeDist * cos(bestHDG)) / bodyRadius) * (180 / constant:pi).
  local lngDeg is ((escapeDist * sin(bestHDG)) / (bodyRadius * cos(currentGeo:lat))) * (180 / constant:pi).
  local inlandGeo is latlng(currentGeo:lat + latDeg, currentGeo:lng + lngDeg).

  executePointTurn(bestHDG, "Inland Escape Turn").
  rosDriveToCoordinates(inlandGeo:lat, inlandGeo:lng, 5.0, 15.0, false).
}
