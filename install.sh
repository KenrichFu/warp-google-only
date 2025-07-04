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
sudo apt install -y curl wget lsb-release gnupg iptables dnsmasq wireguard wireguard-tools resolvconf

# 获取最新的 wgcf 版本下载链接
LATEST_WGCF_URL="https://github.com/ViRb3/wgcf/releases/download/v1.0.4/wgcf_1.0.4_linux_amd64.tar.gz"

# 下载 wgcf 并解压
echo "✅ 下载并安装 wgcf..."
wget -O wgcf.tar.gz "$LATEST_WGCF_URL"

# 检查下载文件是否成功
if ! file wgcf.tar.gz | grep -q "gzip compressed data"; then
    echo "下载的文件不是正确的 .tar.gz 格式，请检查下载链接是否正确"
    exit 1
fi

# 解压下载的 tar.gz 文件
tar zxvf wgcf.tar.gz

# 赋予执行权限并移动到可执行路径
chmod +x wgcf
sudo mv wgcf /usr/local/bin/

# 注册 wgcf（如果没有注册）
echo "✅ 注册 Cloudflare WARP 账户..."
if [ ! -f wgcf-account.toml ]; then
  wgcf register --accept-tos
fi

# 生成 WireGuard 配置文件
echo "✅ 生成 WireGuard 配置..."
wgcf generate

# 备份并修改配置文件的 Endpoint
cp wgcf-profile.conf wgcf-profile.conf.bak
sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf

# 配置 WireGuard
echo "✅ 配置 WireGuard..."
sudo mv wgcf-profile.conf /etc/wireguard/wgcf.conf
sudo systemctl enable wg-quick@wgcf
sudo systemctl start wg-quick@wgcf

sleep 3

# 配置路由
echo "✅ 配置策略路由..."
if ! grep -q "200 warp" /etc/iproute2/rt_tables; then
  echo "200 warp" | sudo tee -a /etc/iproute2/rt_tables
fi
sudo ip route add default dev wgcf table warp || true
sudo ip rule add fwmark 1 table warp || true

# 配置 dnsmasq 分流
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

# 创建标记脚本
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

echo "✅ warp-google-only 安装完成！"
