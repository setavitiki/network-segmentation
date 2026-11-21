# Domain controller: Samba Active Directory (Kerberos, LDAP, SMB, DNS) for the domain CAMPUS.LAB.
FROM ubuntu:24.04

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      samba-ad-dc krb5-user smbclient bind9-dnsutils iproute2 iputils-ping procps \
 && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["sh", "/lab/bin/start.sh"]
