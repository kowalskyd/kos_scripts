// =============================================
//      FULL AUTOMATED MUN MISSION SEQUENCER
// =============================================
// Runs the entire mission end-to-end:
//   1. launch (launch to Kerbin orbit)
//   2. mun.ks (ejection burn, SOI transition, circularization)
//   3. munLand.ks (landing preparation, deorbit, suicide burn, touchdown)
//   4. munLaunch.ks (takeoff, ascent, circularization in Mun orbit)
//   5. munReturn.ks (ejection, coast, reentry preparation, reentry, parachutes)

runOncePath("0:/lib/diagnostics.ks").
if not runPreFlightChecks() {
  clearScreen.
  
  print "=======================================".
  print "        MUN MISSION ABORTED            ".
  print "=======================================".
} else {
  global automatedMission is true.
  clearScreen.
  print "=======================================".
  print "    AUTOMATED MUN MISSION ACTIVATED    ".
  print "=======================================".
  wait 2.

  print "Step 1: Launching to Kerbin Orbit...".
  runPath("0:/launch").
  wait 1.

  print "Step 2: Transferring to Mun Orbit...".
  runPath("0:/mun.ks").
  wait 1.

  print "Step 3: Performing Mun Landing...".
  runPath("0:/munLand.ks").
  wait 1.

  print "Step 4: Launching from Mun to Orbit...".
  runPath("0:/munLaunch.ks").
  wait 1.

  print "Step 5: Returning to Kerbin...".
  runPath("0:/munReturn.ks").

  print "=======================================".
  print "    AUTOMATED MUN MISSION COMPLETED!   ".
  print "=======================================".
}
