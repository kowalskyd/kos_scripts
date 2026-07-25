// =============================================
//    FULL AUTOMATED MINMUS MISSION SEQUENCER
// =============================================
// Runs the entire mission end-to-end:
//   1. launch (launch to Kerbin orbit)
//   2. minmus.ks (ejection burn, SOI transition, circularization)
//   3. minmusLand.ks (landing preparation, deorbit, suicide burn, touchdown)
//   4. minmusLaunch.ks (takeoff, ascent, circularization in Minmus orbit)
//   5. minmusReturn.ks (ejection, coast, reentry preparation, reentry, parachutes)

runOncePath("0:/lib/diagnostics.ks").
if not runPreFlightChecks() {
  clearScreen.
  print "=======================================".
  print "      MINMUS MISSION ABORTED           ".
  print "=======================================".
} else {
  global automatedMission is true.
  clearScreen.
  print "=======================================".
  print "   AUTOMATED MINMUS MISSION ACTIVATED  ".
  print "=======================================".
  wait 2.

  print "Step 1: Launching to Kerbin Orbit...".
  runPath("0:/launch").
  wait 5.

  print "Step 2: Transferring to Minmus Orbit...".
  runPath("0:/minmus.ks").
  wait 5.

  print "Step 3: Performing Minmus Landing...".
  runPath("0:/minmusLand.ks").
  wait 5.

  print "Step 4: Launching from Minmus to Orbit...".
  runPath("0:/minmusLaunch.ks").
  wait 5.

  print "Step 5: Returning to Kerbin...".
  runPath("0:/minmusReturn.ks").

  print "=======================================".
  print "   AUTOMATED MINMUS MISSION COMPLETED! ".
  print "=======================================".
}
