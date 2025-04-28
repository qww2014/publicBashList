#!/bin/bash

# =============================
# 🚀 Intelligent Server Health Inspector v1.0
# Author: 老乔 & 小美
# =============================

# 备注：使用前请配置好 BOT_TOKEN 和 CHAT_ID

# ==== 配置区 ====
SERVER_TAG="生产环境-01"
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

# 设置导出静默模式，避免升级时跳出互动
export DEBIAN_FRONTEND=noninteractive

# ==== 系统状态收集 ====
HOSTNAME=$(hostname)
IP_ADDR=$(curl -s ifconfig.me || echo "N/A")
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')
CPU_LOAD=$(uptime | awk -F 'load average:' '{ print $2 }' | cut -d',' -f1 | xargs)
CPU_CORES=$(nproc)
MEMORY_INFO=$(free -m)
MEM_USED=$(echo "$MEMORY_INFO" | awk '/Mem:/ {print $3}')
MEM_TOTAL=$(echo "$MEMORY_INFO" | awk '/Mem:/ {print $2}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
DISK_INFO=$(df -h /)
DISK_USED=$(echo "$DISK_INFO" | awk 'NR==2 {print $5}' | sed 's/%//')
DISK_LEFT=$(echo "$DISK_INFO" | awk 'NR==2 {print $4}')
UPTIME_INFO=$(uptime -p)

# ==== 智能健康预警 ====
ALERTS=""

# 内存预警
if [ $MEM_PERCENT -ge 80 ]; then
  ALERTS+="🛑 内存占用高达 ${MEM_PERCENT}%\n"
fi

# 磁盘预警
if [ $DISK_USED -ge 90 ]; then
  ALERTS+="🛑 磁盘使用超过 90%\n"
fi

# CPU负载预警
CPU_LOAD_INT=${CPU_LOAD%.*}
LOAD_THRESHOLD=$((CPU_CORES * 2))
if [ $CPU_LOAD_INT -ge $LOAD_THRESHOLD ]; then
  ALERTS+="🛑 CPU负载超过系统核心数倍\n"
fi

# ==== 服务存活检查与自治 ====
SERVICES=(redis docker nginx mysql)
for service in "${SERVICES[@]}"; do
  systemctl is-active --quiet $service
  if [ $? -ne 0 ]; then
    ALERTS+="🛑 $service 服务已停止，自动重启\n"
    systemctl restart $service
  fi
done

# ==== 网络安全监控 ====
PORTS=$(ss -tunlp | grep -v "127.0.0.1" | grep LISTEN | awk '{print $5}' | cut -d":" -f2 | sort -u)
SUSPICIOUS_PORTS=""
for port in $PORTS; do
  if [[ "$port" -lt 1024 ]] && [[ "$port" != "22" ]] && [[ "$port" != "80" ]] && [[ "$port" != "443" ]]; then
    SUSPICIOUS_PORTS+="🚨 未知低级端口: $port\n"
  fi
done

if [[ -n "$SUSPICIOUS_PORTS" ]]; then
  ALERTS+="$SUSPICIOUS_PORTS"
fi

# ==== 总结消息 ====
if [[ -z "$ALERTS" ]]; then
  STATUS_MSG="🌟 服务器状态良好"
else
  STATUS_MSG="🛑 检测到异常！\n$ALERTS"
fi

# ==== 给 Telegram 发送通知 ====
MESSAGE="[$SERVER_TAG] 服务器完成循检

时间：$DATE_NOW
💻 主机：$HOSTNAME
🌐 IP：$IP_ADDR
⏱️ 运行时长：$UPTIME_INFO
🧰 内存：$MEM_USED MiB / $MEM_TOTAL MiB ($MEM_PERCENT%)
📁 磁盘：剩余 $DISK_LEFT
🔢 CPU负载：$CPU_LOAD

$STATUS_MSG"

echo "📢 正在向 Telegram 发送通知..."
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$MESSAGE" > /dev/null

echo "✅ 循检完成！"
