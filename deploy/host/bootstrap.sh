#!/usr/bin/env bash
# Styx 2 — one-time server preparation (Ubuntu 24.04 / Debian 12).
#
#   US/exit:   sudo bash deploy/host/bootstrap.sh exit
#   RU/entry:  curl -fsSL <raw-url>/deploy/host/bootstrap.sh | sudo bash -s entry "<control ssh pubkey>"
#
# Installs Docker (from distro repos: Docker Hub / download.docker.com are
# unreliable from Russia), tunes the kernel, prepares nftables, swap, log
# rotation, time sync and unattended security upgrades.
set -euo pipefail

ROLE="${1:-}"
CONTROL_PUBKEY="${2:-}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info() { echo -e "${G}[+]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
die()  { echo -e "${R}[x]${N} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запусти от root"
[[ "$ROLE" == "exit" || "$ROLE" == "entry" ]] || die "использование: bootstrap.sh exit|entry [ssh-pubkey]"

export DEBIAN_FRONTEND=noninteractive

info "пакеты"
apt-get update -qq
apt-get install -y -qq ca-certificates curl openssh-client nftables chrony rsync jq qrencode python3 \
    unattended-upgrades docker.io docker-compose-v2 >/dev/null

info "docker: ротация логов (и зеркало реестра на RU-ноде)"
mkdir -p /etc/docker
if [[ "$ROLE" == "entry" ]]; then
    # Docker Hub отдаёт 403 на российские IP — тянем образы через зеркало Google
    MIRRORS='"registry-mirrors": ["https://mirror.gcr.io"],'
else
    MIRRORS=''
fi
cat > /etc/docker/daemon.json <<JSON
{
  ${MIRRORS}
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
JSON
systemctl enable --now docker >/dev/null
systemctl restart docker

info "ядро: BBR, буферы UDP для QUIC, conntrack"
modprobe tcp_bbr 2>/dev/null || true
modprobe nf_conntrack 2>/dev/null || true
echo -e "tcp_bbr\nnf_conntrack" > /etc/modules-load.d/styx.conf
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /tmp)"
if [[ -f "$SCRIPT_DIR/sysctl.conf" ]]; then
    install -m 644 "$SCRIPT_DIR/sysctl.conf" /etc/sysctl.d/99-styx.conf
    sysctl -q --system >/dev/null 2>&1 || true
else
    warn "sysctl.conf будет применён при первом ./styxctl deploy"
fi

info "лимиты файлов"
mkdir -p /etc/systemd/system.conf.d
printf '[Manager]\nDefaultLimitNOFILE=1048576\n' > /etc/systemd/system.conf.d/styx.conf
systemctl daemon-reexec

info "nftables: подключаем /etc/nftables.d/*.nft"
mkdir -p /etc/nftables.d
if ! grep -q 'include "/etc/nftables.d/\*.nft"' /etc/nftables.conf 2>/dev/null; then
    echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
fi
systemctl enable nftables >/dev/null
if command -v ufw >/dev/null && ufw status | grep -q active; then
    warn "ufw выключен — firewall теперь управляется styxctl (nftables)"
    ufw disable >/dev/null
fi

info "swap (если RAM < 3 ГБ и swap нет)"
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [[ $MEM_MB -lt 3000 ]] && ! swapon --show | grep -q .; then
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

info "journald: максимум 300 МБ"
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=300M\n' > /etc/systemd/journald.conf.d/styx.conf
systemctl restart systemd-journald

info "время и автообновления безопасности"
systemctl enable --now chrony >/dev/null 2>&1 || true
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true

if [[ -n "$CONTROL_PUBKEY" ]]; then
    info "ключ управления styx-control добавлен в /root/.ssh/authorized_keys"
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    grep -qF "$CONTROL_PUBKEY" /root/.ssh/authorized_keys || echo "$CONTROL_PUBKEY" >> /root/.ssh/authorized_keys
fi

if [[ "$ROLE" == "exit" && "${SKIP_AWG:-0}" != "1" ]]; then
    info "AmneziaWG (ядерный модуль через DKMS, ppa:amnezia/ppa)"
    if apt-get install -y -qq software-properties-common "linux-headers-$(uname -r)" >/dev/null 2>&1 \
        && add-apt-repository -y ppa:amnezia/ppa >/dev/null 2>&1 \
        && apt-get update -qq && apt-get install -y -qq amneziawg >/dev/null 2>&1 \
        && modprobe amneziawg; then
        echo amneziawg >> /etc/modules-load.d/styx.conf
        info "AmneziaWG установлен: $(awg --version 2>/dev/null | head -1)"
    else
        warn "AmneziaWG не установился (нет headers для ядра хостера?). VLESS/Hysteria это не затрагивает. "
        warn "Решение: поставь стандартное ядро Ubuntu (linux-generic) и перезапусти bootstrap"
    fi
fi

if [[ "$ROLE" == "exit" ]]; then
    REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    info "таймеры: ежедневное обновление geo-баз и сертификата на RU-ноде"
    cat > /etc/systemd/system/styx-daily.service <<UNIT
[Unit]
Description=Styx 2 daily maintenance (geo databases, TLS cert sync)
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=${REPO_DIR}/deploy
ExecStart=/usr/bin/python3 ${REPO_DIR}/deploy/styxctl geo-update --deploy
ExecStartPost=/usr/bin/python3 ${REPO_DIR}/deploy/styxctl sync-certs
UNIT
    cat > /etc/systemd/system/styx-daily.timer <<UNIT
[Unit]
Description=Styx 2 daily maintenance

[Timer]
OnCalendar=*-*-* 04:20:00
RandomizedDelaySec=20m
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload
    systemctl enable styx-daily.timer >/dev/null
fi

echo
info "готово (${ROLE}). Ядро: $(uname -r), congestion: $(sysctl -n net.ipv4.tcp_congestion_control)"
if [[ "$ROLE" == "exit" ]]; then
    echo "Дальше: cd deploy && sudo ./styxctl init"
else
    echo "Дальше: вернись на US-ноду и запусти sudo ./styxctl deploy"
fi
