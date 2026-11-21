# Attacker on the Internet side, with common Kali tools.
FROM kalilinux/kali-rolling

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      iproute2 iputils-ping procps tcpdump curl bind9-dnsutils netcat-openbsd nmap hydra \
      python3-impacket smbclient ldap-utils openssh-client \
 && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["sh", "/lab/bin/start.sh"]
