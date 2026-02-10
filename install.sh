#!/bin/bash

REPO="CN-Root/VPSShua"
INSTALL_DIR="/etc/VPSShua"
BIN_PATH="/usr/local/bin/vpsshua"
TARGET_SCRIPT="$INSTALL_DIR/vpsshua.sh"

is_valid_script() {
    local file="$1"
    [ -s "$file" ] || return 1
    head -n 1 "$file" | grep -q '^#!/bin/bash' || return 1
    grep -q 'VPSShua' "$file" || return 1
    grep -q '配置每日定时任务' "$file" || return 1
    grep -q '^404: Not Found$' "$file" && return 1
    return 0
}

fetch_script() {
    local tmp_file="$1"
    shift
    local url

    for url in "$@"; do
        echo "🔎 尝试下载: $url"
        if curl -fsSL "$url" -o "$tmp_file" && is_valid_script "$tmp_file"; then
            echo "✅ 下载成功: $url"
            return 0
        fi
    done

    return 1
}

# 默认优先 main 分支，同时兼容大小写文件名
CANDIDATE_URLS=(
    "https://raw.githubusercontent.com/$REPO/main/vpsshua.sh"
    "https://raw.githubusercontent.com/$REPO/main/VPSShua.sh"
)

echo "🔍 获取 latest release 信息（用于兜底）..."
API_RESPONSE=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || true)
LATEST_TAG=$(echo "$API_RESPONSE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
if [ -n "$LATEST_TAG" ]; then
    CANDIDATE_URLS+=(
        "https://raw.githubusercontent.com/$REPO/$LATEST_TAG/vpsshua.sh"
        "https://raw.githubusercontent.com/$REPO/$LATEST_TAG/VPSShua.sh"
        "https://github.com/$REPO/releases/download/$LATEST_TAG/vpsshua.sh"
        "https://github.com/$REPO/releases/download/$LATEST_TAG/VPSShua.sh"
    )
fi

tmp_file=$(mktemp)
if ! fetch_script "$tmp_file" "${CANDIDATE_URLS[@]}"; then
    rm -f "$tmp_file"
    echo "❌ 下载失败：未获取到包含定时菜单的有效脚本文件，已避免安装旧版/404内容。"
    exit 1
fi

echo "📁 创建安装目录: $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"

sudo mv "$tmp_file" "$TARGET_SCRIPT"
sudo chmod +x "$TARGET_SCRIPT"

echo "🔗 添加软链接到 $BIN_PATH"
sudo ln -sf "$TARGET_SCRIPT" "$BIN_PATH"

if command -v vpsshua >/dev/null 2>&1; then
    echo -e "
✅ 安装成功！你现在可以输入以下命令启动脚本：
"
    echo "  vpsshua"
    echo -e "
📂 安装路径：${INSTALL_DIR}"
else
    echo "⚠️ 安装完成，但未检测到 vpsshua 命令，请检查软链接或重新安装"
fi
