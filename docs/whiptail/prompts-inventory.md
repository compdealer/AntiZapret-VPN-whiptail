# Инвентарь вопросов setup.sh

Источник: `repo/setup.sh` (апстрим). Файл генерирует `tests/build-inventory.sh` — руками не редактировать.

Активных вызовов `read -rp`: **41**, закомментированных: **8**.
Уникальных вопросов: **39** — **29** да/нет, **5** выбор 1..N, **2** число, **3** строка.
Повторы (MTU: 120/122, WARP_ENDPOINT: 178/180) — не отдельные вопросы, а повторный `read`
в цикле проверки; в TUI это повтор того же диалога при невалидном вводе.

| # | строка | переменная | тип | дефолт | текст |
|---|---|---|---|---|---|
| 1 | 120 | `MTU` | num | `$MTU` | OpenVPN/WireGuard path MTU [1280-1420]: |
| 2 | 122 | `MTU` | num | `$MTU` | OpenVPN/WireGuard path MTU [1280-1420]: _(повтор в цикле)_ |
| 3 | 126 | `WARP_MTU` | num | `$MTU` | Cloudflare WARP path MTU [1280-1420]: |
| 4 | 130 | `OPENVPN_UDP_ENABLE` | yn | `y` | Enable OpenVPN UDP? [y/n]: |
| 5 | 134 | `OPENVPN_TCP_ENABLE` | yn | `n` | Enable OpenVPN TCP? [y/n]: |
| 6 | 138 | `WIREGUARD_ENABLE` | yn | `y` | Enable WireGuard/AmneziaWG? [y/n]: |
| 7 | 147 | `OPENVPN_PATCH` | choice | `2` | Version choice [1-4]: |
| 8 | 152 | `OPENVPN_DCO` | yn | `y` | Turn on OpenVPN DCO? [y/n]: |
| 9 | 161 | `ANTIZAPRET_WARP` | choice | `4` | WARP choice [1-4]: |
| 10 | 169 | `VPN_WARP` | choice | `2` | WARP choice [1-3]: |
| 11 | 174 | `WARP_PROTECTION` | yn | `y` | Enable WARP protection? [y/n]: |
| 12 | 178 | `WARP_ENDPOINT` | text | `162.159.192.$((RANDOM` | Custom Cloudflare WARP endpoint (host:port): |
| 13 | 180 | `WARP_ENDPOINT` | text | `162.159.192.$((RANDOM` | Custom Cloudflare WARP endpoint (host:port): _(повтор в цикле)_ |
| 14 | 198 | `ANTIZAPRET_DNS` | choice | `1` | DNS choice [1-6]: |
| 15 | 205 | `VPN_DNS` | choice | `1` | DNS choice [1-2]: |
| 16 | 210 | `DNS_WARP` | yn | `n` | Route all DNS outbound queries via Cloudflare WARP? [y/n]: |
| 17 | 214 | `ANTIZAPRET_ADBLOCK` | yn | `y` | Enable blocking ads, trackers, malware and phishing websites in AntiZapret VPN (antizapret-*) based on AdGuard and OISD rules? [y/n]: |
| 18 | 218 | `VPN_ADBLOCK` | yn | `n` | Enable blocking ads, trackers, malware and phishing websites in full VPN (vpn-*) based on AdGuard and OISD rules? [y/n]: |
| 19 | 224 | `ALTERNATIVE_CLIENT_IP` | yn | `n` | Use alternative CLIENT IP address range? [y/n]: |
| 20 | 231 | `ALTERNATIVE_FAKE_IP` | yn | `y` | Use alternative range of FAKE IP addresses? [y/n]: |
| 21 | 235 | `OPENVPN_BACKUP_UDP` | yn | `y` | Use UDP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: |
| 22 | 239 | `OPENVPN_BACKUP_TCP` | yn | `n` | Use TCP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: |
| 23 | 243 | `WIREGUARD_BACKUP` | yn | `y` | Use UDP ports 540, 580 as backup for WireGuard/AmneziaWG connections? [y/n]: |
| 24 | 247 | `OPENVPN_DUPLICATE` | yn | `y` | Allow multiple clients connecting to OpenVPN using same profile file (*.ovpn)? [y/n]: |
| 25 | 251 | `OPENVPN_LOG` | yn | `n` | Enable detailed logs and status in OpenVPN? [y/n]: |
| 26 | 256 | `SSH_PROTECTION` | yn | `y` | Enable SSH brute-force protection? [y/n]: |
| 27 | 261 | `ATTACK_PROTECTION` | yn | `y` | Enable network attack protection? [y/n]: |
| 28 | 266 | `SCAN_PROTECTION` | yn | `y` | Enable network scan protection? [y/n]: |
| 29 | 271 | `FLOOD_PROTECTION` | yn | `y` | Enable VPN client flood protection? [y/n]: |
| 30 | 276 | `TORRENT_GUARD` | yn | `y` | Enable torrent guard for full VPN? [y/n]: |
| 31 | 280 | `RESTRICT_FORWARD` | yn | `y` | Restrict forwarding in AntiZapret VPN to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]: |
| 32 | 284 | `CLIENT_ISOLATION` | yn | `y` | Enable all VPN client and server isolation? [y/n]: |
| 33 | 287 | `OPENVPN_HOST` | text | `-` | Enter valid domain name for this OpenVPN server or press Enter to skip: |
| 34 | 293 | `WIREGUARD_HOST` | text | `-` | Enter valid domain name for this WireGuard/AmneziaWG server or press Enter to skip: |
| 35 | 300 | `RECONNECT_WARP` | yn | `y` | Reconnect all WARP connections after parse.sh/doall.sh and every night? [y/n]: |
| 36 | 304 | `CLEAR_DNS_CACHE` | yn | `y` | Clear Knot Resolver DNS cache after parse.sh/doall.sh and every night? [y/n]: |
| 37 | 308 | `CLEAR_HOSTS` | yn | `y` | Remove spam domains (casino, bookmaker, etc) from AntiZapret VPN? [y/n]: |
| 38 | 312 | `ROUTE_ALL` | yn | `n` | Route all domains via AntiZapret VPN, excluding Russian domains and config/exclude-hosts.txt? [y/n]: |
| 39 | 320 | `CLOUDFLARE_INCLUDE` | yn | `y` | Include Cloudflare IPs in AntiZapret VPN? [y/n]: |
| 40 | 324 | `TELEGRAM_INCLUDE` | yn | `y` | Include Telegram IPs in AntiZapret VPN? [y/n]: |
| 41 | 328 | `WHATSAPP_INCLUDE` | yn | `y` | Include WhatsApp IPs in AntiZapret VPN? [y/n]: |

## Закомментированные (не спрашиваются)

| строка | переменная | текст |
|---|---|---|
| 316 | `DISCORD_INCLUDE` | Include Discord voice IPs in AntiZapret VPN? [y/n]: |
| 332 | `ROBLOX_INCLUDE` | Include Roblox IPs in AntiZapret VPN? [y/n]: |
| 336 | `AMAZON_INCLUDE` | Include Amazon IPs in AntiZapret VPN? [y/n]: |
| 340 | `HETZNER_INCLUDE` | Include Hetzner IPs in AntiZapret VPN? [y/n]: |
| 344 | `DIGITALOCEAN_INCLUDE` | Include DigitalOcean IPs in AntiZapret VPN? [y/n]: |
| 348 | `OVH_INCLUDE` | Include OVH IPs in AntiZapret VPN? [y/n]: |
| 352 | `GOOGLE_INCLUDE` | Include Google IPs in AntiZapret VPN? [y/n]: |
| 356 | `AKAMAI_INCLUDE` | Include Akamai IPs in AntiZapret VPN? [y/n]: |
