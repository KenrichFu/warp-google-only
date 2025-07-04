#!/bin/bash
set -e

echo "✅ 正在安装 warp-cli ..."
sudo apt update
sudo apt install -y cloudflare-warp dnsmasq

echo "✅ 注册 warp 并连接 ..."
sudo warp-cli register || true
sudo warp-cli set-mode warp
sudo warp-cli connect

sleep 5

echo "✅ 配置策略路由 ..."
echo "200 warp" | sudo tee -a /etc/iproute2/rt_tables
sudo ip route add default dev wgcf table warp
sudo ip rule add fwmark 1 table warp

echo "✅ 配置 dnsmasq ..."
echo "server=/google.com/1.1.1.1
server=/googleapis.com/1.1.1.1
server=/gstatic.com/1.1.1.1
server=/youtube.com/1.1.1.1
server=8.8.8.8" | sudo tee /etc/dnsmasq.d/google-only.conf

sudo systemctl restart dnsmasq
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

echo "✅ 创建自动标记脚本 ..."
echo '#!/bin/bash
while true; do
    iptables -t mangle -F
    for domain in google.com googleapis.com gstatic.com youtube.com; do
        for ip in $(dig +short $domain); do
            iptables -t mangle -A OUTPUT -d $ip -j MARK --set-mark 1
        done
    done
    sleep 300
done' | sudo tee /usr/local/bin/warp-google-only.sh
sudo chmod +x /usr/local/bin/warp-google-only.sh

echo "✅ 创建 systemd 服务 ..."
echo '[Unit]
Description=Warp Google Only Split Routing
After=network.target

[Service]
ExecStart=/usr/local/bin/warp-google-only.sh
Restart=always

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/warp-google-only.service

sudo systemctl daemon-reload
sudo systemctl enable warp-google-only
sudo systemctl start warp-google-only

echo "✅ warp-google-only 安装并已运行完毕！"
