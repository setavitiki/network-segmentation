#!/bin/sh
# Start-up for every lab node. Each node's settings come from its env: block in campus.clab.yml.
#   ROLE    switch, firewall, host, hvac, jump, dns, dc, web, db, cloud
#   IFACES  "dev=address/prefix ..."  (eth2.10 creates VLAN 10 on eth2; repeat a dev for extra addresses)
#   ROUTES  "route; route"            (passed to: ip route replace)
#   DNS     resolver for /etc/resolv.conf
#   PORTS, TRUNK, ACCESS              switch ports, "port:vlan,vlan" and "port:vlan"
#   FW, RULESET                       firewall name (edge or core) and rule set (final or baseline)

PW='Campus-Lab-2026!'

log() { echo "[$(hostname)] $*"; }

# Containerlab adds the links after the container starts, so wait for the interfaces.
wait_for() {
  for dev in "$@"; do
    n=0
    while [ ! -e "/sys/class/net/$dev" ]; do
      n=$((n + 1))
      if [ "$n" -gt 120 ]; then log "interface $dev never appeared"; return 1; fi
      sleep 1
    done
  done
}

setup_ifaces() {
  bases=$(for spec in $IFACES; do dev=${spec%%=*}; echo "${dev%%.*}"; done | sort -u)
  wait_for $bases
  for spec in $IFACES; do
    dev=${spec%%=*}
    addr=${spec#*=}
    base=${dev%%.*}
    ip link set "$base" up
    if [ "$dev" != "$base" ] && [ ! -e "/sys/class/net/$dev" ]; then
      ip link add link "$base" name "$dev" type vlan id "${dev#*.}"
    fi
    ip link set "$dev" up
    ip addr add "$addr" dev "$dev" 2>/dev/null
  done
  echo "${ROUTES:-}" | tr ';' '\n' | while read -r route; do
    [ -n "$route" ] && ip route replace $route
  done
}

setup_switch() {
  wait_for $PORTS
  ip link add br0 type bridge vlan_filtering 1 2>/dev/null
  ip link set br0 up
  for port in $PORTS; do
    ip link set "$port" master br0
    ip link set "$port" up
  done
  for spec in ${ACCESS:-}; do
    port=${spec%%:*}
    bridge vlan del dev "$port" vid 1
    bridge vlan add dev "$port" vid "${spec#*:}" pvid untagged
  done
  for spec in ${TRUNK:-}; do
    port=${spec%%:*}
    bridge vlan del dev "$port" vid 1
    for vid in $(echo "${spec#*:}" | tr ',' ' '); do
      bridge vlan add dev "$port" vid "$vid"
    done
  done
  log "switch ready: ${ACCESS:-all ports in one segment}"
}

setup_client() {
  if [ -n "${DNS:-}" ]; then
    printf 'nameserver %s\nsearch campus.lab\n' "$DNS" > /etc/resolv.conf
  fi
  grep -q dc1.campus.lab /etc/hosts 2>/dev/null || echo "10.10.105.10 dc1.campus.lab dc1" >> /etc/hosts
  if [ "$ROLE" != dc ] && [ -f /lab/config/krb5.conf ]; then
    cp /lab/config/krb5.conf /etc/krb5.conf
  fi
}

make_cert() {
  mkdir -p /etc/ssl/private /etc/ssl/certs
  [ -f /etc/ssl/private/lab.key ] || openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -subj "/CN=$(hostname).campus.lab" \
    -keyout /etc/ssl/private/lab.key -out /etc/ssl/certs/lab.crt 2>/dev/null
}

# Firewall drop logs: nftables sends them to NFLOG group 1, ulogd writes /var/log/firewall.log
start_ulogd() {
  plugins=$(dirname "$(ls /usr/lib/*/ulogd/ulogd_inppkt_NFLOG.so 2>/dev/null | head -n 1)")
  cat > /etc/ulogd-lab.conf <<EOF
[global]
logfile="/var/log/ulogd.log"
loglevel=5
plugin="$plugins/ulogd_inppkt_NFLOG.so"
plugin="$plugins/ulogd_raw2packet_BASE.so"
plugin="$plugins/ulogd_filter_IFINDEX.so"
plugin="$plugins/ulogd_filter_IP2STR.so"
plugin="$plugins/ulogd_filter_PRINTPKT.so"
plugin="$plugins/ulogd_output_LOGEMU.so"
stack=log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU

[log1]
group=1

[emu1]
file="/var/log/firewall.log"
sync=1
EOF
  touch /var/log/firewall.log
  ulogd -d -c /etc/ulogd-lab.conf || log "ulogd did not start: drops are counted but not logged"
}

start_db() {
  pgbin=$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -n 1)
  data=/var/lib/postgresql/lab
  mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql
  if [ ! -s "$data/PG_VERSION" ]; then
    mkdir -p "$data" && chown postgres:postgres "$data"
    su postgres -s /bin/sh -c "$pgbin/initdb -D $data --auth-local=trust --auth-host=scram-sha-256" >/dev/null
    echo "listen_addresses = '*'" >> "$data/postgresql.conf"
    echo "host all all 10.10.0.0/16 scram-sha-256" >> "$data/pg_hba.conf"
    su postgres -s /bin/sh -c "$pgbin/pg_ctl -D $data -w -l /tmp/pg-init.log start" >/dev/null
    su postgres -s /bin/sh -c "$pgbin/psql -q -f /lab/config/records.sql"
    su postgres -s /bin/sh -c "$pgbin/pg_ctl -D $data -w stop" >/dev/null
  fi
  log "records database ready on 10.10.110.20:5432"
  exec su postgres -s /bin/sh -c "exec $pgbin/postgres -D $data"
}

start_dc() {
  if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    log "creating the CAMPUS.LAB domain (first start takes about a minute)"
    rm -f /etc/samba/smb.conf
    if ! samba-tool domain provision --server-role=dc --use-rfc2307 --dns-backend=SAMBA_INTERNAL \
        --realm=CAMPUS.LAB --domain=CAMPUS --host-name=dc1 --host-ip=10.10.105.10 \
        --adminpass="$PW" \
        --option="interfaces = lo eth1" \
        --option="bind interfaces only = yes" \
        --option="dns forwarder = 10.10.100.10" \
        --option="rpc server dynamic port range = 49152-49159" > /tmp/provision.log 2>&1; then
      log "domain setup failed, last lines of /tmp/provision.log:"
      tail -n 20 /tmp/provision.log
      return 1
    fi
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
    for group in Records Finance Facilities IT-Admins; do
      samba-tool group add "$group" >/dev/null
    done
    samba-tool user create alice "$PW" --given-name=Alice --surname=Staff >/dev/null
    samba-tool user create bob "$PW" --given-name=Bob --surname=Finance >/dev/null
    samba-tool user create itadmin "$PW" --given-name=IT --surname=Admin >/dev/null
    samba-tool group addmembers Records alice >/dev/null
    samba-tool group addmembers Finance bob >/dev/null
    samba-tool group addmembers IT-Admins itadmin >/dev/null
  fi
  samba --foreground --no-process-group --debug-stdout &
  samba_pid=$!
  n=0
  until bash -c 'echo > /dev/tcp/127.0.0.1/389' 2>/dev/null; do
    n=$((n + 1)); [ "$n" -gt 120 ] && break; sleep 1
  done
  if [ ! -f /var/lib/samba/.dns-records ]; then
    sleep 5
    for record in "banner 10.10.110.10" "pay 10.10.110.30" "records-db 10.10.110.20" \
                  "jump 10.10.99.10" "dns 10.10.100.10" "staff-pc 10.10.10.10" "hvac 10.10.50.100"; do
      set -- $record
      samba-tool dns add 127.0.0.1 campus.lab "$1" A "$2" -U Administrator --password="$PW" >/dev/null 2>&1
    done
    touch /var/lib/samba/.dns-records
  fi
  log "dc1 is ready (domain CAMPUS.LAB)"
  wait "$samba_pid"
}

case "${ROLE:-host}" in
  switch)
    setup_switch
    ;;
  firewall)
    setup_ifaces
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    start_ulogd
    sh /lab/bin/fw-rules.sh "${RULESET:-final}"
    ;;
  host)
    setup_ifaces; setup_client
    ;;
  hvac)
    setup_ifaces; setup_client
    # The controller checks in with its vendor cloud every minute, as real building controllers do.
    ( while true; do
        curl -sk --max-time 5 https://hvac-vendor.example/update.json -o /tmp/update.json \
          && log "vendor update: $(cat /tmp/update.json)"
        sleep 60
      done ) &
    ;;
  jump)
    setup_ifaces; setup_client
    mkdir -p /run/sshd && ssh-keygen -A >/dev/null && /usr/sbin/sshd
    ;;
  dns)
    setup_ifaces
    exec unbound -d -c /lab/config/unbound.conf
    ;;
  web)
    setup_ifaces; setup_client; make_cert
    exec nginx -c /lab/config/nginx-rstr.conf -g 'daemon off;'
    ;;
  db)
    setup_ifaces; setup_client
    start_db
    ;;
  dc)
    setup_ifaces; setup_client
    start_dc
    ;;
  cloud)
    setup_ifaces; make_cert
    mkdir -p /srv/vendor && cp /lab/config/vendor/update.json /srv/vendor/update.json
    dnsmasq -k --conf-file=/lab/config/dnsmasq-cloud.conf &
    exec nginx -c /lab/config/nginx-cloud.conf -g 'daemon off;'
    ;;
esac

exec sleep infinity
