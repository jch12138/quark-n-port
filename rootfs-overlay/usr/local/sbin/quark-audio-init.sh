#!/bin/bash
set -euo pipefail

# The H3 codec probes with all useful paths muted.  Apply conservative levels;
# users can adjust them later with alsamixer and persist with alsactl store.
if [ ! -e /proc/asound/card0 ]; then
	echo "H3 audio card is not available" >&2
	exit 1
fi

amixer -q -c 0 sset 'Line Out' 75% unmute
amixer -q -c 0 sset 'DAC' 80% unmute
amixer -q -c 0 sset 'Mic1' 60% unmute cap
amixer -q -c 0 sset 'Mic1 Boost' 57%
amixer -q -c 0 sset 'ADC Gain' 43%
