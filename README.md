# Campus Segmentation Lab

A working slice of our campus network design, built with [Containerlab](https://containerlab.dev). Two firewalls in series (Edge and Core), a campus switch with one VLAN per zone, real services (Active Directory with Kerberos, web front ends, a database, DNS, a jump host) and an attacker on the Internet side. Rule IDs match the document *Firewall Rules: Campus Network Segmentation*.

```
                        Internet (EXT) 203.0.113.0/24
        attacker (Kali) .66        cloud .10: Canvas .30, HVAC vendor .20, DNS .53
                              \     /
                                isp
                                 |
  vpn-laptop -------------- edge-fw -------------- core-fw ===== 802.1Q trunk ===== campus-sw
  10.10.250.10  staff                                (gateway for every VLAN)          |
  10.10.250.200 IT admins                                                 VLAN 10   staff-pc    10.10.10.10    FAC
                                                                          VLAN 50   hvac        10.10.50.100   BLDG
                                                                          VLAN 99   jump        10.10.99.10    ADMIN
                                                                          VLAN 100  dns         10.10.100.10   CORE
                                                                          VLAN 105  dc1         10.10.105.10   IDENT
                                                                          VLAN 110  banner      10.10.110.10   RSTR (payment portal .30)
                                                                          VLAN 110  records-db  10.10.110.20   RSTR
```

| Node | Zone | What runs on it |
| --- | --- | --- |
| edge-fw, core-fw | Firewalls | nftables rules, NAT to the Internet, drop logs |
| campus-sw | Switch | Linux bridge with 802.1Q VLANs (trunk to core-fw, access ports to hosts) |
| dc1 | IDENT | Samba Active Directory: domain CAMPUS.LAB, Kerberos, LDAP, SMB, DNS |
| dns | CORE | Unbound DNS for all zones (stands in for the Umbrella appliance) |
| banner | RSTR | nginx over HTTPS: Banner / Patriot Web (.10) and the payment portal (.30) |
| records-db | RSTR | PostgreSQL records database (stands in for Oracle under Banner) |
| jump | ADMIN | OpenSSH jump host |
| staff-pc, vpn-laptop, hvac | FAC, VPN, BLDG | Client tools: nmap, curl, dig, kinit, smbclient, ldapsearch, psql, impacket |
| attacker | EXT | Kali Linux: nmap, hydra, impacket, tcpdump |
| cloud | EXT | Canvas and HVAC vendor stand-ins (nginx), Internet DNS (dnsmasq) |

## Set up (once)

**Mac (Apple Silicon or Intel).** Install [OrbStack](https://orbstack.dev), then in Terminal:

```bash
orb create ubuntu clab          # a Linux machine for the lab
orb -m clab                     # open a shell in it
sudo apt update && sudo apt install -y git
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
newgrp docker
```

**Windows.** Install the [WSL-Containerlab](https://containerlab.dev/windows/) distribution (`wsl --install --from-file clab.wsl`), then open it with `wsl -d Containerlab`. Docker and containerlab are already in it. If Docker Desktop is installed, turn off its WSL integration for this distribution.

Then, inside the Linux machine (for a private repository, run `gh auth login` first):

```bash
git clone <repository URL> segmentation-lab
cd segmentation-lab
./lab.sh build      # first time only, about 10 to 20 minutes
./lab.sh up
```

## Use it

| Command | What it does |
| --- | --- |
| `./lab.sh up` / `down` | Start the lab (final rules) / stop and remove it |
| `./lab.sh rules final` / `baseline` | Load the final rules or the loose baseline on both firewalls |
| `./lab.sh shell staff-pc` | Open a shell on a node |
| `./lab.sh logs` | Follow the firewall drop logs |
| `./lab.sh graph` | Draw the topology at http://localhost:50080 |
| `./lab.sh status` | List the nodes and the rule set loaded |
| `./lab.sh finance-login 10.10.10.10` | Tell the Core firewall a Finance user is on that PC (User-ID) |

Quick check, from `./lab.sh shell staff-pc`:

```bash
kinit alice                                  # a real Kerberos ticket from dc1
curl -k https://10.10.110.10                 # Banner: allowed (R-20)
nmap -Pn -p 443,5432 10.10.110.20 10.10.110.30   # database and payment portal: filtered with final rules
```

Then run `./lab.sh rules baseline` and repeat the `nmap`: the same ports now answer.

## Logins (lab only)

| Account | Password | Where |
| --- | --- | --- |
| alice (Records), bob (Finance), itadmin (IT-Admins) | `Campus-Lab-2026!` | Domain CAMPUS.LAB on dc1 |
| Administrator | `Campus-Lab-2026!` | Domain CAMPUS.LAB on dc1 |
| itadmin | `Campus-Lab-2026!` | Local account on jump and the other hosts |
| banner | `Campus-Lab-2026!` | records database on records-db |

## Files

```
campus.clab.yml     topology: nodes, addresses, VLANs, links
lab.sh              helper commands
images/             Dockerfiles: net (firewalls, switch), node (hosts, servers), dc, kali
bin/                start-up script for every node, and the firewall rule loader
config/             DNS, web, Kerberos and database settings
rules/              nftables rules for each firewall: final and baseline
```

## Change it

- **Rules.** Edit `rules/core-final.nft` or `rules/edge-final.nft`, then `./lab.sh rules final`. No restart needed.
- **Configs and scripts.** `bin/`, `config/` and `rules/` are mounted into the nodes, so changes apply after `./lab.sh up` without a rebuild. Only changes to `images/` need `./lab.sh build`.
- **A new zone.** In `campus.clab.yml`: add a VLAN sub-interface to `core-fw` (for example `eth2.30=10.10.30.254/24`), add the VLAN to the `campus-sw` trunk, add a node with a free switch port in `PORTS` and `ACCESS`, and add the link. Then add its rules to `rules/core-final.nft`.
