#!/bin/bash
set -e

echo "✅ 安装依赖..."
sudo apt update
sudo apt install -y curl wget lsb-release gnupg iptables dnsmasq wireguard wireguard-tools resolvconf

# 安装 wgcf
echo "✅ 安装 wgcf..."
LATEST_WGCF=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4)
wget -O wgcf.tar.gz "$LATEST_WGCF"
tar zxvf wgcf.tar.gz
chmod +x wgcf
sudo mv wgcf /usr/local/bin/

# 注册 wgcf
echo "✅ 注册 Cloudflare WARP 账户..."
if [ ! -f wgcf-account.toml ]; then
  wgcf register --accept-tos
fi

# 生成配置
echo "✅ 生成 WireGuard 配置..."
wgcf generate

# 备份并替换 Endpoint
cp wgcf-profile.conf wgcf-profile.conf.bak
sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf

# 启动 wg-quick
echo "✅ 配置 WireGuard..."
sudo mv wgcf-profile.conf /etc/wireguard/wgcf.conf
sudo systemctl enable wg-quick@wgcf
sudo systemctl start wg-quick@wgcf

sleep 3

# 设置路由表
echo "✅ 配置策略路由..."
if ! grep -q "200 warp" /etc/iproute2/rt_tables; then
  echo "200 warp" | sudo tee -a /etc/iproute2/rt_tables
fi
sudo ip rule add fwmark 1 table warp || true
sudo ip route add default dev wgcf table warp || true

# 配置 dnsmasq
echo "✅ 配置 dnsmasq 分流..."
sudo tee /etc/dnsmasq.d/google-only.conf > /dev/null << EOF
server=/google.com/1.1.1.1
server=/googleapis.com/1.1.1.1
server=/gstatic.com/1.1.1.1
server=/youtube.com/1.1.1.1
server=8.8.8.8
EOF

sudo systemctl restart dnsmasq
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

# 自动标记 Google 流量
echo "✅ 创建标记脚本..."
sudo tee /usr/local/bin/warp-google-only.sh > /dev/null << 'EOL'
#!/bin/bash
while true; do
  iptables -t mangle -F
  for domain in google.com googleapis.com gstatic.com youtube.com; do
    for ip in $(dig +short $domain); do
      iptables -t mangle -A OUTPUT -d $ip -j MARK --set-mark 1
    done
  done
  sleep 300
done
EOL
sudo chmod +x /usr/local/bin/warp-google-only.sh

# 创建 systemd 服务
echo "✅ 创建 systemd 服务..."
sudo tee /etc/systemd/system/warp-google-only.service > /dev/null << EOF
[Unit]
Description=Warp Google Only Split Routing (WireGuard)
After=network.target

[Service]
ExecStart=/usr/local/bin/warp-google-only.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable warp-google-only
sudo systemctl start warp-google-only

echo "✅ 安装完成！WARP 分流生效"
