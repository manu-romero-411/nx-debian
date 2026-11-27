#!/bin/bash
# The L4T Megascript (/usr/lib/nxd/megascript), from EmulationStation's Ports,
# in a terminal: it asks for the password of the user when it installs
# something, so it needs a keyboard (USB or Bluetooth).
exec xterm -maximized -fa 'DejaVu Sans Mono' -fs 12 -T 'L4T Megascript' -e /usr/lib/nxd/megascript
