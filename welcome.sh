#!/bin/bash

# =============================
 # @Author: Lao Qiao
 # @Date: 2025-04-26 15:29:53
 # @LastEditTime: 2025-04-26 16:42:06
 # @LastEditors: Lao Qiao
 # @FilePath: welcome.sh
 # 我秃了，但我更强了~
# =============================

# 彩色定义
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# 基本系统信息
HOSTNAME=$(hostname)

# 更优雅防爆炸版
# 先试着通过接口拿公网IP
IP_ADDR=$(curl -s --max-time 3 https://ipv4.ip.sb/ip)
IP_ADDR=$(echo "$IP_ADDR" | tr -d '\r\n')

# 检查是否是合法IPv4，如果不是，再用hostname本地兜底
if ! echo "$IP_ADDR" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  IP_ADDR=$(hostname -I 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
  IP_ADDR=$(echo "$IP_ADDR" | tr -d '\r\n')
fi

# 最后如果还不是合法IP，标记获取失败
if ! echo "$IP_ADDR" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  IP_ADDR="获取失败"
fi

UPTIME_INFO=$(uptime -p)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ ]*//')

# 内存、磁盘信息
MEMORY_INFO=$(free -m | awk '/Mem:/ {print $3" MiB / "$2" MiB"}')
DISK_INFO=$(df -h / | awk 'NR==2 {print $3" / "$2}')
DISK_USAGE_PERCENT=$(df -h / | awk 'NR==2 {print $5}')

# CPU 温度
if command -v sensors &> /dev/null; then
  CPU_TEMP=$(sensors | grep -m1 -E 'Package id 0|Core 0' | awk '{print $4}')
else
  CPU_TEMP="N/A"
fi

# Docker状态
if command -v docker &> /dev/null; then
  DOCKER_COUNT=$(docker ps -q | wc -l)
else
  DOCKER_COUNT="未安装"
fi

# Fail2ban状态
if command -v fail2ban-client &> /dev/null; then
  BANNED_IPS=$(fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | awk '{print $NF}')
  [ -z "$BANNED_IPS" ] && BANNED_IPS=0
else
  BANNED_IPS="未安装"
fi

# 上次登录信息
LAST_LOGIN=$(last -i | grep -v 'still logged in' | head -n 1 | awk '{print $3" "$4" "$5" "$6" "$7" from "$3}')

# 检查关键服务
check_service() {
  systemctl is-active --quiet "$1" && echo -e "${GREEN}运行中${NC}" || echo -e "${RED}停止${NC}"
}

STATUS_REDIS=$(check_service redis)
STATUS_DOCKER=$(check_service docker)
STATUS_NGINX=$(check_service nginx)
STATUS_MYSQL=$(check_service mysql)

# 输出欢迎页
echo -e "${CYAN}"
echo "┌───────────────────────────────────────────────────────────────────────────────────┐"
echo "│ 欢迎回来，${USER}@${HOSTNAME}"
echo "├───────────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🌐 外网IP地址： ${IP_ADDR}"
echo "│ 🕰️  系统运行时间： ${UPTIME_INFO}"
echo "│ 📈 系统负载 (1/5/15 min)： ${LOAD_AVG}"
echo "│ 🧠 内存使用情况： ${MEMORY_INFO}"
echo "│ 💾 磁盘使用情况： ${DISK_INFO} (已用 ${DISK_USAGE_PERCENT})"
echo "│ 🌡️  CPU温度： ${CPU_TEMP}"
echo "│ 🔎 上次登录信息： ${LAST_LOGIN}"
echo "├───────────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🐳 Docker容器数量： ${DOCKER_COUNT}"
echo "│ 🔒 Fail2ban封禁IP数： ${BANNED_IPS}"
echo "│ 🧩 Redis服务状态： ${STATUS_REDIS}"
echo "│ 🧩 Docker服务状态： ${STATUS_DOCKER}"
echo "│ 🧩 Nginx服务状态： ${STATUS_NGINX}"
echo "│ 🧩 MySQL服务状态： ${STATUS_MYSQL}"
echo "└───────────────────────────────────────────────────────────────────────────────────┘"
echo -e "${NC}\n"

# ==== 今日彩蛋 ====

# 今日摸鱼指数
FISH_INDEX=$(( RANDOM % 41 + 60 ))

# 今日幸运色
COLORS=("红色" "蓝色" "绿色" "紫色" "橙色" "粉色" "黑色" "白色" "金色" "银色")
RANDOM_COLOR=${COLORS[$RANDOM % ${#COLORS[@]}]}

# 今日运势格言
QUOTES=(
  "相信过程，相信自己。🚀"
  "今天的努力，成就明天的自己。💪"
  "稳定压倒一切。🛡️"
  "偶尔摸鱼，也是为了更好的出发。🐟"
  "保持微笑，代码会更顺利。😊"
  "服务器稳定如你，风度翩翩。🖥️✨"
  "技术即力量，心态即未来。⚡"
)
RANDOM_QUOTE=${QUOTES[$RANDOM % ${#QUOTES[@]}]}

# 输出彩蛋
echo -e "${YELLOW}"
echo "🌈 今日摸鱼指数：${FISH_INDEX}%"
echo "🎨 今日幸运色：${RANDOM_COLOR}"
echo "📜 今日运势格言：${RANDOM_QUOTE}"
echo -e "${NC}\n"

# ==== 网络测速小彩蛋 ====

echo -e "${CYAN}📡 网络测速小彩蛋：${NC}"

# 定义测速目标
declare -A TEST_TARGETS
TEST_TARGETS=(
    ["Google"]="8.8.8.8"
    ["OpenAI"]="api.openai.com"
    ["Grok"]="grok.x.ai"
    ["Netflix"]="www.netflix.com"
    ["Aliyun"]="aliyun.com"
    ["Tencent Cloud"]="cloud.tencent.com"
    ["GitHub"]="github.com"
)

# 测速函数
test_latency() {
  local name=$1
  local host=$2
  local ping_result

  ping_result=$(ping -c 1 -W 1 "$host" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | awk '{print $1 " ms"}')

  if [ -z "$ping_result" ]; then
    echo -e "❌ ${RED}${name}${NC} 测试失败"
  else
    echo -e "✅ ${GREEN}${name}${NC} 延迟: ${YELLOW}${ping_result}${NC}"
  fi
}

# 遍历测速
for site in "${!TEST_TARGETS[@]}"; do
  test_latency "$site" "${TEST_TARGETS[$site]}"
done

echo ""