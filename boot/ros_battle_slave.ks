//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// ROS 2 KOS AUTOMATIC SLAVE BOOT SCRIPT
// (Passive Standby Mode - Woken Up by Master Rover)
//_________________________________________________
//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

switch to 0.

set CONFIG:IPU to 1000.

clearScreen.
print "==================================================".
print "=== ROS 2 KOS SLAVE BATTLE ROVER INITIALIZED ===".
print "==================================================".
print "STATUS: PASSIVE SLAVE STANDBY".
print "WAITING FOR MASTER SIGNAL (OR PRESS KEY 0 / AG10)...".
print "==================================================".

brakes on.
lights off.
lock wheelthrottle to 0.

local battleStarted is false.

until battleStarted {
  // 1. Check for Master Signal File on Archive Volume 0
  if exists("0:/battle_start.txt") or exists("0:/battle_start.json") or exists("0:/battle_start.txt.json") {
    set battleStarted to true.
    print ">>> MASTER BATTLE SIGNAL FILE DETECTED! <<<".
  }

  // 2. Check for Inter-Vessel Messages
  if not core:messages:empty {
    local msg is core:messages:pop().
    set battleStarted to true.
    print ">>> INTER-VESSEL MESSAGE RECEIVED! <<<".
  }

  // 3. Check for Action Group 10 (Key 0)
  if AG10 {
    set battleStarted to true.
    print ">>> MANUAL START SIGNAL (AG10) DETECTED! <<<".
  }

  wait 0.02.
}

brakes off.
print ">>> BATTLE UNLEASHED! LAUNCHING ROS BATTLE AI... <<<".
runPath("0:/ros_battle.ks").
