#!/usr/bin/env bash
set -euo pipefail
RELEASE=${RELEASE:-monitoring-offline}
NAMESPACE=${NAMESPACE:-monitoring}
helm list -n "$NAMESPACE" --all
helm status "$RELEASE" -n "$NAMESPACE" || true
echo "== Pods =="
kubectl get pods -n "$NAMESPACE" -o wide
echo "== Services =="
kubectl get svc -n "$NAMESPACE"
echo "== PVC =="
kubectl get pvc -n "$NAMESPACE"
echo "== PV =="
kubectl get pv
echo "Grafana: http://节点IP:31169"
echo "Prometheus: http://节点IP:31212"
