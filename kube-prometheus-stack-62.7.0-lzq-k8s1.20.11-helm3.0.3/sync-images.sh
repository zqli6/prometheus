#!/usr/bin/env bash
#
# sync-images.sh —— 将 kube-prometheus-stack chart 中的【上游原镜像】
# 按 amd64 / arm64 双架构拉取，重命名后推送到西南区 SWR 私有仓库。
#
# 目标命名规则（x86 与 arm 用 -arm 后缀区分）：
#   x86 : swr.cn-southwest-2.myhuaweicloud.com/zqli/<原镜像名>:<原tag>
#   arm : swr.cn-southwest-2.myhuaweicloud.com/zqli/<原镜像名>:<原tag>-arm
#
# 其中 <原镜像名> 保留原 registry 前缀，例如：
#   docker.io/grafana/grafana:11.2.0
#     -> x86: swr.cn-southwest-2.myhuaweicloud.com/zqli/docker.io/grafana/grafana:11.2.0
#     -> arm: swr.cn-southwest-2.myhuaweicloud.com/zqli/docker.io/grafana/grafana:11.2.0-arm
#
# 镜像清单来源：从 chart/ 及 chart/charts/*/ 的 values.yaml 中提取，
# tag 取【实际生效值】（显式 tag 优先，否则用 Chart.yaml 的 appVersion），
# 原 repo / registry 取上游默认（即注释 #registry / #repository 提示的公开仓库）。
#
# 用法：
#   ./sync-images.sh            # 实际拉取并推送
#   ./sync-images.sh --dry-run  # 只打印将执行的 docker 命令，不真正执行
#   ./sync-images.sh --list     # 仅列出镜像清单
#
# 前置：请先登录目标仓库
#   docker login swr.cn-southwest-2.myhuaweicloud.com
#

set -uo pipefail

TARGET_REGISTRY="swr.cn-southwest-2.myhuaweicloud.com/zqli"

# ---------------------------------------------------------------------------
# 原镜像清单：<原镜像名>:<原tag>
# ---------------------------------------------------------------------------
IMAGES=(
  # ===== kube-prometheus-stack 主 chart（appVersion v0.76.1）=====
  "quay.io/prometheus/alertmanager:v0.27.0"                                             # 原 repo quay.io/prometheus/alertmanager，显式 tag
  "quay.io/prometheus-operator/admission-webhook:v0.83.0"                               # 原 repo quay.io/prometheus-operator/admission-webhook，显式 tag
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6"  # 显式 tag
  "quay.io/prometheus-operator/prometheus-operator:v0.76.2"                             # 显式 tag（覆盖 appVersion）
  "quay.io/prometheus-operator/prometheus-config-reloader:v0.76.2"                      # 显式 tag（覆盖 appVersion）
  "quay.io/prometheus/prometheus:v2.54.1"                                               # 显式 tag
  "quay.io/thanos/thanos:v0.39.1"                                                       # 显式 tag（prometheus.thanosImage 与 operator.thanosImage 共用）

  # ===== 子 chart grafana（appVersion 11.2.0）=====
  "docker.io/grafana/grafana:11.2.0"                                                    # tag 留空 -> appVersion 11.2.0
  "docker.io/library/busybox:1.36.1"                                                    # initChownData 容器，显式 tag
  "quay.io/kiwigrid/k8s-sidecar:1.27.4"                                                 # dashboard/datasource sidecar，显式 tag

  # ===== 子 chart kube-state-metrics（appVersion 2.13.0）=====
  "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.9.2"                        # 显式 tag（覆盖 appVersion）
  "quay.io/brancz/kube-rbac-proxy:v0.18.0"                                              # 显式 tag（与 node-exporter 子 chart 共用）

  # ===== 子 chart prometheus-node-exporter（appVersion 1.8.2）=====
  "quay.io/prometheus/node-exporter:v1.9.1"                                             # 显式 tag（覆盖 appVersion）

  # ===== 子 chart prometheus-windows-exporter（appVersion 0.28.1）=====
  "ghcr.io/prometheus-community/windows-exporter:v0.28.1"                               # tag 留空 -> v0.28.1（Windows 专用，Linux 集群可注释）

  # -------------------------------------------------------------------------
  # 以下为可选 / 测试镜像，默认不推送，需要时取消注释：
  # -------------------------------------------------------------------------
  # "docker.io/bats/bats:v1.4.1"                          # grafana testFramework 测试镜像，仅 helm test 使用
  # "docker.io/grafana/grafana-image-renderer:latest"     # 可选远程渲染组件，默认未启用
)

# ---------------------------------------------------------------------------

# 仅列出清单
if [[ "${1:-}" == "--list" ]]; then
  echo "原镜像清单（共 ${#IMAGES[@]} 个）："
  for image in "${IMAGES[@]}"; do
    name="${image%:*}"
    tag="${image##*:}"
    echo "  $image"
    echo "    x86: ${TARGET_REGISTRY}/${name}:${tag}"
    echo "    arm: ${TARGET_REGISTRY}/${name}:${tag}-arm"
  done
  exit 0
fi

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

for image in "${IMAGES[@]}"; do
  name="${image%:*}"
  tag="${image##*:}"

  echo ""
  echo "========== ${image} =========="

  # ---- x86 (amd64) ----
  if run docker pull --platform linux/amd64 "$image"; then
    run docker tag "$image" "${TARGET_REGISTRY}/${name}:${tag}"
    run docker push "${TARGET_REGISTRY}/${name}:${tag}"
    echo "  [x86 完成] ${TARGET_REGISTRY}/${name}:${tag}"
  else
    echo "  !!! x86 拉取失败，跳过: $image"
    continue
  fi

  # ---- arm (arm64) ----
  if run docker pull --platform linux/arm64 "$image"; then
    run docker tag "$image" "${TARGET_REGISTRY}/${name}:${tag}-arm"
    run docker push "${TARGET_REGISTRY}/${name}:${tag}-arm"
    echo "  [arm 完成] ${TARGET_REGISTRY}/${name}:${tag}-arm"
  else
    echo "  !!! arm64 拉取失败（该镜像可能无 arm64 或网络受限），跳过 arm: $image"
  fi
done

echo ""
echo "全部处理完成。"
[[ $DRY_RUN -eq 1 ]] && echo "（本次为 dry-run，未实际拉取/推送）"
