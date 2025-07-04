#!/bin/bash
set -e

# 安装必要工具
echo "✅ 安装必要工具..."
sudo apt update
sudo apt install -y curl wget iptables iproute2 resolvconf dnsmasq

# 下载并安装 cloudflared
echo "✅ 下载并安装 cloudflared..."
wget https://github.com/cloudflare/cloudflared/releases/download/2025.6.0/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared

# 登录并启用 WARP（使用 Cloudflare Tunnel）
echo "✅ 登录并启用 Cloudflare Tunnel..."
sudo cloudflared login

# 配置并启动 Cloudflare Tunnel（即 WARP 服务）
echo "✅ 启动 Cloudflare Tunnel 以实现 WARP..."
sudo cloudflared tunnel --url localhost:5053

# 配置 Google 系列网站流量走 WARP
echo "✅ 配置 Google 流量走 WARP..."
for domain in google.com googleapis.com gstatic.com youtube.com; do
    for ip in $(dig +short $domain); do
        sudo iptables -t mangle -A OUTPUT -d $ip -j MARK --set-mark 1
    done
done

# 配置路由规则：Google 流量走 WARP
echo "✅ 配置路由规则..."
sudo ip rule add fwmark 1 table 200
sudo ip route add default dev cloudflared table 200

# 配置其他流量走原生 IP
echo "✅ 配置其他流量走原生 IP..."
sudo ip rule add from all lookup main

# 自动化脚本：每5分钟执行一次
echo "✅ 创建自动化脚本..."
sudo tee /usr/local/bin/warp-google-only.sh > /dev/null << 'EOL'
#!/bin/bash
while true; do
  # 清除原有的标记规则
  sudo iptables -t mangle -F
  
  # 配置 Google 流量走 WARP
  for domain in google.com googleapis.com gstatic.com youtube.com; do
      for ip in $(dig +short $domain); do
          sudo iptables -t mangle -A OUTPUT -d $ip -
