# Firewalls and switches: nftables, Linux bridge with 802.1Q VLANs, ulogd for drop logs.
FROM debian:bookworm-slim

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      nftables ulogd2 iproute2 procps tcpdump iputils-ping \
 && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["sh", "/lab/bin/start.sh"]
