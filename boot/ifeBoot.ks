wait until ship:unpacked.

set terminal:width to 50.
set terminal:height to 24.

wait 0.
core:part:getModule("kOSProcessor"):doEvent("Open Terminal").

clearScreen.
wait 0.5.

runOncePath("0:/ife.ks").
