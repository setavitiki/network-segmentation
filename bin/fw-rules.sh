#!/bin/sh
# Load a rule set on this firewall:  sh /lab/bin/fw-rules.sh final|baseline
# FW (edge or core) comes from the node's env in campus.clab.yml.
name=${1:-final}
file="/lab/rules/${FW}-${name}.nft"

if [ ! -f "$file" ]; then
  echo "No rule file $file"
  exit 1
fi

if nft -f "$file" 2>/tmp/nft.err; then
  echo "$FW firewall: $name rules loaded"
elif sed 's/ log prefix "[^"]*" group [0-9]*//' "$file" | nft -f /dev/stdin; then
  # Some kernels cannot send logs from containers; the rules still apply, only the drop log is lost.
  echo "$FW firewall: $name rules loaded without drop logging ($(head -n 1 /tmp/nft.err))"
else
  cat /tmp/nft.err
  exit 1
fi
echo "$name" > /tmp/ruleset
