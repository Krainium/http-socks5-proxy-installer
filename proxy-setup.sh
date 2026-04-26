#!/usr/bin/env bash
# ─── CRLF self-fix (survives Windows git checkouts) ──────────────────────────
grep -q "$(printf '\r')" "$0" 2>/dev/null && { _f="/tmp/_psx_fix.$$"; tr -d '\r' < "$0" > "$_f" && mv "$_f" "$0" && exec bash "$0" "$@"; } #
# ─────────────────────────────────────────────────────────────────────────────
#  🌐🧦  proxy-setup  —  HTTP Proxy + SOCKS5 Proxy Installer
#  3proxy compiled from source · Config-file auth · Port Control · Multi-distro
#  Built by krainium. @2026
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
R="\033[0m";     BOLD="\033[1m";  DIM="\033[2m"
RED="\033[31m";  GRN="\033[32m";  YLW="\033[33m"
BLU="\033[34m";  MAG="\033[35m";  CYN="\033[36m"
WHT="\033[97m";  PUR="\033[38;5;135m";  ORG="\033[38;5;208m"

# ─── Logging helpers ──────────────────────────────────────────────────────────
info()       { echo -e "${BLU}${BOLD}  ℹ  ${R}${WHT}$*${R}"; }
ok()         { echo -e "${GRN}${BOLD}  ✔  ${R}${GRN}$*${R}"; }
warn()       { echo -e "${YLW}${BOLD}  ⚠  ${R}${YLW}$*${R}"; }
err()        { echo -e "${RED}${BOLD}  ✖  ${R}${RED}$*${R}"; }
fatal()      { echo -e "${RED}${BOLD}  ✖  ${R}${RED}$*${R}"; exit 1; }
step()       { echo -e "\n${CYN}${BOLD}  ▶  $*${R}"; }
divider()    { echo -e "${DIM}  ──────────────────────────────────────────────────${R}"; }
building()   { echo -e "${MAG}${BOLD}  🔨  ${R}${MAG}$*${R}"; }
installing() { echo -e "${MAG}${BOLD}  ⬇  ${R}${MAG}Installing $*...${R}"; }
prompt()     { echo -en "${CYN}${BOLD}  ➤  ${R}${WHT}$*${R}"; }
svc_line()   { echo -e "${ORG}${BOLD}  🔗  ${R}${WHT}$*${R}"; }
auth_line()  { echo -e "${PUR}${BOLD}  🔑  ${R}${WHT}$*${R}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && { echo -e "\n  Run as root:  sudo bash $0\n"; exit 1; }

# ─── Paths ────────────────────────────────────────────────────────────────────
PROXY_BIN="/usr/local/bin/3proxy"
PROXY_CFG="/etc/3proxy"
HTTP_CFG="${PROXY_CFG}/http.cfg"
SOCKS_CFG="${PROXY_CFG}/socks5.cfg"
PROXY_LOG="/var/log/3proxy"
HTTP_SVC="3proxy-http"
SOCKS_SVC="3proxy-socks5"
BUILD_SRC="/tmp/3proxy_build"

# ─── State ────────────────────────────────────────────────────────────────────
STATE_DIR="/etc/proxy-setup"
STATE_FILE="${STATE_DIR}/state.conf"

HTTP_PORT=8080;  HTTP_INSTALLED=0;  HTTP_AUTH=0;  HTTP_USER="";  HTTP_PASS=""
SOCKS_PORT=1080; SOCKS_INSTALLED=0; SOCKS_AUTH=0; SOCKS_USER=""; SOCKS_PASS=""

save_state() {
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
    cat > "$STATE_FILE" <<EOF
HTTP_PORT=${HTTP_PORT}
HTTP_INSTALLED=${HTTP_INSTALLED}
HTTP_AUTH=${HTTP_AUTH}
HTTP_USER=${HTTP_USER}
HTTP_PASS=${HTTP_PASS}
SOCKS_PORT=${SOCKS_PORT}
SOCKS_INSTALLED=${SOCKS_INSTALLED}
SOCKS_AUTH=${SOCKS_AUTH}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASS=${SOCKS_PASS}
EOF
    chmod 600 "$STATE_FILE"
}

load_state() { [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" || true; }

# ─── OS / package manager ─────────────────────────────────────────────────────
detect_os() {
    [[ -f /etc/os-release ]] && source /etc/os-release || true
    if   command -v apt-get &>/dev/null; then
        PM_UPDATE="apt-get update -qq"
        PM_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get install -y -qq"
    elif command -v dnf &>/dev/null; then
        PM_UPDATE="dnf check-update -q || true"; PM_INSTALL="dnf install -y -q"
    elif command -v yum &>/dev/null; then
        PM_UPDATE="yum check-update -q || true"; PM_INSTALL="yum install -y -q"
    elif command -v pacman &>/dev/null; then
        PM_UPDATE="pacman -Sy --noconfirm --quiet"; PM_INSTALL="pacman -S --noconfirm --quiet"
    else
        fatal "No supported package manager found."
    fi
}

# ─── Detection ────────────────────────────────────────────────────────────────
proxy_bin_ok()    { [[ -x "$PROXY_BIN" ]]; }
http_installed()  { proxy_bin_ok && [[ -f "$HTTP_CFG" ]]; }
socks_installed() { proxy_bin_ok && [[ -f "$SOCKS_CFG" ]]; }
http_running()    { systemctl is-active "$HTTP_SVC"  &>/dev/null 2>&1; }
socks_running()   { systemctl is-active "$SOCKS_SVC" &>/dev/null 2>&1; }

# ─── Port helpers ─────────────────────────────────────────────────────────────
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]; }

port_in_use() {
    ss -tlnp 2>/dev/null | awk '{print $4}' | grep -q ":${1}$" \
        || ss -ulnp 2>/dev/null | awk '{print $4}' | grep -q ":${1}$"
}

ask_port() {
    # ask_port <var_name> <default> — also rejects cross-proxy collision
    local _var="$1" _def="$2" _p=""
    prompt "Port [default ${_def}]: "; read -r _p
    if   [[ -z "${_p:-}" ]];   then _p="$_def"; info "Using default port ${_def}"
    elif ! valid_port "$_p";   then warn "Invalid port — using ${_def}"; _p="$_def"
    fi
    # Block collision with the sibling proxy's port
    if [[ "$_var" == "HTTP_PORT"  && "$_p" == "${SOCKS_PORT:-}" ]]; then
        warn "Port ${_p} is already used by the SOCKS5 proxy. Pick a different port."; return 1
    fi
    if [[ "$_var" == "SOCKS_PORT" && "$_p" == "${HTTP_PORT:-}"  ]]; then
        warn "Port ${_p} is already used by the HTTP proxy. Pick a different port."; return 1
    fi
    if port_in_use "$_p"; then
        warn "Port ${_p} is already in use by another process."
        prompt "Continue anyway? [y/N]: "; read -r _c
        [[ "${_c,,}" != "y" ]] && { info "Cancelled."; return 1; }
    fi
    printf -v "$_var" '%s' "$_p"
}

# ─── Credentials helper ───────────────────────────────────────────────────────
ask_credentials() {
    local _uvar="$1" _pvar="$2" _user="" _pass="" _pass2=""
    echo ""
    while [[ -z "$_user" ]]; do
        prompt "Username: "; read -r _user
        if   [[ -z "$_user" ]];                        then warn "Username cannot be empty."
        elif [[ "$_user" =~ [^a-zA-Z0-9_-] ]];        then warn "Letters, numbers, _ and - only."; _user=""
        fi
    done
    while true; do
        prompt "Password: "; read -rs _pass; echo ""
        if [[ -z "$_pass" ]]; then warn "Password cannot be empty."; continue; fi
        # 3proxy users line uses ':' as delimiter — reject it to prevent config injection
        if [[ "$_pass" == *':'* ]] || [[ "$_pass" =~ [[:space:]] ]]; then
            warn "Password must not contain ':' or spaces (3proxy config format restriction)."; continue
        fi
        prompt "Confirm  : "; read -rs _pass2; echo ""
        [[ "$_pass" != "$_pass2" ]] && { warn "Passwords do not match."; continue; }
        break
    done
    printf -v "$_uvar" '%s' "$_user"
    printf -v "$_pvar" '%s' "$_pass"
}

# ─── Build 3proxy from source ─────────────────────────────────────────────────
build_3proxy() {
    if proxy_bin_ok; then
        ok "3proxy binary already present at ${PROXY_BIN}"
        return 0
    fi

    detect_os

    step "Install build dependencies  (gcc · make · git)"
    eval "$PM_UPDATE" &>/dev/null || true
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc make git
    elif command -v dnf &>/dev/null; then
        dnf install -y -q gcc make git
    elif command -v yum &>/dev/null; then
        yum install -y -q gcc make git
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm --quiet base-devel git
    fi
    ok "Build tools ready"

    step "Clone 3proxy source"
    rm -rf "$BUILD_SRC"
    git clone --depth=1 https://github.com/3proxy/3proxy.git "$BUILD_SRC" \
        || fatal "git clone failed — check internet connection"
    ok "Source cloned"

    step "Compile  (this takes ~30 seconds)"
    building "make -f Makefile.Linux"
    if ! make -C "$BUILD_SRC" -f Makefile.Linux 2>&1 | tail -5; then
        rm -rf "$BUILD_SRC"
        fatal "Compilation failed — see errors above"
    fi
    ok "Compilation complete"

    step "Install binary  →  ${PROXY_BIN}"
    install -m 755 "${BUILD_SRC}/bin/3proxy" "$PROXY_BIN"
    rm -rf "$BUILD_SRC"
    ok "3proxy installed  ($(${PROXY_BIN} --help 2>&1 | head -1 || echo 'binary ready'))"
}

# ─── Write systemd service ────────────────────────────────────────────────────
_write_service() {
    local name="$1" cfg="$2" desc="$3"
    cat > "/etc/systemd/system/${name}.service" <<SVCEOF
[Unit]
Description=${desc}
After=network.target

[Service]
Type=simple
ExecStart=${PROXY_BIN} ${cfg}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
}

# ─── Firewall helper ──────────────────────────────────────────────────────────
_open_port() {
    local port="$1" proto="$2" label="$3"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${port}/${proto}" &>/dev/null || true
        ok "UFW: opened ${port}/${proto} for ${label}"
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/${proto}" &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
        ok "firewalld: opened ${port}/${proto} for ${label}"
    else
        iptables -A INPUT -p "${proto}" --dport "${port}" -j ACCEPT 2>/dev/null || true
        ok "iptables: opened ${port}/${proto} for ${label}"
    fi
}

# ─── Write 3proxy HTTP config ─────────────────────────────────────────────────
_write_http_cfg() {
    mkdir -p "$PROXY_CFG" "$PROXY_LOG"
    local auth_block
    if [[ "$HTTP_AUTH" == "1" ]]; then
        auth_block="auth strong
users ${HTTP_USER}:CL:${HTTP_PASS}
allow ${HTTP_USER}"
    else
        auth_block="auth none
allow *"
    fi
    cat > "$HTTP_CFG" <<HTTPCFG
# 3proxy — HTTP Proxy config
# Generated by proxy-setup.sh
nscache 65536
log ${PROXY_LOG}/http.log D
flush
${auth_block}
maxconn 100
proxy -p${HTTP_PORT} -i0.0.0.0
HTTPCFG
    chmod 600 "$HTTP_CFG"
    ok "Config written → ${HTTP_CFG}"
}

# ─── Write 3proxy SOCKS5 config ───────────────────────────────────────────────
_write_socks_cfg() {
    mkdir -p "$PROXY_CFG" "$PROXY_LOG"
    local auth_block
    if [[ "$SOCKS_AUTH" == "1" ]]; then
        auth_block="auth strong
users ${SOCKS_USER}:CL:${SOCKS_PASS}
allow ${SOCKS_USER}"
    else
        auth_block="auth none
allow *"
    fi
    cat > "$SOCKS_CFG" <<SOCKSCFG
# 3proxy — SOCKS5 config
# Generated by proxy-setup.sh
log ${PROXY_LOG}/socks5.log D
flush
${auth_block}
maxconn 100
socks -p${SOCKS_PORT} -i0.0.0.0
SOCKSCFG
    chmod 600 "$SOCKS_CFG"
    ok "Config written → ${SOCKS_CFG}"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    clear 2>/dev/null || true
    echo -e "${PUR}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║  🌐🧦  proxy-setup  —  HTTP + SOCKS5 Proxy Installer       ║"
    echo "  ║  🔨 Built from source  🔑 Auth  🔌 Port  📊 Management     ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${R}"
    load_state

    local bin_tag http_auth_tag socks_auth_tag
    proxy_bin_ok && bin_tag="${GRN}✔ built${R}" || bin_tag="${DIM}not built${R}"
    echo -e "  ${DIM}3proxy binary : ${R}${bin_tag}"

    if http_installed; then
        local s; s=$(http_running && echo "${GRN}● running${R}" || echo "${YLW}● stopped${R}")
        [[ "$HTTP_AUTH"  == "1" ]] && http_auth_tag="  ${PUR}🔑 auth${R}" || http_auth_tag="  ${DIM}open${R}"
        echo -e "  ${DIM}HTTP Proxy    : ${WHT}port ${HTTP_PORT}${R}${http_auth_tag}   ${s}"
    else
        echo -e "  ${DIM}HTTP Proxy    : ${DIM}not installed${R}"
    fi

    if socks_installed; then
        local s; s=$(socks_running && echo "${GRN}● running${R}" || echo "${YLW}● stopped${R}")
        [[ "$SOCKS_AUTH" == "1" ]] && socks_auth_tag="  ${PUR}🔑 auth${R}" || socks_auth_tag="  ${DIM}open${R}"
        echo -e "  ${DIM}SOCKS5 Proxy  : ${WHT}port ${SOCKS_PORT}${R}${socks_auth_tag}   ${s}"
    else
        echo -e "  ${DIM}SOCKS5 Proxy  : ${DIM}not installed${R}"
    fi
    echo ""
}

# ─── Install HTTP Proxy ───────────────────────────────────────────────────────
install_http() {
    step "Install HTTP Proxy  (3proxy — compiled from source)"
    divider

    if http_installed; then
        warn "HTTP proxy already configured on port ${HTTP_PORT}."
        prompt "Reinstall / reconfigure? [y/N]: "; read -r _r
        [[ "${_r,,}" != "y" ]] && { info "Skipped."; return; }
        systemctl stop "$HTTP_SVC" &>/dev/null || true
    fi

    # ── Port ──────────────────────────────────────────────────────────────────
    echo ""
    ask_port HTTP_PORT 8080 || return

    # ── Auth ──────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${PUR}${BOLD}  🔑 Authentication${R}"
    prompt "Require username and password? [y/N]: "; read -r _auth
    HTTP_AUTH=0; HTTP_USER=""; HTTP_PASS=""
    if [[ "${_auth,,}" == "y" ]]; then
        ask_credentials HTTP_USER HTTP_PASS
        HTTP_AUTH=1
        ok "Credentials set"
    else
        info "No authentication — proxy open to all"
    fi

    # ── Build 3proxy (only if not already built) ───────────────────────────────
    divider
    build_3proxy

    # ── Config ────────────────────────────────────────────────────────────────
    step "Write HTTP proxy config"
    _write_http_cfg

    # ── Systemd service ───────────────────────────────────────────────────────
    step "Register systemd service  (${HTTP_SVC})"
    _write_service "$HTTP_SVC" "$HTTP_CFG" "3proxy HTTP Proxy"
    ok "Service registered"

    # ── Firewall ──────────────────────────────────────────────────────────────
    _open_port "$HTTP_PORT" "tcp" "HTTP proxy"

    # ── Start ─────────────────────────────────────────────────────────────────
    step "Start ${HTTP_SVC}"
    systemctl enable "$HTTP_SVC" &>/dev/null || true
    systemctl restart "$HTTP_SVC"
    sleep 1
    if http_running; then
        ok "HTTP proxy running on port ${HTTP_PORT}"
    else
        warn "Service may not have started — check: journalctl -u ${HTTP_SVC} -n 30"
    fi

    HTTP_INSTALLED=1
    save_state

    echo ""
    divider
    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ "$HTTP_AUTH" == "1" ]]; then
        svc_line "HTTP proxy ready:  http://${HTTP_USER}:****@${ip}:${HTTP_PORT}"
        auth_line "User: ${HTTP_USER}   Pass: ${HTTP_PASS}"
    else
        svc_line "HTTP proxy ready:  http://${ip}:${HTTP_PORT}"
    fi
    echo ""
}

# ─── Install SOCKS5 Proxy ─────────────────────────────────────────────────────
install_socks() {
    step "Install SOCKS5 Proxy  (3proxy — compiled from source)"
    divider

    if socks_installed; then
        warn "SOCKS5 proxy already configured on port ${SOCKS_PORT}."
        prompt "Reinstall / reconfigure? [y/N]: "; read -r _r
        [[ "${_r,,}" != "y" ]] && { info "Skipped."; return; }
        systemctl stop "$SOCKS_SVC" &>/dev/null || true
    fi

    # ── Port ──────────────────────────────────────────────────────────────────
    echo ""
    ask_port SOCKS_PORT 1080 || return

    # ── Auth ──────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${PUR}${BOLD}  🔑 Authentication${R}"
    prompt "Require username and password? [y/N]: "; read -r _auth
    SOCKS_AUTH=0; SOCKS_USER=""; SOCKS_PASS=""
    if [[ "${_auth,,}" == "y" ]]; then
        ask_credentials SOCKS_USER SOCKS_PASS
        SOCKS_AUTH=1
        ok "Credentials set"
    else
        info "No authentication — proxy open to all"
    fi

    # ── Build 3proxy (only if not already built) ───────────────────────────────
    divider
    build_3proxy

    # ── Config ────────────────────────────────────────────────────────────────
    step "Write SOCKS5 proxy config"
    _write_socks_cfg

    # ── Systemd service ───────────────────────────────────────────────────────
    step "Register systemd service  (${SOCKS_SVC})"
    _write_service "$SOCKS_SVC" "$SOCKS_CFG" "3proxy SOCKS5 Proxy"
    ok "Service registered"

    # ── Firewall ──────────────────────────────────────────────────────────────
    _open_port "$SOCKS_PORT" "tcp" "SOCKS5 proxy"

    # ── Start ─────────────────────────────────────────────────────────────────
    step "Start ${SOCKS_SVC}"
    systemctl enable "$SOCKS_SVC" &>/dev/null || true
    systemctl restart "$SOCKS_SVC"
    sleep 1
    if socks_running; then
        ok "SOCKS5 proxy running on port ${SOCKS_PORT}"
    else
        warn "Service may not have started — check: journalctl -u ${SOCKS_SVC} -n 30"
    fi

    SOCKS_INSTALLED=1
    save_state

    echo ""
    divider
    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ "$SOCKS_AUTH" == "1" ]]; then
        svc_line "SOCKS5 proxy ready:  socks5://${SOCKS_USER}:****@${ip}:${SOCKS_PORT}"
        auth_line "User: ${SOCKS_USER}   Pass: ${SOCKS_PASS}"
    else
        svc_line "SOCKS5 proxy ready:  socks5://${ip}:${SOCKS_PORT}"
    fi
    echo ""
}

# ─── Service control ──────────────────────────────────────────────────────────
start_http() {
    step "Start HTTP Proxy"
    if ! http_installed; then warn "HTTP proxy not installed — choose option 1 first."; return; fi
    systemctl start "$HTTP_SVC" && ok "HTTP proxy started" || warn "Failed to start HTTP proxy"
}
stop_http() {
    step "Stop HTTP Proxy"
    if ! http_installed; then warn "HTTP proxy not installed."; return; fi
    systemctl stop "$HTTP_SVC" && ok "HTTP proxy stopped" || warn "Failed to stop HTTP proxy"
}
restart_http() {
    step "Restart HTTP Proxy"
    if ! http_installed; then warn "HTTP proxy not installed — choose option 1 first."; return; fi
    systemctl restart "$HTTP_SVC" && ok "HTTP proxy restarted" || warn "Failed to restart HTTP proxy"
}

start_socks() {
    step "Start SOCKS5 Proxy"
    if ! socks_installed; then warn "SOCKS5 proxy not installed — choose option 5 first."; return; fi
    systemctl start "$SOCKS_SVC" && ok "SOCKS5 proxy started" || warn "Failed to start SOCKS5 proxy"
}
stop_socks() {
    step "Stop SOCKS5 Proxy"
    if ! socks_installed; then warn "SOCKS5 proxy not installed."; return; fi
    systemctl stop "$SOCKS_SVC" && ok "SOCKS5 proxy stopped" || warn "Failed to stop SOCKS5 proxy"
}
restart_socks() {
    step "Restart SOCKS5 Proxy"
    if ! socks_installed; then warn "SOCKS5 proxy not installed — choose option 5 first."; return; fi
    systemctl restart "$SOCKS_SVC" && ok "SOCKS5 proxy restarted" || warn "Failed to restart SOCKS5 proxy"
}

# ─── Status ───────────────────────────────────────────────────────────────────
show_status() {
    load_state
    step "Proxy Status"
    divider
    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo -e "${CYN}${BOLD}  🌐 HTTP Proxy${R}"
    if http_installed; then
        echo -e "  ${DIM}Engine : ${WHT}3proxy (built from source)${R}"
        echo -e "  ${DIM}Binary : ${WHT}${PROXY_BIN}${R}"
        echo -e "  ${DIM}Config : ${WHT}${HTTP_CFG}${R}"
        echo -e "  ${DIM}Port   : ${WHT}${HTTP_PORT}${R}"
        if [[ "$HTTP_AUTH" == "1" ]]; then
            echo -e "  ${DIM}Auth   : ${PUR}${BOLD}enabled${R}  — user: ${WHT}${HTTP_USER}${R}"
        else
            echo -e "  ${DIM}Auth   : ${DIM}open (no credentials)${R}"
        fi
        if http_running; then
            echo -e "  ${DIM}Status : ${GRN}${BOLD}● running${R}"
            systemctl status "$HTTP_SVC" --no-pager -l 2>/dev/null | tail -4 || true
        else
            echo -e "  ${DIM}Status : ${YLW}● stopped${R}"
        fi
        echo ""
        if [[ "$HTTP_AUTH" == "1" ]]; then
            svc_line "http://${HTTP_USER}:****@${ip}:${HTTP_PORT}"
            echo -e "  ${DIM}(credentials stored in ${HTTP_CFG})${R}"
        else
            svc_line "http://${ip}:${HTTP_PORT}"
        fi
    else
        echo -e "  ${DIM}Status : not installed${R}"
    fi

    echo ""
    echo -e "${CYN}${BOLD}  🧦 SOCKS5 Proxy${R}"
    if socks_installed; then
        echo -e "  ${DIM}Engine : ${WHT}3proxy (built from source)${R}"
        echo -e "  ${DIM}Binary : ${WHT}${PROXY_BIN}${R}"
        echo -e "  ${DIM}Config : ${WHT}${SOCKS_CFG}${R}"
        echo -e "  ${DIM}Port   : ${WHT}${SOCKS_PORT}${R}"
        if [[ "$SOCKS_AUTH" == "1" ]]; then
            echo -e "  ${DIM}Auth   : ${PUR}${BOLD}enabled${R}  — user: ${WHT}${SOCKS_USER}${R}"
        else
            echo -e "  ${DIM}Auth   : ${DIM}open (no credentials)${R}"
        fi
        if socks_running; then
            echo -e "  ${DIM}Status : ${GRN}${BOLD}● running${R}"
            systemctl status "$SOCKS_SVC" --no-pager -l 2>/dev/null | tail -4 || true
        else
            echo -e "  ${DIM}Status : ${YLW}● stopped${R}"
        fi
        echo ""
        if [[ "$SOCKS_AUTH" == "1" ]]; then
            svc_line "socks5://${SOCKS_USER}:****@${ip}:${SOCKS_PORT}"
            echo -e "  ${DIM}(credentials stored in ${SOCKS_CFG})${R}"
        else
            svc_line "socks5://${ip}:${SOCKS_PORT}"
        fi
    else
        echo -e "  ${DIM}Status : not installed${R}"
    fi
}

# ─── Uninstall HTTP ───────────────────────────────────────────────────────────
uninstall_http() {
    step "Uninstall HTTP Proxy"
    echo -e "${RED}${BOLD}  Removes the HTTP proxy config and service. The 3proxy binary stays.${R}"
    echo -en "${YLW}  Type YES to confirm: ${R}"; read -r _c
    [[ "$_c" != "YES" ]] && { info "Cancelled."; return; }
    systemctl stop    "$HTTP_SVC" &>/dev/null || true
    systemctl disable "$HTTP_SVC" &>/dev/null || true
    rm -f "$HTTP_CFG" "/etc/systemd/system/${HTTP_SVC}.service"
    systemctl daemon-reload
    HTTP_INSTALLED=0; HTTP_AUTH=0; HTTP_USER=""; HTTP_PASS=""
    save_state
    ok "HTTP proxy removed"
}

# ─── Uninstall SOCKS5 ─────────────────────────────────────────────────────────
uninstall_socks() {
    step "Uninstall SOCKS5 Proxy"
    echo -e "${RED}${BOLD}  Removes the SOCKS5 proxy config and service. The 3proxy binary stays.${R}"
    echo -en "${YLW}  Type YES to confirm: ${R}"; read -r _c
    [[ "$_c" != "YES" ]] && { info "Cancelled."; return; }
    systemctl stop    "$SOCKS_SVC" &>/dev/null || true
    systemctl disable "$SOCKS_SVC" &>/dev/null || true
    rm -f "$SOCKS_CFG" "/etc/systemd/system/${SOCKS_SVC}.service"
    systemctl daemon-reload
    SOCKS_INSTALLED=0; SOCKS_AUTH=0; SOCKS_USER=""; SOCKS_PASS=""
    save_state
    ok "SOCKS5 proxy removed"
}

# ─── Menu ─────────────────────────────────────────────────────────────────────
print_menu() {
    load_state
    local htag="" stag=""
    if http_installed;  then http_running  && htag="${GRN} ● running${R}" || htag="${YLW} ● stopped${R}"; [[ "$HTTP_AUTH"  == "1" ]] && htag+="${PUR} 🔑${R}"; fi
    if socks_installed; then socks_running && stag="${GRN} ● running${R}" || stag="${YLW} ● stopped${R}"; [[ "$SOCKS_AUTH" == "1" ]] && stag+="${PUR} 🔑${R}"; fi

    echo -e "${CYN}${BOLD}  ┌─ 🌐 HTTP Proxy ─────────────────────────────────────────┐${R}"
    echo -e "  ${WHT}  1${R}  🌐  Install HTTP Proxy${htag}"
    echo -e "  ${WHT}  2${R}  ▶   Start HTTP Proxy"
    echo -e "  ${WHT}  3${R}  ■   Stop HTTP Proxy"
    echo -e "  ${WHT}  4${R}  🔄  Restart HTTP Proxy"
    echo -e "${CYN}${BOLD}  ├─ 🧦 SOCKS5 Proxy ───────────────────────────────────────┤${R}"
    echo -e "  ${WHT}  5${R}  🧦  Install SOCKS5 Proxy${stag}"
    echo -e "  ${WHT}  6${R}  ▶   Start SOCKS5 Proxy"
    echo -e "  ${WHT}  7${R}  ■   Stop SOCKS5 Proxy"
    echo -e "  ${WHT}  8${R}  🔄  Restart SOCKS5 Proxy"
    echo -e "${CYN}${BOLD}  ├─ General ───────────────────────────────────────────────┤${R}"
    echo -e "  ${WHT}  9${R}  📊  Status"
    echo -e "  ${WHT} 10${R}  🗑   Uninstall HTTP Proxy"
    echo -e "  ${WHT} 11${R}  🗑   Uninstall SOCKS5 Proxy"
    echo -e "${CYN}${BOLD}  └─────────────────────────────────────────────────────────┘${R}"
    echo -e "  ${WHT}  0${R}  ❌  Exit"
    echo ""
    echo -en "${CYN}${BOLD}  Choice: ${R}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    while true; do
        banner
        print_menu
        read -r choice
        echo ""
        case "$choice" in
            1)  install_http  ;;
            2)  start_http    ;;
            3)  stop_http     ;;
            4)  restart_http  ;;
            5)  install_socks ;;
            6)  start_socks   ;;
            7)  stop_socks    ;;
            8)  restart_socks ;;
            9)  show_status   ;;
            10) uninstall_http  ;;
            11) uninstall_socks ;;
            0|q|Q) echo -e "  ${DIM}Goodbye.${R}"; exit 0 ;;
            *) warn "Invalid choice — enter a number from 0 to 11." ;;
        esac
        echo ""
        echo -en "${DIM}  Press Enter to continue...${R}"; read -r
    done
}

main "$@"
