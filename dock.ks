runOncePath("0:/lib/mnv.ks").
runOncePath("0:/lib/system.ks").
runOncePath("0:/lib/docking.ks").

wait 0.1.

// Check if we already have a target selected.
// If not, default to "Space Station 01" to match rdv.ks behavior.
if not HASTARGET {
  set target to VESSEL("Space Station 01").
}

if HASTARGET {
  clearScreen.
  print "=== Docking Mission Initiated ===".
  print "Target selected: " + target:name.
  print "Initializing automatic docking guidance...".
  wait 1.5.
  // Port selection is handled interactively inside dockToTarget.
  // If a specific port was pre-selected as the target, it will be used directly.
  dockToTarget(target).
} else {
  print "Error: No target selected, and 'Space Station 01' could not be found.".
  print "Please select a target vessel or docking port manually and run again.".
}
