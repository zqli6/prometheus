#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RELEASE=${RELEASE:-monitoring-offline}
NAMESPACE=${NAMESPACE:-monitoring}
command -v kubectl >/dev/null || { echo "缺少 kubectl"; exit 1; }
command -v helm >/dev/null || { echo "缺少 Helm 3"; exit 1; }
kubectl cluster-info >/dev/null
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}{range .items[?(@.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' | head -n1)
[[ -n "$DEFAULT_SC" ]] || { echo "没有默认 StorageClass，请先配置或在 values.yaml 指定 storageClassName" >&2; exit 1; }
echo "默认 StorageClass: $DEFAULT_SC"
helm lint "$ROOT/chart" -f "$ROOT/values.yaml"
# 先以 SSA 方式安装/更新 CRD(幂等)。现场集群可能残留旧版 PrometheusRule 等 CRD
# (旧版 duration 正则不认 "10m" 这类时长),必须用包内版本覆盖,02 脚本已含此步骤。
kubectl apply --server-side --force-conflicts -f "$ROOT/crds"
# 兼容 Helm 3.0.x: --create-namespace(3.2.0)、--dependency-update(3.1.0)、--skip-crds(3.1.0)均不可用。
# values.yaml 中 crds.enabled=false 已禁用 crds 子 Chart,避免 Helm 以普通方式重复安装 CRD。
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
helm upgrade --install "$RELEASE" "$ROOT/chart" \
  --namespace "$NAMESPACE" \
  -f "$ROOT/values.yaml" --timeout 15m "$@"
echo "安装请求完成。请执行 scripts/04-verify.sh 检查状态。"
