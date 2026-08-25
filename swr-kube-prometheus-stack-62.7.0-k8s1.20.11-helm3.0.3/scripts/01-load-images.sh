#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARCHIVE="$ROOT/images/monitoring-images.tar"
[[ $EUID -eq 0 ]] || { echo "请使用 root 执行"; exit 1; }
[[ -f "$ARCHIVE" ]] || { echo "找不到镜像归档: $ARCHIVE"; exit 1; }
if command -v ctr >/dev/null 2>&1; then
  ctr -n k8s.io images import "$ARCHIVE"
elif command -v nerdctl >/dev/null 2>&1; then
  nerdctl -n k8s.io load -i "$ARCHIVE"
elif command -v docker >/dev/null 2>&1; then
  docker load -i "$ARCHIVE"
else
  echo "未找到 ctr、nerdctl 或 docker" >&2
  exit 1
fi
echo "镜像导入完成。本脚本需要在每个可调度 Kubernetes 节点执行。"
