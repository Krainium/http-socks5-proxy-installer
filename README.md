# 🌐🧦 http-socks5-proxy-installer

http-socks5-proxy-installer turns any Ubuntu, Debian, or RHEL-family VPS into a proxy server. It compiles **3proxy** from source — no distro packages required. Both an HTTP proxy and a SOCKS5 proxy run from the same binary, each with its own config, its own systemd service, its own port, and its own optional username and password protection. You can run both at the same time or just one.

```bash
git clone https://github.com/Krainium/http-socks5-proxy-installer
cd http-socks5-proxy-installer
sudo bash proxy-setup.sh
```

---

## 🎯 What it sets up

**🌐 HTTP Proxy** — powered by [3proxy](https://github.com/3proxy/3proxy). Handles HTTP and HTTP CONNECT tunnelling. Optional username and password protection so only authorised clients can connect.

**🧦 SOCKS5 Proxy** — also powered by 3proxy, running as a completely separate service on its own port. Full SOCKS5 with optional authentication. No system users are created — credentials live entirely in the config file.

The script installs the build tools (`gcc`, `make`, `git`), clones the 3proxy source, compiles it once, then reuses that single binary for both services.

---

## ⚙️ Setup

Run the script as root. The interactive menu appears. No prior configuration is needed.

---

### 🌐 Install HTTP Proxy — option 1

**Step 1 — Port**
Press Enter to use the default `8080` or type any port between 1 and 65535.

**Step 2 — Authentication**
```
Require username and password? [y/N]:
```
Press `N` to leave the proxy open to all connections.
Press `y` to protect it with credentials. The script then asks:
```
Username:
Password:
Confirm  :
```
Usernames may only contain letters, numbers, `_` and `-`. The password field hides what you type. Passwords must not contain `:` or spaces (a 3proxy config format requirement). You confirm the password once to prevent typos.

When setup finishes the script prints the proxy address:
```
🔗  http://alice:****@203.0.113.1:8080
🔑  User: alice   Pass: yourpassword
```

---

### 🧦 Install SOCKS5 Proxy — option 5

**Step 1 — Port**
Press Enter for the default `1080` or type your own. The script will not let you pick the same port as the HTTP proxy.

**Step 2 — Authentication**
Same prompt as HTTP. Press `N` for an open proxy or `y` to set credentials. Credentials are stored in `/etc/3proxy/socks5.cfg` (mode 600, root-only). No system user is created.

When setup finishes:
```
🔗  socks5://bob:****@203.0.113.1:1080
🔑  User: bob   Pass: yourpassword
```

You can run both proxies on the same server at the same time. They use different ports and independent systemd services.

---

## 📋 Menu reference

```
  ─ 🌐 HTTP Proxy ──────────────────────────────────────────
  1  🌐  Install HTTP Proxy         (port + optional auth)
  2  ▶   Start HTTP Proxy
  3  ■   Stop HTTP Proxy
  4  🔄  Restart HTTP Proxy

  ─ 🧦 SOCKS5 Proxy ────────────────────────────────────────
  5  🧦  Install SOCKS5 Proxy       (port + optional auth)
  6  ▶   Start SOCKS5 Proxy
  7  ■   Stop SOCKS5 Proxy
  8  🔄  Restart SOCKS5 Proxy

  ─ General ────────────────────────────────────────────────
  9  📊  Status                     (port · auth · connection string)
 10  🗑   Uninstall HTTP Proxy
 11  🗑   Uninstall SOCKS5 Proxy
  0  ❌  Exit
```

The banner at the top of the menu shows live status for each proxy. A `🔑` tag appears next to any proxy that has authentication enabled.

---

## 🔌 Connecting to the proxy

**Browser (HTTP proxy)**
Go to your browser's network or proxy settings. Set proxy type to HTTP, enter your server IP, enter the port. If you set credentials, the browser will prompt for them on first connection.

**Browser (SOCKS5)**
Same place in settings. Set type to SOCKS5 instead of HTTP.

**curl**
```bash
# HTTP proxy — no auth
curl -x http://SERVER_IP:8080 https://ifconfig.me

# HTTP proxy — with auth
curl -x http://alice:password@SERVER_IP:8080 https://ifconfig.me

# SOCKS5 — no auth
curl --socks5-hostname SERVER_IP:1080 https://ifconfig.me

# SOCKS5 — with auth
curl --socks5-hostname bob:password@SERVER_IP:1080 https://ifconfig.me
```

**SSH through SOCKS5**
```bash
# No auth
ssh -o ProxyCommand="nc -X 5 -x SERVER_IP:1080 %h %p" user@destination

# With auth
ssh -o ProxyCommand="ncat --proxy-type socks5 --proxy SERVER_IP:1080 --proxy-auth bob:password %h %p" user@destination
```

**System-wide on Linux**
```bash
# HTTP proxy
export http_proxy="http://SERVER_IP:8080"
export https_proxy="http://SERVER_IP:8080"

# SOCKS5
export ALL_PROXY="socks5://SERVER_IP:1080"
```

---

## 📁 Where things live

| Path | What is it |
|------|------------|
| `/usr/local/bin/3proxy` | 3proxy binary (compiled from source) |
| `/etc/3proxy/http.cfg` | HTTP proxy config (mode 600) |
| `/etc/3proxy/socks5.cfg` | SOCKS5 proxy config (mode 600) |
| `/var/log/3proxy/http.log` | HTTP proxy log (daily rotation) |
| `/var/log/3proxy/socks5.log` | SOCKS5 proxy log (daily rotation) |
| `/etc/proxy-setup/state.conf` | Saved port and auth settings (mode 600) |

Systemd services: `3proxy-http` and `3proxy-socks5`.

---

## 📄 Config file format

The script generates minimal 3proxy configs. Here is what an authenticated HTTP proxy config looks like:

```
nscache 65536
log /var/log/3proxy/http.log D
flush
auth strong
users alice:CL:password
allow alice
maxconn 100
proxy -p8080 -i0.0.0.0
```

And an open (no-auth) SOCKS5 config:

```
log /var/log/3proxy/socks5.log D
flush
auth none
allow *
maxconn 100
socks -p1080 -i0.0.0.0
```

`CL:` means cleartext password stored in the config file. The file is readable by root only (mode 600).

---

## 🔒 Authentication details

Both proxies use 3proxy's built-in config-file authentication. When you enable auth, the script writes a `users username:CL:password` line and sets `auth strong`. No system users are created. When you uninstall a proxy its config is deleted and the credentials go with it.

The status screen always shows `****` in place of the password. To read the actual credentials after install:

```bash
grep users /etc/3proxy/http.cfg
grep users /etc/3proxy/socks5.cfg
```

---

## 🌐 Compatible apps

| App | HTTP | SOCKS5 | HTTP Auth | SOCKS5 Auth |
|-----|------|--------|-----------|-------------|
| Chrome / Firefox | ✔ | ✔ | ✔ | ✔ |
| curl / wget | ✔ | ✔ | ✔ | ✔ |
| SSH (ProxyCommand) | — | ✔ | — | ✔ |
| Telegram | ✔ | ✔ | ✔ | ✔ |
| Android (system proxy) | ✔ | ✔ | ✔ | ✔ |
| iOS (system proxy) | ✔ | — | ✔ | — |
| Torrent clients | — | ✔ | — | ✔ |
| Python requests | ✔ | ✔ | ✔ | ✔ |

---

## 🛠 Troubleshooting

**Build fails during install**
The script needs `git`, `gcc`, and `make`. It installs them automatically, but if the package manager itself fails:
```bash
# Debian / Ubuntu
apt-get install -y gcc make git

# RHEL / CentOS / Fedora
yum install -y gcc make git
```
Then re-run the script and reinstall.

**Service starts then immediately stops**
Check the journal for the exact error:
```bash
journalctl -u 3proxy-http -n 30
journalctl -u 3proxy-socks5 -n 30
```
If you see `Unknown command` in the output, an old config from a previous version of this script may be present. Fix it by removing the unknown directive and restarting:
```bash
sed -i '/^nofork/d' /etc/3proxy/http.cfg /etc/3proxy/socks5.cfg
systemctl restart 3proxy-http
systemctl restart 3proxy-socks5
```
Or reinstall cleanly using options `10` → `1` and `11` → `5`.

**Proxy installs but connection is refused**
The firewall port may not be open. Check and open it manually if needed:
```bash
ufw status
iptables -L INPUT -n | grep <port>
ufw allow 8080/tcp
ufw allow 1080/tcp
```

**Auth fails — 407 from HTTP proxy or rejected after SOCKS5 handshake**
Read the config to confirm the credentials match what you entered:
```bash
grep users /etc/3proxy/http.cfg
grep users /etc/3proxy/socks5.cfg
```
If they are wrong or missing, reinstall with option `10` or `11` then `1` or `5`.

**Want to change the port or toggle auth after install**
Use option `10` or `11` to uninstall, then reinstall with option `1` or `5` and choose the new settings.
