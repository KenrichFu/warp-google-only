# 🌐 gemini-curl-ipv4

🚀 让 `curl` 在访问 `gemini.google.com` 时 **只走 IPv4**，  
避免因为 VPS 的 IPv6 被 Google 屏蔽、地区绕路、速度慢的问题。

---

## ✨ 功能特点

✅ 只针对 `gemini.google.com` 自动检测最新 IPv4  
✅ 使用 `--resolve` 强制 IPv4，不污染 `/etc/hosts`  
✅ 自动配置 `curl` 别名，其他网站依然照常走 IPv4/IPv6  
✅ 永久生效（重启后也有效）

---

## ⚡ 一键安装

只需在你的服务器（如 Oracle Cloud）SSH 执行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/KenrichFu/gemini-curl-ipv4/main/install.sh | bash
