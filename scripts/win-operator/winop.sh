#!/bin/bash
# winop.sh - call the resident Windows operator (127.0.0.1:18711).
# Usage:
#   winop.sh ping
#   winop.sh '{"command":"list-windows"}'
#   winop.sh '{"command":"click","x":100,"y":200}'
#   winop.sh '{"command":"type","pid":1234,"clickX":500,"clickY":300,"text":"hello"}'
#   winop.sh '{"command":"screenshot"}'
#   winop.sh '{"command":"get-tree","pid":1234,"maxElements":100,"maxDepth":4}'
#   winop.sh '{"command":"bring-to-front","hwnd":123456}'
#   winop.sh '{"command":"get-text","windowHwnd":123456,"className":"Edit"}'
#   winop.sh '{"command":"press-key","key":"return"}'
#   winop.sh '{"command":"press-key","hotkey":["ctrl","s"]}'
#   winop.sh '{"command":"run","path":"notepad.exe"}'
# Requires the 18711 tunnel (win_operator_tunnel.sh, auto-restarted by vm-recover).
if [ "$1" = "ping" ] || [ -z "$1" ]; then
  curl -s -m 15 http://127.0.0.1:18711/ping
  echo
  exit 0
fi
curl -s -m 60 -X POST http://127.0.0.1:18711/ -H 'Content-Type: application/json' -d "$1"
echo
