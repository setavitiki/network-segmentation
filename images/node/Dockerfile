# Campus hosts and servers: client tools plus the services some nodes run
# (OpenSSH, nginx, PostgreSQL, Unbound, dnsmasq). The role in campus.clab.yml picks what starts.
FROM debian:bookworm-slim

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      iproute2 iputils-ping procps tcpdump curl ca-certificates bind9-dnsutils netcat-openbsd nmap \
      openssh-client openssh-server smbclient ldap-utils krb5-user python3-impacket \
      postgresql postgresql-client nginx unbound dnsmasq-base openssl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash itadmin \
 && echo 'itadmin:Campus-Lab-2026!' | chpasswd

ENTRYPOINT ["sh", "/lab/bin/start.sh"]
