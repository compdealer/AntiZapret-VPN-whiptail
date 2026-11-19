#!/bin/bash
#
# Скрипт для установки на своём сервере AntiZapret VPN + полный VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# Завершим выполнение скрипта при ошибке
set -e

# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $2: $3 (exit code $1)\e[0m"
	exit 1
}
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

# Лог установки: апстрим лог не ведёт, а версию whiptail нужно писать в файл
LOG=${LOG:-/tmp/antizapret-setup.log}

# QUESTIONS_ONLY=1 — только вопросы: система не меняется, блок setup печатается в stdout
QUESTIONS_ONLY=${QUESTIONS_ONLY:-0}

# 1) выбор интерфейса. Приоритет: AZ_UI -> NO_WHIPTAIL -> нет TTY -> вопрос.
#    Вопрос задаётся обычным read -rp: whiptail здесь использовать нельзя.
ui_explicit=0
if [[ -n ${AZ_UI:-} ]]; then
	ui_explicit=1
elif [[ ${NO_WHIPTAIL:-0} == 1 ]]; then
	AZ_UI=plain
elif [[ ! -t 0 ]]; then
	AZ_UI=plain
	echo "stdin is not a terminal: using plain prompts"
else
	while :; do
		read -rp 'Interface: 1) whiptail TUI  2) plain prompts [1]: ' ui_choice || ui_choice=1
		case ${ui_choice:-1} in
			1) AZ_UI=whiptail; break ;;
			2) AZ_UI=plain; break ;;
			*) echo "Invalid choice: ${ui_choice}" ;;
		esac
	done
fi
case $AZ_UI in
	whiptail|plain) ;;
	*) echo "AZ_UI must be whiptail or plain"; exit 2 ;;
esac

# 2) режим whiptail: бинарь, TTY, TERM. Пакет ставим только в этой ветке.
if [[ $AZ_UI == whiptail ]]; then
	WHIPTAIL_BIN=$(command -v whiptail || true)
	if [[ -z $WHIPTAIL_BIN && ${QUESTIONS_ONLY:-0} != 1 ]]; then
		apt-get install -y whiptail || true
		WHIPTAIL_BIN=$(command -v whiptail || true)
	fi
	if [[ -z $WHIPTAIL_BIN ]]; then
		# явный AZ_UI=whiptail молча не подменяем
		if [[ $ui_explicit == 1 ]]; then
			echo "AZ_UI=whiptail but whiptail is not installed"
			exit 2
		fi
		echo "whiptail not available, falling back to plain prompts"
		AZ_UI=plain
	elif [[ $ui_explicit == 0 && ( ! -t 0 || -z ${TERM:-} ) ]]; then
		echo "whiptail not available, falling back to plain prompts"
		AZ_UI=plain
	fi
	if [[ $AZ_UI == whiptail && ${QUESTIONS_ONLY:-0} != 1 ]]; then
		whiptail --version 2>&1 | head -1 >> "$LOG"
	fi
fi

# 3) хелперы диалогов: ответ приходит по fd 3 (3>&1 1>&2 2>&3), а каждый вызов
#    стоит в if/|| — иначе set -e убил бы установщик на Cancel (1) и ESC (255).
WHIPTAIL_TITLE='AntiZapret VPN setup'

# Терминал не умеет рисовать: явный AZ_UI -> код 2, выбранный в диалоге -> plain
if [[ $AZ_UI == whiptail ]]; then
	if ! whiptail --infobox '' 8 40 3>&1 1>&2 2>&3 2>/dev/null; then
		if [[ $ui_explicit == 1 ]]; then
			echo "AZ_UI=whiptail but whiptail cannot draw on this terminal"
			exit 2
		fi
		echo "whiptail not available, falling back to plain prompts"
		AZ_UI=plain
	fi
fi

# Апстримные тексты размечены ANSI (SOH ... ESC[1;32m ... STX): whiptail inline-ANSI
# не разбирает, поэтому маркеры и SGR-последовательности из текста диалога вырезаем.
wt_clean() {
	local s=$1
	local rx=$'\033\\[[0-9;]*m'
	s=${s//$'\001'/}
	s=${s//$'\002'/}
	while [[ $s =~ $rx ]]; do
		s=${s//"${BASH_REMATCH[0]}"/}
	done
	printf '%s' "$s"
}

# Размер окна по фактическому тексту: newt переносит только текст сообщения
# (внутренняя ширина = ширина окна - 4), поэтому ширину берём по самой длинной
# строке, высоту — по числу строк после переноса плюс строки списка. Подсчёт —
# как в dietpi-globals:524-560; при нехватке места включаем --scrolltext.
# Размер терминала: COLUMNS/LINES из окружения, иначе сам терминал, иначе 24x80.
# В скрипте COLUMNS/LINES обычно не экспортированы, поэтому нужен путь через stty.
wt_term() {
	local s
	if [[ -n ${COLUMNS:-} && -n ${LINES:-} ]]; then
		printf '%s %s\n' "$LINES" "$COLUMNS"
		return
	fi
	if s=$(stty size < /dev/tty 2>/dev/null) && [[ -n $s ]]; then
		printf '%s\n' "$s"
		return
	fi
	printf '24 80\n'
}

wt_dims() {
	local text=$1 rows=${2:-0}
	local cols lines
	read -r lines cols <<< "$(wt_term)"
	local width=40 inner wrap=0 line height maxh
	local -a parts=()
	local scroll=''
	[[ $cols =~ ^[0-9]+$ ]] || cols=80
	[[ $lines =~ ^[0-9]+$ ]] || lines=24
	mapfile -t parts <<< "$text"
	for line in "${parts[@]}"; do
		if (( ${#line} > width )); then
			width=${#line}
		fi
	done
	if (( width > 120 )); then
		width=120
	fi
	if (( width > cols - 2 )); then
		width=$(( cols - 2 ))
	fi
	if (( width < 40 )); then
		width=40
	fi
	inner=$(( width - 4 ))
	if (( inner < 8 )); then
		inner=8
	fi
	for line in "${parts[@]}"; do
		wrap=$(( wrap + 1 + ( ${#line} - 1 ) / inner ))
	done
	height=$(( wrap + rows + 7 ))
	maxh=$(( lines - 2 ))
	if (( maxh < 12 )); then
		maxh=12
	fi
	if (( height > maxh )); then
		height=$maxh
		scroll='--scrolltext'
	fi
	printf '%s %s %s\n' "$height" "$width" "$scroll"
}

# Сообщение об ошибке: размер по тексту, как у остальных диалогов
wt_msg() {
	local text=$1 h w scroll
	text=$(wt_clean "$text")
	read -r h w scroll <<< "$(wt_dims "$text" 0)"
	if (( h < 10 )); then
		h=10
	fi
	if [[ -n $scroll ]]; then
		whiptail --title "$WHIPTAIL_TITLE" --scrolltext --msgbox "$text" "$h" "$w" 3>&1 1>&2 2>&3 || true
	else
		whiptail --title "$WHIPTAIL_TITLE" --msgbox "$text" "$h" "$w" 3>&1 1>&2 2>&3 || true
	fi
}

# Файл целиком (сводка настроек): размер по экрану, прокрутка включена всегда
wt_textbox() {
	local file=$1 h w lines cols
	read -r lines cols <<< "$(wt_term)"
	[[ $lines =~ ^[0-9]+$ ]] || lines=24
	[[ $cols =~ ^[0-9]+$ ]] || cols=80
	h=$(( lines - 4 ))
	w=$(( cols - 4 ))
	if (( h < 12 )); then
		h=12
	fi
	if (( w < 40 )); then
		w=40
	fi
	if (( w > 120 )); then
		w=120
	fi
	whiptail --title "$WHIPTAIL_TITLE" --scrolltext --textbox "$file" "$h" "$w" 3>&1 1>&2 2>&3 || true
}

# Да/нет: y или n
ask_yn() {
	local var=$1 text=$2 def=$3
	local rc=0 h w scroll
	local -a opt=()
	text=$(wt_clean "$text")
	read -r h w scroll <<< "$(wt_dims "$text" 0)"
	if [[ $def == n ]]; then
		opt+=(--defaultno)
	fi
	if [[ -n $scroll ]]; then
		opt+=("$scroll")
	fi
	whiptail --title "$WHIPTAIL_TITLE" "${opt[@]}" --yesno "$text" "$h" "$w" 3>&1 1>&2 2>&3 || rc=$?
	if [[ $rc -eq 0 ]]; then
		printf -v "$var" '%s' y
	elif [[ $rc -eq 1 ]]; then
		printf -v "$var" '%s' n
	else
		echo "Cancelled" >&2
		exit 1
	fi
}

# Число в диапазоне: неверный ввод -> msgbox с ошибкой и тот же диалог
ask_num() {
	local var=$1 text=$2 min=$3 max=$4 def=$5
	local val=$def rc=0 h w scroll
	text=$(wt_clean "$text")
	read -r h w scroll <<< "$(wt_dims "$text" 0)"
	if (( h < 12 )); then
		h=12
	fi
	while :; do
		rc=0
		val=$(whiptail --title "$WHIPTAIL_TITLE" --inputbox "$text" "$h" "$w" "$val" 3>&1 1>&2 2>&3) || rc=$?
		if [[ $rc -ne 0 ]]; then
			echo "Cancelled" >&2
			exit 1
		fi
		if [[ $val =~ ^[0-9]+$ ]] && (( val >= min && val <= max )); then
			break
		fi
		wt_msg "Invalid value: $val
Enter a number from $min to $max"
	done
	printf -v "$var" '%s' "$val"
}

# Меню: возвращает тег (номер пункта), а не текст пункта.
# newt не переносит пункты списка (хвост строки обрезается), поэтому меню с длинными
# описаниями помечают --noitem: полная строка автора («1 MSK-IX+NSDI - …») уходит в текст
# сообщения (там перенос по словам), а в списке остаётся только номер пункта.
ask_menu() {
	local var=$1 text=$2 def=$3
	shift 3
	local noitem=0 h w scroll rc=0 out rows=0
	local -a items=() nio=()
	if [[ ${1:-} == --noitem ]]; then
		noitem=1
		shift
	fi
	text=$(wt_clean "$text")
	if (( noitem )); then
		while (( $# )); do
			text+=$'\n'"$1 $2"
			items+=("$1" '')
			rows=$(( rows + 1 ))
			shift 2
		done
		nio+=(--noitem)
	else
		items=("$@")
		rows=$(( $# / 2 ))
	fi
	read -r h w scroll <<< "$(wt_dims "$text" "$rows")"
	if [[ -n $scroll ]]; then
		nio+=("$scroll")
	fi
	out=$(whiptail --title "$WHIPTAIL_TITLE" "${nio[@]}" --menu "$text" "$h" "$w" "$rows" --default-item "$def" "${items[@]}" 3>&1 1>&2 2>&3) || rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "Cancelled" >&2
		exit 1
	fi
	printf -v "$var" '%s' "$out"
}

# Строка: необязательный regex и необязательная проверка домена через getent
ask_text() {
	local var=$1 text=$2 def=$3 regex=${4:-} mode=${5:-}
	text=$(wt_clean "$text")
	local val=$def rc=0 h w scroll
	read -r h w scroll <<< "$(wt_dims "$text" 0)"
	if (( h < 12 )); then
		h=12
	fi
	while :; do
		rc=0
		val=$(whiptail --title "$WHIPTAIL_TITLE" --inputbox "$text" "$h" "$w" "$val" 3>&1 1>&2 2>&3) || rc=$?
		if [[ $rc -ne 0 ]]; then
			echo "Cancelled" >&2
			exit 1
		fi
		if [[ -n $regex && ! $val =~ $regex ]]; then
			wt_msg "Invalid value: $val"
			continue
		fi
		if [[ $mode == host && -n $val ]]; then
			if [[ -z $(getent ahostsv4 "$val") ]]; then
				wt_msg "Invalid domain name: $val"
				continue
			fi
		fi
		break
	done
	printf -v "$var" '%s' "$val"
}

# В режиме QUESTIONS_ONLY системная преамбула целиком пропускается
if [[ $QUESTIONS_ONLY != 1 ]]; then
# Проверка необходимости перезагрузить
if [[ -f /var/run/reboot-required ]] || pidof apt apt-get dpkg unattended-upgrades &>/dev/null; then
	echo 'Error: You need to reboot this server before installation!'
	exit 2
fi

# Остановим фоновые обновления системы
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily 2>/dev/null || true
systemctl stop apt-daily-upgrade 2>/dev/null || true
systemctl stop unattended-upgrades 2>/dev/null || true

# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo 'Error: You need to run this as root!'
	exit 3
fi

cd /root

# Проверка на OpenVZ и LXC
if [[ "$(systemd-detect-virt)" == 'openvz' || "$(systemd-detect-virt)" == 'lxc' ]]; then
	echo 'Error: OpenVZ and LXC are not supported!'
	exit 4
fi

# Проверка версии системы
OS="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
VERSION="$(lsb_release -rs | cut -d '.' -f1)"
CODENAME="$(lsb_release -cs)"
ARCH="$(dpkg --print-architecture)"

if [[ "$OS" == 'debian' ]]; then
	if (( VERSION < 13 )); then
		echo "Error: Debian $VERSION is not supported! Minimal supported version is 13"
		exit 5
	fi
elif [[ "$OS" == 'ubuntu' ]]; then
	if (( VERSION < 24 )); then
		echo "Error: Ubuntu $VERSION is not supported! Minimal supported version is 24"
		exit 6
	fi
else
	echo "Error: Your Linux distribution ($OS) is not supported!"
	exit 7
fi

# Очистка диска
echo 'Cleaning disk, please wait...'
journalctl --vacuum-size=1B -q
find /var/log -name "*.gz" -delete
find /var/log -name "*.1" -delete
find /var/log -type f -exec truncate -s 0 {} + || true
[[ -d /etc/openvpn/server/logs ]] && find /etc/openvpn/server/logs -type f -exec truncate -s 0 {} + || true
apt-get clean >/dev/null

# Проверка свободного места (минимум 2Гб)
if [[ $(df --output=avail / | tail -n 1) -lt $((2 * 1024 * 1024)) ]]; then
	echo 'Error: Low disk space! You need 2GB of free space!'
	exit 8
fi

# Проверка наличия сетевого интерфейса и IPv4-адреса
DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \K\S+')" || true
if [[ -z "$DEFAULT_INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 9
fi

DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \K\S+')" || true
if [[ -z "$DEFAULT_IP" ]]; then
	echo 'Default IPv4 address not found!'
	exit 10
fi

echo
echo -e '\e[1;32mInstalling AntiZapret VPN + full VPN...\e[0m'
echo 'OpenVPN + WireGuard + AmneziaWG'
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'
echo

echo 'Detecting path MTU via ping to Cloudflare WARP (engage.cloudflareclient.com)...'
DEFAULT_MTU=1280
for size in $(seq 1472 -1 1252); do
	mtu=$((size + 28))
	if ping -4 -n -M do -s "$size" -c 1 -W 1 engage.cloudflareclient.com >/dev/null 2>&1; then
		DEFAULT_MTU=$mtu
		break
	fi
done
MTU=$((DEFAULT_MTU - 60))
(( MTU > 1420 )) && MTU=1420
(( MTU < 1280 )) && MTU=1280
else
	# Система не меняется: берём рекомендуемые значения MTU по умолчанию
	DEFAULT_MTU=1420
	MTU=$((DEFAULT_MTU - 60))
fi

# Спрашиваем о настройках
# Случайный endpoint считается ОДИН раз: в plain-ветке он нужен для -i, в whiptail — как дефолт
WARP_ENDPOINT_DEFAULT="162.159.192.$((RANDOM % 254 + 1)):500"

# В whiptail-режиме вопросы задаются диалогами, порядок/тексты/дефолты как в апстриме
if [[ $AZ_UI == whiptail ]]; then
	ask_num MTU "Detected server path MTU: $DEFAULT_MTU
Recommended OpenVPN/WireGuard/WARP path MTU is $MTU

OpenVPN/WireGuard path MTU [1280-1420]:" 1280 1420 "$MTU"
	ask_num WARP_MTU 'Cloudflare WARP path MTU [1280-1420]:' 1280 1420 "$MTU"
	ask_yn OPENVPN_UDP_ENABLE 'Enable OpenVPN UDP? [y/n]:' y
	ask_yn OPENVPN_TCP_ENABLE 'Enable OpenVPN TCP? [y/n]:' n
	ask_yn WIREGUARD_ENABLE 'Enable WireGuard/AmneziaWG? [y/n]:' y
	ask_menu OPENVPN_PATCH 'Choose anti-censorship patch for OpenVPN (UDP only):
Version choice [1-4]:' 2 --noitem \
		1 'None        - Do not install anti-censorship patch, or remove if already installed' \
		2 'Random      - Recommended by default, randomly selects Strong or Error-Free' \
		3 'Strong      - Better protocol masking' \
		4 'Error-Free  - Use if Strong patch causes connection error, recommended for routers'
	ask_yn OPENVPN_DCO 'OpenVPN DCO lowers CPU load, boosts data speeds, and only supports AES-128-GCM, AES-256-GCM and CHACHA20-POLY1305 encryption

Turn on OpenVPN DCO? [y/n]:' y
	ask_menu ANTIZAPRET_WARP $'Choose Cloudflare WARP for \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*) outbound traffic:\nWARP choice [1-4]:' 4 --noitem \
		1 'None    - Do not use' \
		2 'All     - Route all AntiZapret VPN traffic (domains and IPs)' \
		3 'Domain  - Route AntiZapret domains and config/include-warp-hosts.txt, excluding config/exclude-warp-hosts.txt' \
		4 'Custom  - Route domains only from config/include-warp-hosts.txt, excluding config/exclude-warp-hosts.txt'
	ask_menu VPN_WARP $'Choose Cloudflare WARP for \001\e[1;32m\002full VPN\001\e[0m\002 (vpn-*) outbound traffic:\nWARP choice [1-3]:' 2 --noitem \
		1 'None    - Do not use' \
		2 'All     - Route all full VPN traffic (domains and IPs)' \
		3 'Custom  - Route domains only from config/include-warp-hosts.txt, excluding config/exclude-warp-hosts.txt'
	ask_yn WARP_PROTECTION $'Warning! WARP protection blocks \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 and \001\e[1;32m\002full VPN\001\e[0m\002 traffic if WARP failed to connect!\n\nEnable WARP protection? [y/n]:' y
	ask_text WARP_ENDPOINT 'Custom Cloudflare WARP endpoint (host:port):
Enter empty to set default endpoint' "$WARP_ENDPOINT_DEFAULT" '^([^:]+:[0-9]+)?$'
	ask_menu ANTIZAPRET_DNS $'Choose DNS resolvers for \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*):\nDNS choice [1-6]:\n\n  * - DNS resolvers support EDNS Client Subnet\n ** - Enable additional proxying and hide this server IP on some internet resources\n     Use only if this server is geolocated in Russia or problems\n     accessing some internet resources' 1 --noitem \
		1 'MSK-IX+NSDI      - DNS resolvers optimized for users located in Russia, recommended by default (+BI.ZONE +TransTeleCom +Cloudflare +Quad9 +ControlD +UltraDNS)' \
		2 'Cloudflare+Quad9  - Use if default choice fails to resolve domains (+ControlD +UltraDNS)' \
		3 'Yandex *         - Use if previous choice fails to resolve domains' \
		4 'Google *         - Use if previous choice fails to resolve domains' \
		5 'AdGuard *        - Use for blocking ads, trackers, malware and phishing websites' \
		6 'GeoHide **       - More details: https://geohide.ru'
	ask_menu VPN_DNS $'Choose DNS resolvers for \001\e[1;32m\002full VPN\001\e[0m\002 (vpn-*):\nDNS choice [1-2]:' 1 --noitem \
		1 'Self-hosted        - Use previous choice for AntiZapret VPN, recommended by default' \
		2 'Cloudflare/Custom  - Disables replacement answer from self-hosted DNS, allows custom DNS'
	ask_yn DNS_WARP $'Answer "y" if selected DNS resolvers are blocked or unreachable\n\nRoute all DNS outbound queries via Cloudflare WARP? [y/n]:' n
	ask_yn ANTIZAPRET_ADBLOCK $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*) based on AdGuard and OISD rules? [y/n]:' y
	ask_yn VPN_ADBLOCK $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002full VPN\001\e[0m\002 (vpn-*) based on AdGuard and OISD rules? [y/n]:' n
	ask_yn ALTERNATIVE_CLIENT_IP $'Default CLIENT IP address range:     10.28.0.0/15\nAlternative CLIENT IP address range: 172.28.0.0/15\n\nUse alternative CLIENT IP address range? [y/n]:' n
	if [[ $ALTERNATIVE_CLIENT_IP == 'y' ]]; then IP=172; else IP=10; fi
	ask_yn ALTERNATIVE_FAKE_IP "Default FAKE IP address range:     $IP.30.0.0/15
Alternative FAKE IP address range: 198.18.0.0/15

Use alternative range of FAKE IP addresses? [y/n]:" y
	ask_yn OPENVPN_BACKUP_UDP 'Use UDP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]:' y
	ask_yn OPENVPN_BACKUP_TCP 'Use TCP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]:' n
	ask_yn WIREGUARD_BACKUP 'Use UDP ports 540, 580 as backup for WireGuard/AmneziaWG connections? [y/n]:' y
	ask_yn OPENVPN_DUPLICATE 'Allow multiple clients connecting to OpenVPN using same profile file (*.ovpn)? [y/n]:' y
	ask_yn OPENVPN_LOG 'Enable detailed logs and status in OpenVPN? [y/n]:' n
	ask_yn SSH_PROTECTION $'Warning! SSH protection may block your IP after 5 logins/minute!\n\nEnable SSH brute-force protection? [y/n]:' y
	ask_yn ATTACK_PROTECTION $'Warning! Attack protection may block VPN or third-party applications!\n\nEnable network attack protection? [y/n]:' y
	ask_yn SCAN_PROTECTION $'Warning! Scan protection blocks ping and closed-port replies!\n\nEnable network scan protection? [y/n]:' y
	ask_yn FLOOD_PROTECTION $'Warning! Flood protection limits new connections and DNS queries per VPN client!\n\nEnable VPN client flood protection? [y/n]:' y
	ask_yn TORRENT_GUARD $'Warning! Torrent guard blocks VPN traffic for 1 minute on torrent detection!\n\nEnable torrent guard for \001\e[1;32m\002full VPN\001\e[0m\002? [y/n]:' y
	ask_yn RESTRICT_FORWARD $'Restrict forwarding in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]:' y
	ask_yn CLIENT_ISOLATION $'Enable \001\e[1;32m\002all VPN\001\e[0m\002 client and server isolation? [y/n]:' y
	ask_text OPENVPN_HOST 'Enter valid domain name for this OpenVPN server or press Enter to skip:' '' '' host
	ask_text WIREGUARD_HOST 'Enter valid domain name for this WireGuard/AmneziaWG server or press Enter to skip:' '' '' host
	ask_yn RECONNECT_WARP 'Reconnect all WARP connections after parse.sh/doall.sh and every night? [y/n]:' y
	ask_yn CLEAR_DNS_CACHE 'Clear Knot Resolver DNS cache after parse.sh/doall.sh and every night? [y/n]:' y
	ask_yn CLEAR_HOSTS $'Remove spam domains (casino, bookmaker, etc) from \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]:' y
	ask_yn ROUTE_ALL $'Route all domains via \001\e[1;32m\002AntiZapret VPN\001\e[0m\002, excluding Russian domains and config/exclude-hosts.txt? [y/n]:' n
	ask_yn CLOUDFLARE_INCLUDE $'Include Cloudflare IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]:' y
	ask_yn TELEGRAM_INCLUDE $'Include Telegram IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]:' y
	ask_yn WHATSAPP_INCLUDE $'Include WhatsApp IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]:' y
else
echo "Detected server path MTU: $DEFAULT_MTU"
echo "Recommended OpenVPN/WireGuard/WARP path MTU is $MTU"
echo
read -rp 'OpenVPN/WireGuard path MTU [1280-1420]: ' -e -i "$MTU" MTU
until [[ "$MTU" =~ ^[0-9]+$ ]] && (( MTU >= 1280 && MTU <= 1420 )); do
	read -rp 'OpenVPN/WireGuard path MTU [1280-1420]: ' -e -i "$MTU" MTU
done
echo
until [[ "$WARP_MTU" =~ ^[0-9]+$ ]] && (( WARP_MTU >= 1280 && WARP_MTU <= 1420 )); do
	read -rp 'Cloudflare WARP path MTU [1280-1420]: ' -e -i "$MTU" WARP_MTU
done
echo
until [[ "$OPENVPN_UDP_ENABLE" =~ (y|n) ]]; do
	read -rp 'Enable OpenVPN UDP? [y/n]: ' -e -i y OPENVPN_UDP_ENABLE
done
echo
until [[ "$OPENVPN_TCP_ENABLE" =~ (y|n) ]]; do
	read -rp 'Enable OpenVPN TCP? [y/n]: ' -e -i n OPENVPN_TCP_ENABLE
done
echo
until [[ "$WIREGUARD_ENABLE" =~ (y|n) ]]; do
	read -rp 'Enable WireGuard/AmneziaWG? [y/n]: ' -e -i y WIREGUARD_ENABLE
done
echo
echo 'Choose anti-censorship patch for OpenVPN (UDP only):'
echo '    1) None        - Do not install anti-censorship patch, or remove if already installed'
echo '    2) Random      - Recommended by default, randomly selects Strong or Error-Free'
echo '    3) Strong      - Better protocol masking'
echo '    4) Error-Free  - Use if Strong patch causes connection error, recommended for routers'
until [[ "$OPENVPN_PATCH" =~ ^[1-4]$ ]]; do
	read -rp 'Version choice [1-4]: ' -e -i 2 OPENVPN_PATCH
done
echo
echo 'OpenVPN DCO lowers CPU load, boosts data speeds, and only supports AES-128-GCM, AES-256-GCM and CHACHA20-POLY1305 encryption'
until [[ "$OPENVPN_DCO" =~ (y|n) ]]; do
	read -rp 'Turn on OpenVPN DCO? [y/n]: ' -e -i y OPENVPN_DCO
done
echo
echo -e 'Choose Cloudflare WARP for \e[1;32mAntiZapret VPN\e[0m (antizapret-*) outbound traffic:'
echo '    1) None    - Do not use'
echo '    2) All     - Route all AntiZapret VPN traffic (domains and IPs)'
echo '    3) Domain  - Route AntiZapret domains and config/include-warp-hosts.txt, excluding config/exclude-warp-hosts.txt'
echo '    4) Custom  - Route domains only from config/include-warp-hosts.txt, excluding config/exclude-warp-hosts.txt'
until [[ "$ANTIZAPRET_WARP" =~ ^[1-4]$ ]]; do
	read -rp 'WARP choice [1-4]: ' -e -i 4 ANTIZAPRET_WARP
done
echo
echo -e 'Choose Cloudflare WARP for \e[1;32mfull VPN\e[0m (vpn-*) outbound traffic:'
echo '    1) None    - Do not use'
echo '    2) All     - Route all full VPN traffic (domains and IPs)'
echo '    3) Custom  - Route domains only from config/include-warp-hosts.txt, excluding config/exclude-warp-hosts.txt'
until [[ "$VPN_WARP" =~ ^[1-3]$ ]]; do
	read -rp 'WARP choice [1-3]: ' -e -i 2 VPN_WARP
done
echo
echo -e 'Warning! WARP protection blocks \e[1;32mAntiZapret VPN\e[0m and \e[1;32mfull VPN\e[0m traffic if WARP failed to connect!'
until [[ "$WARP_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable WARP protection? [y/n]: ' -e -i y WARP_PROTECTION
done
echo
echo 'Enter empty to set default endpoint'
read -rp 'Custom Cloudflare WARP endpoint (host:port): ' -e -i "$WARP_ENDPOINT_DEFAULT" WARP_ENDPOINT
until [[ -z "$WARP_ENDPOINT" || "$WARP_ENDPOINT" =~ ^[^:]+:[0-9]+$ ]]; do
	read -rp 'Custom Cloudflare WARP endpoint (host:port): ' -e -i "$WARP_ENDPOINT_DEFAULT" WARP_ENDPOINT
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mAntiZapret VPN\e[0m (antizapret-*):'
echo '    1) MSK-IX+NSDI      - DNS resolvers optimized for users located in Russia, recommended by default'
echo '       +BI.ZONE+TransTeleCom'
echo '       +Cloudflare+Quad9'
echo '       +ControlD+UltraDNS'
echo '    2) Cloudflare+Quad9  - Use if default choice fails to resolve domains'
echo '       +ControlD+UltraDNS'
echo '    3) Yandex *         - Use if previous choice fails to resolve domains'
echo '    4) Google *         - Use if previous choice fails to resolve domains'
echo '    5) AdGuard *        - Use for blocking ads, trackers, malware and phishing websites'
echo '    6) GeoHide **       - More details: https://geohide.ru'
echo '  * - DNS resolvers support EDNS Client Subnet'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$ANTIZAPRET_DNS" =~ ^[1-6]$ ]]; do
	read -rp 'DNS choice [1-6]: ' -e -i 1 ANTIZAPRET_DNS
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mfull VPN\e[0m (vpn-*):'
echo '    1) Self-hosted        - Use previous choice for AntiZapret VPN, recommended by default'
echo '    2) Cloudflare/Custom  - Disables replacement answer from self‑hosted DNS, allows custom DNS'
until [[ "$VPN_DNS" =~ ^[1-2]$ ]]; do
	read -rp 'DNS choice [1-2]: ' -e -i 1 VPN_DNS
done
echo
echo 'Answer "y" if selected DNS resolvers are blocked or unreachable'
until [[ "$DNS_WARP" =~ (y|n) ]]; do
	read -rp 'Route all DNS outbound queries via Cloudflare WARP? [y/n]: ' -e -i n DNS_WARP
done
echo
until [[ "$ANTIZAPRET_ADBLOCK" =~ (y|n) ]]; do
	read -rp $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*) based on AdGuard and OISD rules? [y/n]: ' -e -i y ANTIZAPRET_ADBLOCK
done
echo
until [[ "$VPN_ADBLOCK" =~ (y|n) ]]; do
	read -rp $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002full VPN\001\e[0m\002 (vpn-*) based on AdGuard and OISD rules? [y/n]: ' -e -i n VPN_ADBLOCK
done
echo
echo 'Default CLIENT IP address range:     10.28.0.0/15'
echo 'Alternative CLIENT IP address range: 172.28.0.0/15'
until [[ "$ALTERNATIVE_CLIENT_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative CLIENT IP address range? [y/n]: ' -e -i n ALTERNATIVE_CLIENT_IP
done
echo
[[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]] && IP=172 || IP=10
echo "Default FAKE IP address range:     $IP.30.0.0/15"
echo 'Alternative FAKE IP address range: 198.18.0.0/15'
until [[ "$ALTERNATIVE_FAKE_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative range of FAKE IP addresses? [y/n]: ' -e -i y ALTERNATIVE_FAKE_IP
done
echo
until [[ "$OPENVPN_BACKUP_UDP" =~ (y|n) ]]; do
	read -rp 'Use UDP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: ' -e -i y OPENVPN_BACKUP_UDP
done
echo
until [[ "$OPENVPN_BACKUP_TCP" =~ (y|n) ]]; do
	read -rp 'Use TCP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: ' -e -i n OPENVPN_BACKUP_TCP
done
echo
until [[ "$WIREGUARD_BACKUP" =~ (y|n) ]]; do
	read -rp 'Use UDP ports 540, 580 as backup for WireGuard/AmneziaWG connections? [y/n]: ' -e -i y WIREGUARD_BACKUP
done
echo
until [[ "$OPENVPN_DUPLICATE" =~ (y|n) ]]; do
	read -rp 'Allow multiple clients connecting to OpenVPN using same profile file (*.ovpn)? [y/n]: ' -e -i y OPENVPN_DUPLICATE
done
echo
until [[ "$OPENVPN_LOG" =~ (y|n) ]]; do
	read -rp 'Enable detailed logs and status in OpenVPN? [y/n]: ' -e -i n OPENVPN_LOG
done
echo
echo 'Warning! SSH protection may block your IP after 5 logins/minute!'
until [[ "$SSH_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable SSH brute-force protection? [y/n]: ' -e -i y SSH_PROTECTION
done
echo
echo 'Warning! Attack protection may block VPN or third-party applications!'
until [[ "$ATTACK_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network attack protection? [y/n]: ' -e -i y ATTACK_PROTECTION
done
echo
echo 'Warning! Scan protection blocks ping and closed-port replies!'
until [[ "$SCAN_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network scan protection? [y/n]: ' -e -i y SCAN_PROTECTION
done
echo
echo 'Warning! Flood protection limits new connections and DNS queries per VPN client!'
until [[ "$FLOOD_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable VPN client flood protection? [y/n]: ' -e -i y FLOOD_PROTECTION
done
echo
echo 'Warning! Torrent guard blocks VPN traffic for 1 minute on torrent detection!'
until [[ "$TORRENT_GUARD" =~ (y|n) ]]; do
	read -rp $'Enable torrent guard for \001\e[1;32m\002full VPN\001\e[0m\002? [y/n]: ' -e -i y TORRENT_GUARD
done
echo
until [[ "$RESTRICT_FORWARD" =~ (y|n) ]]; do
	read -rp $'Restrict forwarding in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]: ' -e -i y RESTRICT_FORWARD
done
echo
until [[ "$CLIENT_ISOLATION" =~ (y|n) ]]; do
	read -rp $'Enable \001\e[1;32m\002all VPN\001\e[0m\002 client and server isolation? [y/n]: ' -e -i y CLIENT_ISOLATION
done
echo
while read -rp 'Enter valid domain name for this OpenVPN server or press Enter to skip: ' -e OPENVPN_HOST
do
	[[ -z "$OPENVPN_HOST" ]] && break
	[[ -n $(getent ahostsv4 "$OPENVPN_HOST") ]] && break
done
echo
while read -rp 'Enter valid domain name for this WireGuard/AmneziaWG server or press Enter to skip: ' -e WIREGUARD_HOST
do
	[[ -z "$WIREGUARD_HOST" ]] && break
	[[ -n $(getent ahostsv4 "$WIREGUARD_HOST") ]] && break
done
echo
until [[ "$RECONNECT_WARP" =~ (y|n) ]]; do
	read -rp 'Reconnect all WARP connections after parse.sh/doall.sh and every night? [y/n]: ' -e -i y RECONNECT_WARP
done
echo
until [[ "$CLEAR_DNS_CACHE" =~ (y|n) ]]; do
	read -rp 'Clear Knot Resolver DNS cache after parse.sh/doall.sh and every night? [y/n]: ' -e -i y CLEAR_DNS_CACHE
done
echo
until [[ "$CLEAR_HOSTS" =~ (y|n) ]]; do
	read -rp $'Remove spam domains (casino, bookmaker, etc) from \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y CLEAR_HOSTS
done
echo
until [[ "$ROUTE_ALL" =~ (y|n) ]]; do
	read -rp $'Route all domains via \001\e[1;32m\002AntiZapret VPN\001\e[0m\002, excluding Russian domains and config/exclude-hosts.txt? [y/n]: ' -e -i n ROUTE_ALL
done
echo
#until [[ "$DISCORD_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Discord voice IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n DISCORD_INCLUDE
#done
#echo
until [[ "$CLOUDFLARE_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Cloudflare IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y CLOUDFLARE_INCLUDE
done
echo
until [[ "$TELEGRAM_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Telegram IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y TELEGRAM_INCLUDE
done
echo
until [[ "$WHATSAPP_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include WhatsApp IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y WHATSAPP_INCLUDE
done
echo
#until [[ "$ROBLOX_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Roblox IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n ROBLOX_INCLUDE
#done
#echo
#until [[ "$AMAZON_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Amazon IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AMAZON_INCLUDE
#done
#echo
#until [[ "$HETZNER_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Hetzner IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n HETZNER_INCLUDE
#done
#echo
#until [[ "$DIGITALOCEAN_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include DigitalOcean IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n DIGITALOCEAN_INCLUDE
#done
#echo
#until [[ "$OVH_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include OVH IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n OVH_INCLUDE
#done
#echo
#until [[ "$GOOGLE_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Google IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n GOOGLE_INCLUDE
#done
#echo
#until [[ "$AKAMAI_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Akamai IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AKAMAI_INCLUDE
#done
#echo
fi

# Единый writer файла настроек: из него берут и предпросмотр, и сама установка
write_setup_file() {
	cat <<SETUP_EOF
SETUP_DATE=$(date --iso-8601=seconds)
MTU=$MTU
WARP_MTU=$WARP_MTU
OPENVPN_UDP_ENABLE=$OPENVPN_UDP_ENABLE
OPENVPN_TCP_ENABLE=$OPENVPN_TCP_ENABLE
WIREGUARD_ENABLE=$WIREGUARD_ENABLE
OPENVPN_PATCH=$OPENVPN_PATCH
OPENVPN_DCO=$OPENVPN_DCO
ANTIZAPRET_WARP=$ANTIZAPRET_WARP
ANTIZAPRET_WARP_PRIVATE_KEY=
ANTIZAPRET_WARP_PUBLIC_KEY=
ANTIZAPRET_WARP_ENDPOINT=
ANTIZAPRET_WARP_ADDRESS=
VPN_WARP=$VPN_WARP
VPN_WARP_PRIVATE_KEY=
VPN_WARP_PUBLIC_KEY=
VPN_WARP_ENDPOINT=
VPN_WARP_ADDRESS=
DNS_WARP=$DNS_WARP
DNS_WARP_PRIVATE_KEY=
DNS_WARP_PUBLIC_KEY=
DNS_WARP_ENDPOINT=
DNS_WARP_ADDRESS=
WARP_ENDPOINT=$WARP_ENDPOINT
WARP_PROTECTION=$WARP_PROTECTION
ANTIZAPRET_DNS=$ANTIZAPRET_DNS
VPN_DNS=$VPN_DNS
ANTIZAPRET_ADBLOCK=$ANTIZAPRET_ADBLOCK
VPN_ADBLOCK=$VPN_ADBLOCK
ALTERNATIVE_CLIENT_IP=$ALTERNATIVE_CLIENT_IP
ALTERNATIVE_FAKE_IP=$ALTERNATIVE_FAKE_IP
OPENVPN_BACKUP_UDP=$OPENVPN_BACKUP_UDP
OPENVPN_BACKUP_TCP=$OPENVPN_BACKUP_TCP
WIREGUARD_BACKUP=$WIREGUARD_BACKUP
OPENVPN_DUPLICATE=$OPENVPN_DUPLICATE
OPENVPN_LOG=$OPENVPN_LOG
SSH_PROTECTION=$SSH_PROTECTION
ATTACK_PROTECTION=$ATTACK_PROTECTION
SCAN_PROTECTION=$SCAN_PROTECTION
FLOOD_PROTECTION=$FLOOD_PROTECTION
TORRENT_GUARD=$TORRENT_GUARD
RESTRICT_FORWARD=$RESTRICT_FORWARD
CLIENT_ISOLATION=$CLIENT_ISOLATION
OPENVPN_HOST=$OPENVPN_HOST
WIREGUARD_HOST=$WIREGUARD_HOST
RECONNECT_WARP=$RECONNECT_WARP
CLEAR_DNS_CACHE=$CLEAR_DNS_CACHE
CLEAR_HOSTS=$CLEAR_HOSTS
ROUTE_ALL=$ROUTE_ALL
DISCORD_INCLUDE=$DISCORD_INCLUDE
CLOUDFLARE_INCLUDE=$CLOUDFLARE_INCLUDE
TELEGRAM_INCLUDE=$TELEGRAM_INCLUDE
WHATSAPP_INCLUDE=$WHATSAPP_INCLUDE
ROBLOX_INCLUDE=$ROBLOX_INCLUDE
AMAZON_INCLUDE=$AMAZON_INCLUDE
HETZNER_INCLUDE=$HETZNER_INCLUDE
DIGITALOCEAN_INCLUDE=$DIGITALOCEAN_INCLUDE
OVH_INCLUDE=$OVH_INCLUDE
GOOGLE_INCLUDE=$GOOGLE_INCLUDE
AKAMAI_INCLUDE=$AKAMAI_INCLUDE
DEFAULT_INTERFACE=
DEFAULT_IP=
ANTIZAPRET_OUT_INTERFACE=
ANTIZAPRET_OUT_IP=
VPN_OUT_INTERFACE=
VPN_OUT_IP=
CLIENT_IP=
FAKE_IP=
SETUP_EOF
}

if [[ $QUESTIONS_ONLY == 1 ]]; then
	write_setup_file
	exit 0
fi

if [[ $AZ_UI == whiptail ]]; then
	SETUP_PREVIEW=$(mktemp)
	trap 'rm -f "$SETUP_PREVIEW"' EXIT
	write_setup_file > "$SETUP_PREVIEW"
	wt_textbox "$SETUP_PREVIEW"
	PROCEED=
	ask_yn PROCEED 'Proceed with installation?' y
	if [[ $PROCEED != y ]]; then
		exit 1
	fi
fi
echo 'Installation, please wait...'

# Остановим и выключим обновляемые службы
systemctl disable --now kresd@1 || true
systemctl disable --now kresd@2 || true
systemctl disable --now kresd@3 || true
systemctl disable --now antizapret || true
systemctl disable --now antizapret-update.timer || true
systemctl disable --now antizapret-update || true
systemctl disable --now openvpn-server@antizapret-udp || true
systemctl disable --now openvpn-server@vpn-udp || true
systemctl disable --now openvpn-server@antizapret-tcp || true
systemctl disable --now openvpn-server@vpn-tcp || true
systemctl disable --now wg-quick@antizapret || true
systemctl disable --now wg-quick@vpn || true

# Починим сломанные пакеты
rm -rf /etc/apt/sources.list.d/cznic-labs-knot-resolver.list
rm -rf /etc/apt/sources.list.d/openvpn-aptrepo.list
rm -rf /etc/apt/sources.list.d/backports.list
dpkg --configure -a --force-confdef --force-confold
apt-get update
apt-get install -f -y

# Удалим ненужные службы
dpkg -s ufw &>/dev/null && apt-get purge -y ufw
dpkg -s firewalld &>/dev/null && apt-get purge -y firewalld
dpkg -s apparmor &>/dev/null && apt-get purge -y apparmor
dpkg -s apport &>/dev/null && apt-get purge -y apport
dpkg -s modemmanager &>/dev/null && apt-get purge -y modemmanager
dpkg -s snapd &>/dev/null && apt-get purge -y snapd
dpkg -s upower &>/dev/null && apt-get purge -y upower
dpkg -s multipath-tools &>/dev/null && apt-get purge -y multipath-tools
dpkg -s rsyslog &>/dev/null && apt-get purge -y rsyslog
dpkg -s udisks2 &>/dev/null && apt-get purge -y udisks2
dpkg -s tuned &>/dev/null && apt-get purge -y tuned
dpkg -s sysstat &>/dev/null && apt-get purge -y sysstat
dpkg -s acpid &>/dev/null && apt-get purge -y acpid
dpkg -s fwupd &>/dev/null && apt-get purge -y fwupd
dpkg -s watchdog &>/dev/null && apt-get purge -y watchdog
dpkg -s pcscd &>/dev/null && apt-get purge -y pcscd
dpkg -s packagekit &>/dev/null && apt-get purge -y packagekit
dpkg -s thermald &>/dev/null && apt-get purge -y thermald
dpkg -s open-iscsi &>/dev/null && apt-get purge -y open-iscsi
dpkg -s ubuntu-drivers-common &>/dev/null && apt-get purge -y ubuntu-drivers-common
dpkg -s avahi-daemon &>/dev/null && apt-get purge -y avahi-daemon
dpkg -s accountsservice &>/dev/null && apt-get purge -y accountsservice
dpkg -s bolt &>/dev/null && apt-get purge -y bolt
dpkg -s plymouth &>/dev/null && apt-get purge -y plymouth
dpkg -s popularity-contest &>/dev/null && apt-get purge -y popularity-contest
dpkg -s whoopsie &>/dev/null && apt-get purge -y whoopsie
dpkg -s landscape-common &>/dev/null && apt-get purge -y landscape-common
dpkg -s canonical-livepatch &>/dev/null && apt-get purge -y canonical-livepatch
dpkg -s ppp &>/dev/null && apt-get purge -y ppp
dpkg -s speech-dispatcher &>/dev/null && apt-get purge -y speech-dispatcher
dpkg -s brltty &>/dev/null && apt-get purge -y brltty
dpkg -s bluez &>/dev/null && apt-get purge -y bluez
dpkg -s bluetooth &>/dev/null && apt-get purge -y bluetooth
dpkg -s wpasupplicant &>/dev/null && apt-get purge -y wpasupplicant
dpkg -s cups &>/dev/null && apt-get purge -y cups
dpkg -s cups-browsed &>/dev/null && apt-get purge -y cups-browsed
dpkg -s cups-client &>/dev/null && apt-get purge -y cups-client
dpkg -s cups-daemon &>/dev/null && apt-get purge -y cups-daemon
dpkg -s cups-common &>/dev/null && apt-get purge -y cups-common
dpkg -s nfs-common &>/dev/null && apt-get purge -y nfs-common
dpkg -s rpcbind &>/dev/null && apt-get purge -y rpcbind
dpkg -s cifs-utils &>/dev/null && apt-get purge -y cifs-utils
dpkg -s ntfs-3g &>/dev/null && apt-get purge -y ntfs-3g
dpkg -s os-prober &>/dev/null && apt-get purge -y os-prober
dpkg -s laptop-detect &>/dev/null && apt-get purge -y laptop-detect
dpkg -s powermgmt-base &>/dev/null && apt-get purge -y powermgmt-base
dpkg -s xdg-user-dirs &>/dev/null && apt-get purge -y xdg-user-dirs
dpkg -s update-notifier-common &>/dev/null && apt-get purge -y update-notifier-common
dpkg -s at &>/dev/null && apt-get purge -y at
dpkg -s spice-vdagent &>/dev/null && apt-get purge -y spice-vdagent
dpkg -s libnss-mdns &>/dev/null && apt-get purge -y libnss-mdns
dpkg -s byobu &>/dev/null && apt-get purge -y byobu
dpkg -s ubuntu-advantage-tools &>/dev/null && apt-get purge -y ubuntu-advantage-tools
dpkg -s ubuntu-pro-client &>/dev/null && apt-get purge -y ubuntu-pro-client
dpkg -s pollinate &>/dev/null && apt-get purge -y pollinate
dpkg -s secureboot-db &>/dev/null && apt-get purge -y secureboot-db
dpkg -s telnet &>/dev/null && apt-get purge -y telnet
dpkg -s inetutils-telnet &>/dev/null && apt-get purge -y inetutils-telnet
dpkg -s ftp &>/dev/null && apt-get purge -y ftp
dpkg -s tnftp &>/dev/null && apt-get purge -y tnftp
dpkg -s lxd-installer &>/dev/null && apt-get purge -y lxd-installer
dpkg -s lxd-agent-loader &>/dev/null && apt-get purge -y lxd-agent-loader
dpkg -s openvpn-dco-dkms &>/dev/null && apt-get purge -y openvpn-dco-dkms
#dpkg -s pastebinit &>/dev/null && apt-get purge -y pastebinit

# Отключим ненужные службы
systemctl disable --now ifupdown-wait-online || true
systemctl disable --now setvtrgb || true
systemctl disable --now e2scrub_reap || true
systemctl disable --now systemd-pstore || true
systemctl disable --now motd-news.timer || true
#systemctl disable --now networkd-dispatcher
#systemctl disable --now secureboot-db

# SSH protection включён
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	dpkg -s fail2ban &>/dev/null && apt-get purge -y fail2ban
	dpkg -s sshguard &>/dev/null && apt-get purge -y sshguard
fi

# Удаляем кэш Knot Resolver
rm -rf /var/cache/knot-resolver/*
rm -rf /var/cache/knot-resolver2/*
rm -rf /var/cache/knot-resolver3/*

# Удаляем старые файлы OpenVPN и WireGuard
rm -rf /etc/openvpn/server/*
rm -rf /etc/openvpn/client/*
rm -rf /etc/wireguard/templates/*

# Удаляем скомпилированный патченный OpenVPN
if [[ -d /usr/local/src/openvpn ]]; then
	make -C /usr/local/src/openvpn uninstall || true
	rm -rf /usr/local/src/openvpn
fi

# Отключим IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 || true
sysctl -w net.ipv6.conf.lo.disable_ipv6=1 || true

# Удаляем переопределённые параметры ядра
[[ -f /etc/sysctl.conf ]] && sed -i '/^$/!{/^#/!d}' /etc/sysctl.conf

# Принудительная загрузка модуля nf_conntrack
echo 'nf_conntrack' > /etc/modules-load.d/nf_conntrack.conf

# Обновляем систему
dpkg --configure -a --force-confdef --force-confold
apt-get update
apt-get install -f -y
apt-get dist-upgrade -y --fix-missing -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
apt-get install -y curl gpg

# Папка для ключей
mkdir -p /etc/apt/keyrings

# Добавим репозиторий Knot Resolver
curl -fL --connect-timeout 30 https://pkg.labs.nic.cz/gpg -o /etc/apt/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/etc/apt/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $CODENAME main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

# Добавим репозиторий OpenVPN
curl -fL --connect-timeout 30 https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --yes --dearmor -o /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.7 $CODENAME main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

# Добавим репозиторий Debian Backports
if [[ "$OS" == 'debian' ]]; then
	echo "deb http://deb.debian.org/debian $CODENAME-backports main" > /etc/apt/sources.list.d/backports.list
fi

# Ставим необходимое ядро и пакеты
apt-get update
INSTALL=
# Обновляем ядро только на Ubuntu ниже 26 и Debian ниже 14
if [[ "$OS" == 'ubuntu' ]] && (( VERSION < 26 )); then
	INSTALL="linux-generic-hwe-${VERSION}.04"
elif [[ "$OS" == 'debian' ]] && (( VERSION < 14 )); then
	INSTALL="-t $CODENAME-backports linux-image-$ARCH linux-headers-$ARCH"
fi
apt-get install -y $INSTALL git openvpn iptables easy-rsa gawk knot-resolver idn sipcalc python3-pip wireguard diffutils socat lua-cqueues ipset irqbalance unattended-upgrades jq iproute2 nftables
systemctl disable --now openvpn
apt-get autoremove --purge -y
apt-get clean

# Конфигурируем пакеты
dpkg-reconfigure -f noninteractive unattended-upgrades
#git config --global http.version HTTP/1.1

# Клонируем репозиторий и устанавливаем dnslib
rm -rf /tmp/dnslib
git clone --depth 1 https://github.com/paulc/dnslib.git /tmp/dnslib
PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --force-reinstall --user /tmp/dnslib

# Клонируем репозиторий antizapret
rm -rf /tmp/antizapret
git clone --depth 1 https://github.com/GubernievS/AntiZapret-VPN.git /tmp/antizapret

# Сохраняем пользовательские настройки и обработчики custom*.sh
cp /root/antizapret/config/*.txt /tmp/antizapret/setup/root/antizapret/config/ || true
cp /root/antizapret/custom*.sh /tmp/antizapret/setup/root/antizapret/ || true
cp /etc/knot-resolver/custom*.lua /etc/knot-resolver/renumber*.lua /tmp/antizapret/setup/etc/knot-resolver/ || true

# Восстанавливаем из бэкапа пользовательские настройки и обработчики custom*.sh, пользователей OpenVPN и WireGuard
if [[ -e /root/backup*.tar.gz ]]; then
	rm -rf /root/easyrsa3
	rm -rf /root/wireguard
	rm -rf /root/config
	rm -rf /root/knot-resolver
	rm -rf /root/custom
fi

tar -xzf /root/backup*.tar.gz || true
rm -f /root/backup*.tar.gz || true

mkdir -p /tmp/antizapret/setup/etc/openvpn/easyrsa3
cp -r /root/easyrsa3/* /tmp/antizapret/setup/etc/openvpn/easyrsa3/ || true
cp /root/wireguard/* /tmp/antizapret/setup/etc/wireguard/ || true
cp /root/config/* /tmp/antizapret/setup/root/antizapret/config/ || true
cp /root/knot-resolver/* /tmp/antizapret/setup/etc/knot-resolver/ || true
cp /root/custom/* /tmp/antizapret/setup/root/antizapret/ || true

rm -rf /root/easyrsa3
rm -rf /root/wireguard
rm -rf /root/config
rm -rf /root/knot-resolver
rm -rf /root/custom

# Сохраняем настройки
write_setup_file > /tmp/antizapret/setup/root/antizapret/setup

# Создаем папки для кэша Knot Resolver
mkdir -p /var/cache/knot-resolver
mkdir -p /var/cache/knot-resolver2
mkdir -p /var/cache/knot-resolver3

# Выставляем разрешения
find /tmp/antizapret -type f -exec chmod 644 {} +
find /tmp/antizapret -type d -exec chmod 755 {} +
find /tmp/antizapret/setup/root/antizapret -type f -exec chmod +x {} +
find /tmp/antizapret/setup/etc/openvpn/server/scripts -type f -exec chmod +x {} +
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver2
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver3

# Копируем нужное, удаляем не нужное
rm -rf /root/antizapret
cp -r /tmp/antizapret/setup/* /
rm -rf /tmp/dnslib
rm -rf /tmp/antizapret

# Настраиваем DNS в AntiZapret VPN
if [[ "$ANTIZAPRET_DNS" != '1' ]]; then
	sed -i "s/local antizapret_dns = 1/local antizapret_dns = $ANTIZAPRET_DNS/" /etc/knot-resolver/kresd.conf
fi

# Настраиваем DNS в full VPN
if [[ "$VPN_DNS" == '1' && "$ANTIZAPRET_DNS" != '1' ]]; then
	sed -i "s/local vpn_dns = 2/local vpn_dns = $ANTIZAPRET_DNS/" /etc/knot-resolver/kresd.conf
fi

# Не используем альтернативный диапазон подменных IPv4-адресов
# 198.18.0.0/15 => 10.30.0.0/15 или 172.30.0.0/15
if [[ "$ALTERNATIVE_FAKE_IP" == 'n' ]]; then
	sed -i "s/198\.18\./${IP}\.30\./g" /root/antizapret/proxy.py
fi

# Используем альтернативный диапазон клиентских IPv4-адресов
# 10.28.0.0/15 => 172.28.0.0/15
if [[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]]; then
	sed -i 's/10\./172\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

# Настраиваем MTU в OpenVPN и WireGuard
if [[ "$MTU" != '1420' ]]; then
	sed -i "s/tun-mtu 1420/tun-mtu $MTU/" /etc/openvpn/server/*.conf
	sed -i "s/MTU = 1420/MTU = $MTU/" /etc/wireguard/templates/*.conf
fi

# Запрещаем несколько одновременных подключений к OpenVPN для одного клиента
if [[ "$OPENVPN_DUPLICATE" == 'n' ]]; then
	sed -i '/duplicate-cn/s/^/#/' /etc/openvpn/server/*.conf
fi

# Включим подробные логи и статус в OpenVPN
if [[ "$OPENVPN_LOG" == 'y' ]]; then
	sed -i '/^#\(verb\|log\|status\)/s/^#//' /etc/openvpn/server/*.conf
fi

# Изменяем поведение Knot Resolver
sed -i '/function policy\.PASS(state, _)/,/^end$/s/return state/return nil/' /usr/lib/knot-resolver/kres_modules/policy.lua
sed -i -z -E 's/policy\.DENY_MSG\([^)]*kres\.extended_error\.NOTSUP[^)]*\)/policy.DENY/g' /usr/lib/knot-resolver/kres_modules/policy.lua

# Загружаем и создаем списки исключений
/root/antizapret/doall.sh

# Настраиваем сервера OpenVPN и WireGuard/AmneziaWG для первого запуска
# Пересоздаем для всех существующих пользователей файлы подключений
# Если пользователей нет, то создаем новых пользователей 'antizapret-client' для OpenVPN и WireGuard/AmneziaWG
/root/antizapret/client.sh 7

# Включим обновляемые службы
systemctl enable kresd@1
systemctl enable kresd@2
systemctl enable kresd@3
systemctl enable antizapret
systemctl enable antizapret-update.timer
systemctl enable antizapret-update
if [[ "$OPENVPN_UDP_ENABLE" == 'y' ]]; then
	systemctl enable openvpn-server@antizapret-udp
	systemctl enable openvpn-server@vpn-udp
fi
if [[ "$OPENVPN_TCP_ENABLE" == 'y' ]]; then
	systemctl enable openvpn-server@antizapret-tcp
	systemctl enable openvpn-server@vpn-tcp
fi
if [[ "$WIREGUARD_ENABLE" == 'y' ]]; then
	systemctl enable wg-quick@antizapret
	systemctl enable wg-quick@vpn
fi

ERRORS=

if [[ "$OPENVPN_PATCH" != '1' ]]; then
	if ! /root/antizapret/patch-openvpn.sh "$OPENVPN_PATCH"; then
		ERRORS+="\n\e[1;31mAnti-censorship patch for OpenVPN has not installed!\e[0m Please run '/root/antizapret/patch-openvpn.sh' after rebooting\n"
	fi
fi

if [[ "$OPENVPN_DCO" == 'y' ]]; then
	if ! /root/antizapret/openvpn-dco.sh y; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not turn on!\e[0m Please run '/root/antizapret/openvpn-dco.sh y' after rebooting\n"
	fi
fi

# Если есть ошибки, выводим их
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

# Создадим файл подкачки размером 1 Гб если его нет
if [[ -z "$(swapon --show)" ]]; then
	set +e
	SWAPFILE=/swapfile
	SWAPSIZE=1024
	dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE
	chmod 600 $SWAPFILE
	mkswap $SWAPFILE
	swapon $SWAPFILE
	echo $SWAPFILE none swap sw 0 0 >> /etc/fstab
fi

# Перезагружаем
echo
echo -e '\e[1;32mAntiZapret VPN + full VPN installed successfully!\e[0m'
reboot