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

# 登录并启用 WARP
echo "✅ 登录并启用 WARP..."
sudo cloudflared warp --accept-tos login

# 启动 WARP
echo "✅ 启动 cloudflared WARP..."
sudo cloudflared warp --accept-tos --proxy-dns --proxy-dns-port 5053

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
          sudo iptables -t mangle -A OUTPUT -d $ip -j MARK --set-mark 1
      done
  done

  # 配置路由规则：Google 流量走 WARP
  sudo ip rule add fwmark 1 table 200
  sudo ip route add default dev cloudflared table 200

  # 配置其他流量走原生 IP
  sudo ip rule add from all lookup main

  # 每5分钟执行一次
  sleep 300
done
EOL

# 赋予脚本执行权限
sudo chmod +x /usr/local/bin/warp-google-only.sh

# 创建 systemd 服务管理脚本
echo "✅ 创建 systemd 服务..."
sudo tee /etc/systemd/system/warp-google-only.service > /dev/null << EOF
[Unit]
Description=Google Traffic via WARP (Cloudflare)
After=network.target

[Service]
ExecStart=/usr/local/bin/warp-google-only.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启动并使服务在系统启动时自动运行
sudo systemctl daemon-reload
sudo systemctl enable warp-google-only
sudo systemctl start warp-google-only

echo "✅ WARP 安装和配置完成！"
echo "🎉 Google 流量已配置走 WARP，其他流量保持原生 IP。"
