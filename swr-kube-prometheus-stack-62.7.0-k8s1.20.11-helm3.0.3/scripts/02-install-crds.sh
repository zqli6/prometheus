#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v kubectl >/dev/null || { echo "缺少 kubectl"; exit 1; }
kubectl cluster-info >/dev/null
kubectl apply --server-side --force-conflicts -f "$ROOT/crds"
echo "Prometheus Operator CRD 安装完成。"
