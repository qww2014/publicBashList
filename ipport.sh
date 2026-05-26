#!/usr/bin/env bash
set -euo pipefail

TARGET="/usr/local/bin/ipport"
SCRIPT_URL="https://raw.githubusercontent.com/qww2014/publicBashList/refs/heads/main/ipport.sh"
COMMENT_PREFIX="ipport-toggle"

die() {
  echo "错误：$*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请用 root 运行，例如：sudo ipport"
  fi
}

install_self() {
  need_root

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o "$TARGET"
  else
    [ -r "${BASH_SOURCE[0]}" ] || die "未找到 curl，且无法读取当前脚本"
    cp "${BASH_SOURCE[0]}" "$TARGET"
  fi

  chmod +x "$TARGET"
  echo "安装完成。以后直接运行：sudo ipport"
}

ipt() {
  iptables "$@"
}

rule_exists() {
  ipt -C "$@" >/dev/null 2>&1
}

insert_once() {
  local chain="$1"
  shift

  if ! rule_exists "$chain" "$@"; then
    ipt -I "$chain" 1 "$@"
  fi
}

delete_all() {
  local chain="$1"
  shift

  while rule_exists "$chain" "$@"; do
    ipt -D "$chain" "$@"
  done
}

has_chain() {
  ipt -nL "$1" >/dev/null 2>&1
}

host_ip() {
  ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1
}

detect_container_ips() {
  local host_port="$1"

  if [ -n "${CONTAINER_IP:-}" ]; then
    echo "$CONTAINER_IP"
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  local ids
  ids="$(docker ps --filter "publish=${host_port}" -q 2>/dev/null || true)"
  [ -n "$ids" ] || return

  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' $ids 2>/dev/null |
    tr ' ' '\n' |
    sed '/^$/d' |
    sort -u
}

protect_container() {
  local container_ip="$1"
  local public_ip="$2"

  delete_all DOCKER-USER -p tcp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT
  delete_all DOCKER-USER -p udp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT

  if [ -n "$public_ip" ]; then
    delete_all DOCKER-USER -p tcp -s "$public_ip" -d "$container_ip" -j ACCEPT
    delete_all DOCKER-USER -p udp -s "$public_ip" -d "$container_ip" -j ACCEPT
  fi

  delete_all DOCKER-USER -p tcp -d "$container_ip" -j DROP
  delete_all DOCKER-USER -p udp -d "$container_ip" -j DROP

  insert_once DOCKER-USER -p udp -d "$container_ip" -j DROP
  insert_once DOCKER-USER -p tcp -d "$container_ip" -j DROP

  if [ -n "$public_ip" ]; then
    insert_once DOCKER-USER -p udp -s "$public_ip" -d "$container_ip" -j ACCEPT
    insert_once DOCKER-USER -p tcp -s "$public_ip" -d "$container_ip" -j ACCEPT
  fi

  insert_once DOCKER-USER -p udp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT
  insert_once DOCKER-USER -p tcp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT
}

open_port() {
  local host_port="$1"
  local container_port="$2"
  local comment="${COMMENT_PREFIX}:${host_port}"

  insert_once INPUT -p tcp --dport "$host_port" -m comment --comment "$comment" -j ACCEPT
  insert_once INPUT -p udp --dport "$host_port" -m comment --comment "$comment" -j ACCEPT

  if has_chain DOCKER-USER; then
    local ips
    ips="$(detect_container_ips "$host_port" || true)"

    if [ -n "$ips" ]; then
      while IFS= read -r container_ip; do
        insert_once DOCKER-USER -p tcp -d "$container_ip" --dport "$container_port" -m comment --comment "$comment" -j ACCEPT
        insert_once DOCKER-USER -p udp -d "$container_ip" --dport "$container_port" -m comment --comment "$comment" -j ACCEPT
      done <<< "$ips"
    else
      echo "提示：未识别到 Docker 容器 IP。如仍不能访问，可这样执行："
      echo "CONTAINER_IP=172.xx.xx.xx sudo ipport"
    fi
  fi

  echo "已开启 IP:${host_port} 直连访问。"
}

close_port() {
  local host_port="$1"
  local container_port="$2"
  local comment="${COMMENT_PREFIX}:${host_port}"

  delete_all INPUT -p tcp --dport "$host_port" -m comment --comment "$comment" -j ACCEPT
  delete_all INPUT -p udp --dport "$host_port" -m comment --comment "$comment" -j ACCEPT

  if ! rule_exists INPUT -p tcp --dport "$host_port" -j DROP; then
    ipt -I INPUT 1 -p tcp --dport "$host_port" -j DROP
  fi

  if ! rule_exists INPUT -p udp --dport "$host_port" -j DROP; then
    ipt -I INPUT 1 -p udp --dport "$host_port" -j DROP
  fi

  if has_chain DOCKER-USER; then
    local ips public_ip
    ips="$(detect_container_ips "$host_port" || true)"
    public_ip="$(host_ip || true)"

    if [ -n "$ips" ]; then
      while IFS= read -r container_ip; do
        delete_all DOCKER-USER -p tcp -d "$container_ip" --dport "$container_port" -m comment --comment "$comment" -j ACCEPT
        delete_all DOCKER-USER -p udp -d "$container_ip" --dport "$container_port" -m comment --comment "$comment" -j ACCEPT
        protect_container "$container_ip" "$public_ip"
      done <<< "$ips"
    else
      echo "提示：未识别到 Docker 容器 IP，已处理 INPUT 规则。"
      echo "如需补 Docker 防护，可这样执行：CONTAINER_IP=172.xx.xx.xx sudo ipport"
    fi
  fi

  echo "已禁止 IP:${host_port} 直连访问，域名反代应仍可用。"
}

show_status() {
  local host_port="$1"
  local container_port="$2"
  local comment="${COMMENT_PREFIX}:${host_port}"

  echo "端口：$host_port"
  echo
  echo "INPUT 相关规则："
  ipt -S INPUT | grep -E -- "(--dport ${host_port}|${comment})" || true

  if has_chain DOCKER-USER; then
    echo
    echo "DOCKER-USER 相关规则："
    ipt -S DOCKER-USER | grep -E -- "(${comment}|--dport ${container_port}|-j DROP|-j ACCEPT)" || true
  fi

  echo
  echo "识别到的 Docker 容器 IP："
  detect_container_ips "$host_port" || true
}

read_port() {
  local port
  read -r -p "请输入端口号，例如 18317：" port
  [[ "$port" =~ ^[0-9]+$ ]] || die "端口号必须是数字"
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "端口号范围必须是 1-65535"
  echo "$port"
}

interactive_menu() {
  need_root

  clear 2>/dev/null || true
  echo "IP+端口访问管理"
  echo "1. 开启 IP+端口访问"
  echo "2. 禁止 IP+端口访问"
  echo "3. 查看当前规则"
  echo "0. 退出"
  echo

  local choice host_port container_port
  read -r -p "请选择：" choice

  case "$choice" in
    1)
      host_port="$(read_port)"
      container_port="${CONTAINER_PORT:-$host_port}"
      open_port "$host_port" "$container_port"
      ;;
    2)
      host_port="$(read_port)"
      container_port="${CONTAINER_PORT:-$host_port}"
      close_port "$host_port" "$container_port"
      ;;
    3)
      host_port="$(read_port)"
      container_port="${CONTAINER_PORT:-$host_port}"
      show_status "$host_port" "$container_port"
      ;;
    0)
      exit 0
      ;;
    *)
      die "无效选择"
      ;;
  esac
}

case "${1:-}" in
  --install)
    install_self
    ;;
  --help|-h)
    echo "用法："
    echo "  bash <(curl -fsSL $SCRIPT_URL)"
    echo "  sudo ipport"
    echo "  CONTAINER_IP=172.xx.xx.xx sudo ipport"
    ;;
  *)
    if [ "$(basename "$0")" != "ipport" ]; then
      install_self
    else
      interactive_menu
    fi
    ;;
esac
