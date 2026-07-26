// =============================================
//      KAL-9000 AUTOMATED SCIENCE LIBRARY
// =============================================
// Automatically deploys all operable science experiments,
// collects and stores the data in the Experiment Storage Unit (ESU),
// and resets reusable instruments (including Crew Reports).
// 
global collectScience is false.

// Interactively prompts user at mission start to enable or disable science collection
global function promptScienceOption {
  print " ".
  print "---------------------------------------".
  print " SCIENCE COLLECTION OPTION".
  print " Enable automated science collection?".
  print "   [Y] Yes - Collect, store in ESU, & reset".
  print "   [N] No  - Fast Mission Mode (skip science)".
  print " Press Y or N: ".

  local choice is terminal:input:getchar().
  if choice = "y" or choice = "Y" {
    set collectScience to true.
    print " >> Science Collection: ENABLED".
  } else {
    set collectScience to false.
    print " >> Science Collection: DISABLED (Fast Mission)".
  }
  print "---------------------------------------".
  wait 1.5.
}

// Pauses execution on planetary surface to allow player EVA / surface operations
global function promptSurfaceEVAPause {
  parameter bodyName is "Mun".

  print " ".
  print "=======================================".
  print "   " + bodyName:toUpper() + " TOUCHDOWN COMPLETE".
  print "=======================================".
  print " Vessel is safely stationary on " + bodyName + " surface.".
  print " You can perform an EVA, plant flags, or collect extra science now.".
  print "---------------------------------------".
  print " Press ANY KEY in Terminal when ready for liftoff...".
  
  terminal:input:getchar().

  print " ".
  print " [OK] Liftoff confirmation received! Initiating ascent...".
  print "=======================================".
  wait 2.0.
}

global function doScience {
  parameter stageLabel is "Mission Science".

  // If science collection is disabled, skip execution immediately
  if not collectScience {
    return.
  }

  clearScreen.
  print "=======================================".
  print "     AUTOMATED SCIENCE COLLECTION      ".
  print "=======================================".
  print " Stage: " + stageLabel.
  print "---------------------------------------".

  hudText("SCIENCE: " + stageLabel, 3, 2, 20, rgb(0.2, 0.8, 1.0), false).

  // 1. Gather all experiment modules across vessel parts
  local expList is list().
  for p in ship:parts {
    for m in p:modules {
      if m = "ModuleScienceExperiment" {
        expList:add(p:getModule("ModuleScienceExperiment")).
      }
    }
  }

  if expList:length = 0 {
    print " [!] No science experiment modules found.".
    print "=======================================".
    wait 1.5.
    return.
  }

  print " Found " + expList:length + " science experiment module(s).".

  // 2. Deploy all operable experiments that don't currently hold data
  local deployedCount is 0.
  for exp in expList {
    if not exp:inoperable and not exp:hasdata {
      print "  -> Deploying: " + exp:part:title.
      exp:deploy().
      set deployedCount to deployedCount + 1.
    } else if exp:hasdata {
      print "  -> Data already present on: " + exp:part:title.
    } else if exp:inoperable {
      print "  -> Instrument inoperable: " + exp:part:title.
    }
  }

  if deployedCount > 0 {
    print " Waiting for experiments to complete observation...".
    wait 2.5.
  }

  // 3. Transfer all science data into Experiment Storage Unit (ESU)
  local containers is ship:modulesNamed("ModuleScienceContainer").
  if containers:length > 0 {
    print "---------------------------------------".
    print " Storing all data to Experiment Storage Unit...".
    for container in containers {
      if container:hasaction("collect all") {
        container:doAction("collect all", true).
      } else if container:hasevent("collect all") {
        container:doEvent("collect all").
      } else if container:hasevent("container: collect all") {
        container:doEvent("container: collect all").
      }
      wait 1.0.
    }
    print " [OK] All data stored in ESU! Sensors reset.".
    hudText("SCIENCE: All data stored in ESU & reset!", 3, 2, 20, rgb(0.2, 1.0, 0.4), false).
  } else {
    print " [!] WARNING: No ModuleScienceContainer (ESU) found.".
    print "     Data retained directly on sensor parts.".
  }

  print "=======================================".
  wait 2.0.
}
