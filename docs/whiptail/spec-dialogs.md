# 39 диалогов TUI (таблица генерируется)

Источник: `repo/setup.sh`; генерирует `tests/build-inventory.sh`. Порядок = порядок апстрима.

Уникальных вопросов: **39** — **29** да/нет (`--yesno`), **5** меню (`--menu`), **2** число (`--inputbox` + проверка диапазона), **3** строка (`--inputbox`).

| # | переменная | диалог | дефолт | текст вопроса |
|---|---|---|---|---|
| 1 | `MTU` | `--inputbox` (число) | `$MTU` | OpenVPN/WireGuard path MTU [1280-1420]: |
| 2 | `WARP_MTU` | `--inputbox` (число) | `$MTU` | Cloudflare WARP path MTU [1280-1420]: |
| 3 | `OPENVPN_UDP_ENABLE` | `--yesno` | `y` | Enable OpenVPN UDP? [y/n]: |
| 4 | `OPENVPN_TCP_ENABLE` | `--yesno` | `n` | Enable OpenVPN TCP? [y/n]: |
| 5 | `WIREGUARD_ENABLE` | `--yesno` | `y` | Enable WireGuard/AmneziaWG? [y/n]: |
| 6 | `OPENVPN_PATCH` | `--menu` | `2` | Version choice [1-4]: |
| 7 | `OPENVPN_DCO` | `--yesno` | `y` | Turn on OpenVPN DCO? [y/n]: |
| 8 | `ANTIZAPRET_WARP` | `--menu` | `4` | WARP choice [1-4]: |
| 9 | `VPN_WARP` | `--menu` | `2` | WARP choice [1-3]: |
| 10 | `WARP_PROTECTION` | `--yesno` | `y` | Enable WARP protection? [y/n]: |
| 11 | `WARP_ENDPOINT` | `--inputbox` | `162.159.192.$((RANDOM` | Custom Cloudflare WARP endpoint (host:port): |
| 12 | `ANTIZAPRET_DNS` | `--menu` | `1` | DNS choice [1-6]: |
| 13 | `VPN_DNS` | `--menu` | `1` | DNS choice [1-2]: |
| 14 | `DNS_WARP` | `--yesno` | `n` | Route all DNS outbound queries via Cloudflare WARP? [y/n]: |
| 15 | `ANTIZAPRET_ADBLOCK` | `--yesno` | `y` | Enable blocking ads, trackers, malware and phishing websites in AntiZapret VPN (antizapret-*) based on AdGuard and OISD rules? [y/n]: |
| 16 | `VPN_ADBLOCK` | `--yesno` | `n` | Enable blocking ads, trackers, malware and phishing websites in full VPN (vpn-*) based on AdGuard and OISD rules? [y/n]: |
| 17 | `ALTERNATIVE_CLIENT_IP` | `--yesno` | `n` | Use alternative CLIENT IP address range? [y/n]: |
| 18 | `ALTERNATIVE_FAKE_IP` | `--yesno` | `y` | Use alternative range of FAKE IP addresses? [y/n]: |
| 19 | `OPENVPN_BACKUP_UDP` | `--yesno` | `y` | Use UDP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: |
| 20 | `OPENVPN_BACKUP_TCP` | `--yesno` | `n` | Use TCP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: |
| 21 | `WIREGUARD_BACKUP` | `--yesno` | `y` | Use UDP ports 540, 580 as backup for WireGuard/AmneziaWG connections? [y/n]: |
| 22 | `OPENVPN_DUPLICATE` | `--yesno` | `y` | Allow multiple clients connecting to OpenVPN using same profile file (*.ovpn)? [y/n]: |
| 23 | `OPENVPN_LOG` | `--yesno` | `n` | Enable detailed logs and status in OpenVPN? [y/n]: |
| 24 | `SSH_PROTECTION` | `--yesno` | `y` | Enable SSH brute-force protection? [y/n]: |
| 25 | `ATTACK_PROTECTION` | `--yesno` | `y` | Enable network attack protection? [y/n]: |
| 26 | `SCAN_PROTECTION` | `--yesno` | `y` | Enable network scan protection? [y/n]: |
| 27 | `FLOOD_PROTECTION` | `--yesno` | `y` | Enable VPN client flood protection? [y/n]: |
| 28 | `TORRENT_GUARD` | `--yesno` | `y` | Enable torrent guard for full VPN? [y/n]: |
| 29 | `RESTRICT_FORWARD` | `--yesno` | `y` | Restrict forwarding in AntiZapret VPN to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]: |
| 30 | `CLIENT_ISOLATION` | `--yesno` | `y` | Enable all VPN client and server isolation? [y/n]: |
| 31 | `OPENVPN_HOST` | `--inputbox` | `-` | Enter valid domain name for this OpenVPN server or press Enter to skip: |
| 32 | `WIREGUARD_HOST` | `--inputbox` | `-` | Enter valid domain name for this WireGuard/AmneziaWG server or press Enter to skip: |
| 33 | `RECONNECT_WARP` | `--yesno` | `y` | Reconnect all WARP connections after parse.sh/doall.sh and every night? [y/n]: |
| 34 | `CLEAR_DNS_CACHE` | `--yesno` | `y` | Clear Knot Resolver DNS cache after parse.sh/doall.sh and every night? [y/n]: |
| 35 | `CLEAR_HOSTS` | `--yesno` | `y` | Remove spam domains (casino, bookmaker, etc) from AntiZapret VPN? [y/n]: |
| 36 | `ROUTE_ALL` | `--yesno` | `n` | Route all domains via AntiZapret VPN, excluding Russian domains and config/exclude-hosts.txt? [y/n]: |
| 37 | `CLOUDFLARE_INCLUDE` | `--yesno` | `y` | Include Cloudflare IPs in AntiZapret VPN? [y/n]: |
| 38 | `TELEGRAM_INCLUDE` | `--yesno` | `y` | Include Telegram IPs in AntiZapret VPN? [y/n]: |
| 39 | `WHATSAPP_INCLUDE` | `--yesno` | `y` | Include WhatsApp IPs in AntiZapret VPN? [y/n]: |

## Проверка согласованности

Строк таблицы: 39. Приёмка спеки требует 39; сверка автоматическая в `tests/check-bootstrap.sh`.
