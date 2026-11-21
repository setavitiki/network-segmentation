#!/usr/bin/env bash
# Helper for the campus segmentation lab. Run it inside the Linux machine that has
# containerlab (an OrbStack machine on a Mac, WSL on Windows).
set -euo pipefail
cd "$(dirname "$0")"

TOPO=campus.clab.yml
node() { echo "clab-campus-$1"; }

usage() {
  cat <<'EOF'
Usage: ./lab.sh <command>

  build                    build the four images (first time, and after changing images/)
  up                       start the lab with the final rules
  down                     stop the lab and remove it
  status                   list the nodes and the rule set loaded
  rules final|baseline     load a rule set on both firewalls
  logs                     follow the firewall drop logs (Ctrl+C to stop)
  shell <node>             open a shell on a node, e.g. ./lab.sh shell staff-pc
  graph                    draw the topology at http://localhost:50080
  finance-login <ip>       tell the Core firewall a Finance user is on <ip> (User-ID)
  finance-logout <ip>
EOF
}

case "${1:-help}" in
  build)
    for image in net node dc kali; do
      docker build -t "campus/$image:latest" "images/$image"
    done
    ;;
  up)
    sudo containerlab deploy -t "$TOPO" --reconfigure
    echo "Waiting for dc1 to set up the domain (about a minute on first start)..."
    for _ in $(seq 1 180); do
      if docker logs "$(node dc1)" 2>&1 | grep -q "dc1 is ready"; then
        echo "Lab is ready."
        exit 0
      fi
      sleep 1
    done
    echo "dc1 is not ready yet. Check with: docker logs $(node dc1)"
    ;;
  down)
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  status)
    sudo containerlab inspect -t "$TOPO"
    echo "Rule set loaded: $(docker exec "$(node core-fw)" cat /tmp/ruleset 2>/dev/null || echo unknown)"
    ;;
  rules)
    set_name="${2:?give final or baseline}"
    for fw in edge-fw core-fw; do
      docker exec "$(node "$fw")" sh /lab/bin/fw-rules.sh "$set_name"
    done
    ;;
  logs)
    docker exec "$(node edge-fw)" tail -n 20 -f /var/log/firewall.log &
    docker exec "$(node core-fw)" tail -n 20 -f /var/log/firewall.log
    ;;
  shell)
    docker exec -it "$(node "${2:?give a node name}")" bash
    ;;
  graph)
    sudo containerlab graph -t "$TOPO"
    ;;
  finance-login)
    docker exec "$(node core-fw)" nft add element inet core finance_users "{ ${2:?give an IP address} }"
    echo "Core firewall: Finance user logged in on $2"
    ;;
  finance-logout)
    docker exec "$(node core-fw)" nft delete element inet core finance_users "{ ${2:?give an IP address} }"
    echo "Core firewall: Finance user logged out of $2"
    ;;
  *)
    usage
    ;;
esac
