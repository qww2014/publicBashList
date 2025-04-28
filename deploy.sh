#!/bin/bash

# =============================
 # @Author: Lao Qiao
 # @Date: 2025-04-26 15:29:53
 # @LastEditTime: 2025-04-26 16:42:06
 # @LastEditors: Lao Qiao
 # @FilePath: deploy.sh
 # 我秃了，但我更强了~
# =============================

SCRIPT_FILE="./lazy-maintenance-multi.sh"
SERVER_LIST="./servers.txt"

# ===============================
# SSH密钥配置区
# ===============================

# 设置SSH私钥路径，默认是 ~/.ssh/sshkey
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/sshkey}"

# 检查密钥文件是否存在
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "❌ 错误：找不到SSH密钥文件: $SSH_KEY_PATH"
  exit 1
fi

# 确保密钥文件权限正确（必要）
chmod 600 "$SSH_KEY_PATH"

# 启动ssh-agent并添加密钥，避免多次输入密码
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$SSH_KEY_PATH"

if [ $? -ne 0 ]; then
  echo "❌ 错误：SSH密钥加载失败，请检查密钥密码是否正确。"
  exit 1
fi

echo "✅ SSH密钥加载完成，准备连接服务器..."

# ===============================
# 检查巡检脚本和服务器列表
# ===============================

if [ ! -f "$SCRIPT_FILE" ]; then
  echo "❌ 没找到巡检脚本 $SCRIPT_FILE"
  exit 1
fi

if [ ! -f "$SERVER_LIST" ]; then
  echo "❌ 没找到服务器列表 $SERVER_LIST"
  exit 1
fi

# ===============================
# 遍历每一行服务器
# ===============================

while IFS= read -r line || [ -n "$line" ]; do
  USER_HOST=$(echo $line | cut -d'|' -f1)
  SERVER_TAG=$(echo $line | cut -d'|' -f2)
  HOST=$(echo $USER_HOST | cut -d':' -f1)
  PORT=$(echo $USER_HOST | cut -d':' -f2)

  echo "🚀 正在部署到 $USER_HOST - [$SERVER_TAG]..."

  # 复制脚本到服务器
  scp -i "$SSH_KEY_PATH" -P $PORT "$SCRIPT_FILE" "$HOST:/root/lazy-maintenance-multi.sh"

  # 连接服务器，修改 SERVER_TAG，授权执行，设置 crontab
  ssh -i "$SSH_KEY_PATH" -p $PORT "$HOST" <<EOF
    sed -i 's/^SERVER_TAG=.*/SERVER_TAG="$SERVER_TAG"/' /root/lazy-maintenance-multi.sh
    chmod +x /root/lazy-maintenance-multi.sh
    (crontab -l 2>/dev/null; echo "0 4 * * 0 /root/lazy-maintenance-multi.sh >> /var/log/lazy.log 2>&1") | crontab -
EOF

  echo "✅ [$SERVER_TAG] 部署完成！"
  echo "--------------------------------------"

done < "$SERVER_LIST"

echo "🎯 所有服务器部署完成！收工喝茶 🍵"

# 关闭 ssh-agent
eval "$(ssh-agent -k)" >/dev/null