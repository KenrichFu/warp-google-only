#!/bin/bash
set -e

echo "✅ 检测系统版本..."

. /etc/os-release
if [[ "$ID" == "ubuntu" ]]; then
  if [[ "$VERSION_ID" == "24.04" ]]; then
    UBUNTU_CODENAME="jammy"
    echo "检测到 Ubuntu 24.04，使用 jammy (22.04) 软件源"
  else
    UBUNTU_CODENAME=$(lsb_release -cs)
    echo "检测到 Ubuntu $VERSION_ID，使用官方软件源代号：$UBUNTU_CODENAME"
  fi
else
  echo "非Ubuntu系统，脚本仅支持Ubuntu"
  exit 1
fi

echo "✅ 安装依赖..."
sudo apt update
sudo apt install -y apt-transport-https gnupg curl dnsmasq lsb-release iptables dnsutils

echo "✅ 添加 Cloudflare WARP 官方源..."
curl https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

echo "✅ 更新包列表并安装 warp-cli..."
sudo apt update
sudo apt install -y cloudflare-warp

echo "✅ 注册并启动 warp..."
if ! warp-cli registration status | grep -q "Registered"; then
  sudo warp-cli registration create
fi
sudo warp-cli proxy set-mode warp
sudo warp-cli connect

sleep 5

echo "✅ 配置策略路由..."
if ! grep -q "200 warp" /etc/iproute2/rt_tables; then
  echo "200 warp" | sudo tee -a /etc/iproute2/rt_tables
fi
sudo ip route add default dev wgcf table warp || true
sudo ip rule add fwmark 1 table warp || true

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

echo "✅ 创建自动标记脚本..."
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

echo "✅ 创建 systemd 服务..."
sudo tee /etc/systemd/system/warp-google-only.service > /dev/null << EOF
[Unit]
Description=Warp Google Only Split Routing
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

echo "✅ warp-google-only 安装完成！"
