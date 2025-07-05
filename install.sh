#!/bin/bash

set -e

echo -e "\033[34m🚀 开始安装 gemini curl 自动 IPv4...\033[0m"

sudo tee /usr/local/bin/curl-gemini >/dev/null <<'EOF'
#!/bin/bash
if [[ "$@" == *"gemini.google.com"* ]]; then
    IP=$(dig +short gemini.google.com A | head -n1)
    if [[ -z "$IP" ]]; then
        echo -e "\033[31m[✗] 无法解析 gemini.google.com 的 IPv4，使用默认。\033[0m"
        /usr/bin/curl "$@"
    else
        echo -e "\033[32m[✓] 检测到 gemini.google.com 当前 IPv4: $IP，使用 --resolve。\033[0m"
        /usr/bin/curl --resolve gemini.google.com:443:$IP "$@"
    fi
else
    /usr/bin/curl "$@"
fi
EOF

sudo chmod +x /usr/local/bin/curl-gemini

if ! grep -q "alias curl=" ~/.bashrc; then
    echo "alias curl='/usr/local/bin/curl-gemini'" >> ~/.bashrc
    echo -e "\033[32m[✓] 已在 ~/.bashrc 中设置 curl 别名。\033[0m"
fi

if [ -f ~/.zshrc ]; then
    if ! grep -q "alias curl=" ~/.zshrc; then
        echo "alias curl='/usr/local/bin/curl-gemini'" >> ~/.zshrc
        echo -e "\033[32m[✓] 已在 ~/.zshrc 中设置 curl 别名。\033[0m"
    fi
fi

echo -e "\033[36m🎉 安装完成，请重新登录 SSH 或执行 'source ~/.bashrc' 生效。\033[0m"
