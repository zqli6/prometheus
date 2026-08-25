# 监控平台离线部署包 V2

该包已经将“离线镜像”和“真正安装的 Helm Chart”完全分离，避免以下问题：

- Helm 扫描大型镜像归档后被 OOM Killer 终止。
- 外层包装 Chart 导致 Helm Release Secret 超过 1 MiB。
- 大型 CRD 使用客户端 Apply 时 annotation 超过 256 KiB。

## 目录

```text
chart/       原始 kube-prometheus-stack 62.7.0 Chart，只安装这个目录
crds/        Prometheus Operator CRD
images/      9 个离线镜像及镜像清单
scripts/     分步部署脚本
backup/      源环境 Grafana Dashboard、数据源及 grafana.db 备份
values.yaml  直接作用于原始 Chart 的配置
```

## 默认配置

- Grafana NodePort：31169，PVC：10 GiB
- Prometheus NodePort：31212，PVC：50 GiB，保留期：10 天
- Alertmanager：不部署；告警规则（PrometheusRule）：不创建（仅资源监控）
- PVC 使用目标集群默认动态 StorageClass
- Grafana 默认账号：`admin / prom-operator`

## 部署步骤

### 1. 在每个可调度 Kubernetes 节点导入镜像

把完整目录传到节点后执行：

```bash
chmod +x scripts/*.sh
sudo ./scripts/01-load-images.sh
```

> Grafana 的 initChownData init 容器需要 `docker.io/library/busybox:1.36.1`，
> 该镜像不在本包内，需单独导入到所有可调度节点（导入后的镜像名必须与之一致）。

### 2. 在 Kubernetes 管理节点安装 CRD

```bash
./scripts/02-install-crds.sh
```

该脚本使用 Server-Side Apply，不会出现 CRD annotation 超限。
`03-install-monitoring.sh` 已内置此步骤（幂等），即使跳过 02 也会先以 SSA 安装/更新 CRD——
若集群残留旧版 Prometheus Operator CRD（旧 duration 正则不认 `10m`），此步骤会将其覆盖更新。

### 3. 安装监控平台

```bash
./scripts/03-install-monitoring.sh
```

也可以完全手动安装：

```bash
kubectl apply --server-side --force-conflicts -f ./crds
helm lint ./chart -f ./values.yaml
kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring
helm upgrade --install monitoring-offline ./chart \
  -n monitoring \
  -f ./values.yaml --timeout 15m
```

> 兼容 Helm 3.0.x(三星环境):
> - grafana 子 Chart 中依赖 Helm 3.1+ 的 `lookup`、规则模板中的 `dig`、node-exporter 中的
>   `fromYamlArray` 均已移除或替换为等价实现。
> - 命令不再使用 `--create-namespace`(3.2.0+)、`--dependency-update`(3.1.0+)、`--skip-crds`(3.1.0+)。
>   CRD 由 `scripts/02-install-crds.sh` 以 Server-Side Apply 安装,values.yaml 中 `crds.enabled: false`
>   已禁用 crds 子 Chart,两者配合避免 Helm 重复安装 CRD。
> - `helm template` 在 Helm 3.0.x 不可用(默认假定 K8s v1.16.0 且无 `--kube-version` 旗标),
>   渲染检查请改用 `helm upgrade --install ... --dry-run`(连集群取真实版本)。

不要运行 `helm install ... .`，当前根目录不是 Helm Chart；必须安装 `./chart`。

### 4. 验证

```bash
./scripts/04-verify.sh
kubectl get pods -n monitoring -w
```

访问：

- Grafana：`http://任一节点IP:31169`
- Prometheus：`http://任一节点IP:31212`

## 常见问题

### Pod 为 ImagePullBackOff

在 Pod 所在节点重新执行：

```bash
sudo ./scripts/01-load-images.sh
```

若为 Grafana 的 init 容器（init-chown-data），确认该节点已单独导入
`docker.io/library/busybox:1.36.1`（不在本包镜像内）。

### 安装报 PrometheusRule `for` 校验失败

```text
Error: PrometheusRule.monitoring.coreos.com "..." is invalid: spec.groups.rules.for ...
```

集群残留旧版 Prometheus Operator CRD。执行 `./scripts/02-install-crds.sh` 覆盖更新后再重装。
本包默认不创建告警规则，此错误仅在启用告警时出现。

### PVC 为 Pending

```bash
kubectl get storageclass
kubectl describe pvc -n monitoring
kubectl get pods -A | grep -Ei 'nfs|provision'
```

目标集群必须存在默认动态 StorageClass。

### 查看完整状态

```bash
helm status monitoring-offline -n monitoring
kubectl get pods,svc,pvc -n monitoring -o wide
kubectl get pv
```

## 卸载

```bash
helm uninstall monitoring-offline -n monitoring
```

PVC/PV 可能保留数据。确认不再需要数据后再删除，不要直接删除 Prometheus Operator CRD。
