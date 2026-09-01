# Dashboard 推荐与资源规划

## 1. 目标与结论

本文面向三星人寿当前这套监控平台（Prometheus + Grafana + node-exporter + kube-state-metrics），目标是解决以下问题：

- 看**整个集群资源汇总**
- 看**每个 Node 资源**
- 看**每个 Namespace 资源**
- 看**每个 Pod / Workload 资源**
- 看**QPS / P95 / P99**
- 做 **Pod requests / limits** 规划
- 解释为什么有些 dashboard 会 `No data`

### 结论先说

最稳的做法不是只找“一个万能大盘”，而是按三层组合：

1. **官方 / 半官方优先**：kube-prometheus-stack 自带的 Kubernetes mixin / node-exporter mixin 仪表盘
2. **社区经典补洞**：补 requests / limits、命名空间容量、Ingress QPS/P95/P99 等视图
3. **自定义业务盘**：针对 Nginx / Java / Go / Python 应用的业务流量与性能盘

> 重要说明：
>
> 当前如果配置了：
>
> ```yaml
> defaultRules:
>   create: false
> ```
>
> 那么关闭的不只是**告警规则（alerting rules）**，还包括大量 **recording rules（聚合规则）**。
> 很多官方 Cluster / Namespace / Pod 汇总盘依赖这些 recording rules，
> 所以会出现 **原始指标有、单节点盘有数据，但汇总盘 No data** 的现象。
>
> 如果想保留“仅资源监控、不发告警”，推荐：
>
> - `alertmanager.enabled: false`
> - `defaultRules.create: true`
>
> 然后先执行：
>
> ```bash
> ./scripts/02-install-crds.sh
> ./scripts/03-install-monitoring.sh
> ```
>
> 这样既不真正部署告警通道，又能保留官方大盘依赖的聚合指标。

---

## 2. 当前包里已经有的优秀 Dashboard

当前离线包 `grafana-dashboards.yaml` 中，已经包含一批质量很高的大盘，核心来源是：

- **kubernetes-mixin**
- **node-exporter mixin**
- **kube-prometheus-stack**

它们比随机找的 Grafana 社区盘更稳定，适合作为默认基线。

### 2.1 整个集群资源汇总

#### 1）Kubernetes / Compute Resources / Cluster

用途：

- 整个集群 CPU / 内存 / 资源分布汇总
- 适合看整体负载、整体资源紧张程度

特点：

- 更偏平台/运维总览
- 很多图依赖 recording rules

#### 2）Kubernetes / Networking / Cluster

用途：

- 集群整体网络流量
- 按 namespace 聚合网络使用情况

特点：

- 很适合定位哪个命名空间流量大
- 你当前包里可见 `cluster-total.json` 这类 Cluster 网络汇总盘

#### 3）Node Exporter / USE Method / Cluster

用途：

- 所有节点的 CPU / Memory / Disk / Network 汇总视图
- 用 USE（Utilization / Saturation / Errors）方法看基础设施健康度

依赖：

- node-exporter

---

### 2.2 每个 Node 资源

#### 4）Node Exporter / Nodes

用途：

- 看单个节点 CPU、Load、Memory、Disk、Filesystem、Network
- 适合排查某台机器高负载、磁盘打满、网卡异常

特点：

- 社区最经典、最稳的大盘之一
- 通常数据最全、问题最少

#### 5）Kubernetes / Compute Resources / Node (Pods)

用途：

- 按 Node 看它上面承载了哪些 Pod
- 看某台节点的 Pod 资源占用情况

适合：

- 调度分析
- 某 Node 被某类 Pod 压垮的排查

---

### 2.3 每个 Namespace 资源

#### 6）Kubernetes / Compute Resources / Namespace (Pods)

用途：

- 按命名空间汇总 CPU / 内存 / Pod 数量
- 最适合做“哪个业务最吃资源”的分析

适合：

- 成本归属
- 环境隔离分析
- namespace 级别资源规划

#### 7）Kubernetes / Networking / Namespace (Pods)

用途：

- 按命名空间看网络流量
- 发现高流量租户、异常网络行为

---

### 2.4 每个 Pod / Workload 资源

#### 8）Kubernetes / Compute Resources / Pod

用途：

- 看单个 Pod CPU / 内存 / 重启 / 生命周期状态
- 适合排查具体应用 Pod 问题

#### 9）Kubernetes / Compute Resources / Workload

用途：

- 按 Deployment / StatefulSet / DaemonSet 看整体资源
- 比一个个 Pod 看更符合运维视角

适合：

- 看某个服务整体资源趋势
- 做 requests / limits 调优

---

## 3. 哪些 Dashboard `No data` 是正常的，哪些不是

### 3.1 正常会空的（不是故障）

如果是阿里云托管 Kubernetes（ACK 等）或控制面不在你的节点上，以下大盘经常空：

- **Kubernetes / Controller Manager**
- **Kubernetes / Scheduler**
- **Kubernetes / Etcd**
- **Alertmanager / Overview**（你已关闭 Alertmanager）

原因：

- 托管集群通常不暴露这些 control plane 组件的监控 endpoint
- 或者你明确关闭了 Alertmanager

这类 `No data` **不代表坏掉**。

### 3.2 不正常的空盘

以下这些如果空，就通常不是“正常现象”：

- **Kubernetes / Compute Resources / Cluster**
- **Kubernetes / Compute Resources / Namespace (Pods)**
- **Kubernetes / Compute Resources / Pod**
- **Node Exporter / USE Method / Cluster**
- **Node Exporter / Nodes**
- **Kubernetes / Networking / Cluster**

常见原因：

1. Prometheus 采集 target 没起来
2. kube-state-metrics 没采到
3. node-exporter 没采到
4. `defaultRules.create: false`，导致 recording rules 没生成
5. Grafana 数据源没连到 Prometheus

---

## 4. 为什么安装了 node-exporter 和 kube-state-metrics 还会 No data

这是当前最容易误判的点。

### 4.1 原始指标 vs 聚合指标

`node-exporter` 和 `kube-state-metrics` 提供的是**原始指标**，比如：

- `node_cpu_seconds_total`
- `node_memory_MemAvailable_bytes`
- `container_memory_working_set_bytes`
- `kube_pod_info`
- `kube_pod_container_resource_requests`

而很多优秀 dashboard（尤其是 Cluster / Namespace 汇总盘）查的是**聚合后的 recording rule 指标**，比如：

- `instance:node_cpu_utilisation:rate5m`
- `namespace_workload_pod:kube_pod_owner:relabel`
- `cluster_quantile:apiserver_request_sli_duration_seconds:histogram_quantile`
- `code_resource:apiserver_request_total:rate5m`

这些 recording rule 只有在：

```yaml
defaultRules:
  create: true
```

时才会创建。

### 4.2 验证方法

在 Prometheus 页面里分别查：

#### 原始指标（应有数据）

```promql
node_cpu_seconds_total
```

#### recording rule 聚合指标（若无数据则说明规则没启用）

```promql
instance:node_cpu_utilisation:rate5m
```

如果：

- 原始指标有数据
- recording rule 指标没数据

那么就不是 dashboard 坏，而是 **recording rules 没装**。

---

## 5. 外部 Dashboard 导入说明（已修订）

> **更正（2026-08-24）**：本文此前写的 “Requests / Limits / Overcommit Dashboard”、
> “Ingress / Nginx QPS / P95 / P99 Dashboard”、
> “Namespace Capacity / Utilization Dashboard” 是**能力分类**，不是 Grafana.com 上可直接搜索、
> 可直接导入的 Dashboard 精确名称或 ID。不能把它们当作实际 Dashboard 去官网搜索。
>
> 由于当前没有完成对 Grafana.com 条目、Dashboard ID、维护状态及指标前提的逐项可访问验证，
> **本包暂不推荐任何外部 Grafana.com Dashboard ID，也不在本文编造中文 Dashboard 名称、ID 或链接。**
> 外部 Dashboard 的导入必须在目标环境联网后，逐个确认来源、JSON 内容、PromQL 指标和维护状态。

### 5.1 当前已验证、已导入的 Dashboard

当前 Grafana 实例已经实际存在以下 Dashboard。这些来自 kube-prometheus-stack 的
Kubernetes mixin / node-exporter mixin，**不需要到 Grafana.com 搜索或二次导入**：

| 监控目标 | Grafana 中的精确标题 | Grafana URI | 指标前提 |
|---|---|---|---|
| 集群资源汇总 | `Kubernetes / Compute Resources / Cluster` | `db/kubernetes-compute-resources-cluster` | kubelet/cAdvisor、kube-state-metrics、recording rules |
| Node 资源 | `Node Exporter / Nodes` | `db/node-exporter-nodes` | node-exporter |
| Node USE 视图 | `Node Exporter / USE Method / Cluster` | `db/node-exporter-use-method-cluster` | node-exporter、recording rules |
| Node 上 Pod 资源 | `Kubernetes / Compute Resources / Node (Pods)` | `db/kubernetes-compute-resources-node-pods` | kubelet/cAdvisor、kube-state-metrics、recording rules |
| Namespace Pod 资源 | `Kubernetes / Compute Resources / Namespace (Pods)` | `db/kubernetes-compute-resources-namespace-pods` | kubelet/cAdvisor、kube-state-metrics、recording rules |
| Namespace Workload 资源 | `Kubernetes / Compute Resources / Namespace (Workloads)` | `db/kubernetes-compute-resources-namespace-workloads` | kube-state-metrics、recording rules |
| Pod 资源 | `Kubernetes / Compute Resources / Pod` | `db/kubernetes-compute-resources-pod` | kubelet/cAdvisor、kube-state-metrics、recording rules |
| Workload 资源 | `Kubernetes / Compute Resources / Workload` | `db/kubernetes-compute-resources-workload` | kube-state-metrics、recording rules |
| 集群网络 | `Kubernetes / Networking / Cluster` | `db/kubernetes-networking-cluster` | kubelet/cAdvisor、kube-state-metrics |
| Namespace 网络 | `Kubernetes / Networking / Namespace (Pods)` | `db/kubernetes-networking-namespace-pods` | kubelet/cAdvisor、kube-state-metrics |
| Pod 网络 | `Kubernetes / Networking / Pod` | `db/kubernetes-networking-pod` | kubelet/cAdvisor、kube-state-metrics |
| PVC 使用情况 | `Kubernetes / Persistent Volumes` | `db/kubernetes-persistent-volumes` | kubelet volume metrics、kube-state-metrics |

上述名称已通过当前集群 Grafana HTTP API 的 `/api/search` 实际核实。

### 5.2 对外部导入盘的正确处理方式

如果后续需要补充以下能力：

- requests / limits / overcommit 表格；
- Ingress QPS、4xx/5xx、P95、P99；
- 应用 HTTP QPS、接口级 P95/P99；

不要按“中文能力名称”去 Grafana.com 搜索。应先确认相应指标存在，再确定具体导入 JSON：

| 目标能力 | 必须先确认的指标 / 条件 |
|---|---|
| requests / limits | `kube_pod_container_resource_requests`、`kube_pod_container_resource_limits` 已被 kube-state-metrics 采集 |
| Namespace 配额 | 已真实创建 `ResourceQuota`；否则 `kube_resourcequota` 无数据，CPU Quota 类面板空白属正常 |
| Ingress QPS / P95 / P99 | ingress-nginx controller 已暴露并被采集 `nginx_ingress_controller_requests`、`nginx_ingress_controller_request_duration_seconds_bucket` |
| 应用 QPS / P95 / P99 | 应用已暴露 HTTP counter 与 histogram bucket；例如 `http_server_requests_seconds_count` 和 `http_server_requests_seconds_bucket` |

导入任意外部 Dashboard 前，必须执行：

1. 在 Grafana.com 的实际页面确认 Dashboard ID、作者、最近维护时间和说明；
2. 下载 JSON 后检查所有 PromQL 的指标名、label 和 datasource UID；
3. 先在 Prometheus Web UI 查询关键指标，确认不是空结果；
4. 在测试 Grafana 导入并验证，再导入生产 Grafana；
5. 把最终确认的 Grafana.com 链接、ID、JSON 文件校验和写入本包文档。

### 5.3 中文 Dashboard 说明

当前没有经过验证、可承诺长期可在 Grafana.com 搜索到的“中文官方 Dashboard”。
Grafana.com 上多数 Dashboard 使用英文标题和英文说明。建议保留已验证的官方英文 Dashboard，
在 Grafana 中创建中文 Folder、中文说明或对副本改中文标题；不要为了中文名称导入来源不明的 JSON。

## 6. QPS / P95 / P99 应该怎么做

### 6.1 先分清“看谁的 QPS / 延迟”

至少分 3 类：

1. **Ingress QPS / P95 / P99**
   - 整个平台入口流量
   - 适合看整体趋势

2. **Service / 应用 QPS / P95 / P99**
   - 某个服务整体性能
   - 适合定位某个应用变慢

3. **接口级 QPS / P95 / P99**
   - 某个 URI / API 的性能
   - 适合精细排障

---

### 6.2 如果使用 ingress-nginx（推荐先做）

#### 总 QPS

```promql
sum(rate(nginx_ingress_controller_requests[5m]))
```

#### 按 host / ingress 看 QPS

```promql
sum by (host, ingress) (
  rate(nginx_ingress_controller_requests[5m])
)
```

#### P95

```promql
histogram_quantile(0.95,
  sum by (le, ingress) (
    rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])
  )
)
```

#### P99

```promql
histogram_quantile(0.99,
  sum by (le, ingress) (
    rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])
  )
)
```

#### 4xx / 5xx

```promql
sum by (ingress, status) (
  rate(nginx_ingress_controller_requests{status=~"4..|5.."}[5m])
)
```

---

### 6.3 如果应用自身暴露 HTTP 指标（推荐长期做）

例如 Spring Boot / Micrometer、Go Prometheus client、Python instrumentator：

#### QPS

```promql
sum(rate(http_server_requests_seconds_count{job="your-app"}[5m]))
```

#### 按 URI / status 看 QPS

```promql
sum by (uri, status) (
  rate(http_server_requests_seconds_count{job="your-app"}[5m])
)
```

#### P95

```promql
histogram_quantile(0.95,
  sum by (le, uri) (
    rate(http_server_requests_seconds_bucket{job="your-app"}[5m])
  )
)
```

#### P99

```promql
histogram_quantile(0.99,
  sum by (le, uri) (
    rate(http_server_requests_seconds_bucket{job="your-app"}[5m])
  )
)
```

> 前提：应用必须暴露 **histogram bucket**。
> 如果只有 summary 或简单 timer，则跨实例聚合很难准确做 P95 / P99。

---

## 7. Pod requests / limits 怎么规划

这部分不只是“看盘”，更要形成调优方法。

### 7.1 CPU requests / limits 规划

观察周期建议：

- 至少 **7 天**
- 最好覆盖工作日高峰
- 如有大促/批处理/夜间任务，也要覆盖

重点看：

- CPU P95
- CPU 峰值
- 是否有 HPA
- 是否有 throttling

#### 经验做法

- `request ≈ CPU P95 的 1.2 ~ 1.5 倍`
- `limit ≈ CPU 峰值的 1.2 ~ 1.5 倍`
- 若团队不希望 CPU throttling 太多，可放宽 limit，甚至不设 limit（视规范而定）

#### 示例

某 Pod 过去 7 天：

- 平时 100m
- P95 220m
- 峰值 350m

可考虑：

- `request = 250m`
- `limit = 500m`

#### 常用 PromQL

CPU usage：

```promql
sum by (namespace, pod) (
  rate(container_cpu_usage_seconds_total{container!="",image!=""}[5m])
)
```

CPU usage / request：

```promql
sum by (namespace, pod) (
  rate(container_cpu_usage_seconds_total{container!="",image!=""}[5m])
)
/
sum by (namespace, pod) (
  kube_pod_container_resource_requests{resource="cpu",unit="core"}
)
```

---

### 7.2 Memory requests / limits 规划

Memory 更适合重点看：

- Working Set
- RSS
- P95
- 峰值
- 是否有 OOMKill

#### 经验做法

- `request ≈ Memory P95 working set 的 1.2 ~ 1.3 倍`
- `limit ≈ Memory 峰值的 1.2 ~ 1.3 倍`
- 有 OOM 历史的服务，不要压太紧

#### 常用 PromQL

Memory working set：

```promql
sum by (namespace, pod) (
  container_memory_working_set_bytes{container!="",image!=""}
)
```

Memory usage / request：

```promql
sum by (namespace, pod) (
  container_memory_working_set_bytes{container!="",image!=""}
)
/
sum by (namespace, pod) (
  kube_pod_container_resource_requests{resource="memory",unit="byte"}
)
```

---

### 7.3 最实用的资源规划表

建议定期拉这样一张表：

| 服务 | CPU P95 | CPU Peak | CPU Request | CPU Limit | Memory P95 | Memory Peak | Memory Request | Memory Limit | 建议 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| app-a | 220m | 350m | 500m | 1000m | 700Mi | 900Mi | 1Gi | 2Gi | request 偏大，可下调 |
| app-b | 850m | 1200m | 500m | 1000m | 1.8Gi | 2.2Gi | 1Gi | 2Gi | request 偏小，易被抢占 |

这个表往往比任何单独 dashboard 都更适合做落地调优。

---

## 8. 推荐的最终 Dashboard 组合（适合三星现场）

### 第一层：优先使用包内自带盘

1. **Kubernetes / Compute Resources / Cluster**
2. **Kubernetes / Compute Resources / Namespace (Pods)**
3. **Kubernetes / Compute Resources / Pod**
4. **Kubernetes / Compute Resources / Workload**
5. **Node Exporter / Nodes**
6. **Node Exporter / USE Method / Cluster**
7. **Kubernetes / Networking / Cluster**

### 第二层：外部能力补充（尚未在本包内导入）

以下是需要补齐的**能力**，不是可直接在 Grafana.com 搜索的 Dashboard 名称：

1. requests / limits / overcommit 资源规划视图；
2. Ingress QPS / P95 / P99 视图；
3. Namespace 容量 / 利用率视图。

导入外部 Dashboard 的实际编号、链接和 JSON 必须按 §5.2 的流程在联网环境逐项验证后再记录。

### 第三层：建议自定义一个“三星 AI 平台总览盘”

建议至少包含：

- 总 QPS
- P95 / P99
- 4xx / 5xx
- 各 namespace CPU / memory Top N
- 各服务 Pod Restart Top N
- Node CPU / memory Top N
- PVC 使用率 Top N

这个盘最适合：

- 领导看整体
- 值班运维看风险
- 一线排障快速定位

---

## 9. 对当前环境的直接建议

### 方案 A（推荐）

保留：

```yaml
alertmanager:
  enabled: false
```

恢复：

```yaml
defaultRules:
  create: true
```

然后执行：

```bash
./scripts/02-install-crds.sh
./scripts/03-install-monitoring.sh
```

这样：

- Alertmanager 仍然不部署
- 不发送告警
- recording rules 恢复
- 官方 Cluster / Namespace / Pod 汇总盘恢复正常很多

### 方案 B（不推荐）

继续保持：

```yaml
defaultRules:
  create: false
```

后果：

- 很多聚合大盘持续 `No data`
- 只能依赖原始指标盘
- 后面需要自己做一批“纯原始指标版 dashboard”
- 工作量明显更大

---

## 10. 后续建议补的文档

建议后续再补一份更偏现场交付的文档，例如：

**《三星监控指标与 Dashboard 规划手册》**

建议章节：

1. 当前监控架构说明
2. 哪些 Dashboard 是官方自带
3. 哪些 Dashboard 是社区补充
4. 哪些 No data 属正常
5. QPS / P95 / P99 指标设计
6. Requests / Limits 调优方法
7. 三星现场推荐阈值与容量建议

---

## 11. 官方 / 社区参考方向

本文建议主要基于以下体系整理：

- kube-prometheus-stack 自带 Grafana dashboard
- kubernetes-mixin / node-exporter mixin 的设计思路
- Prometheus `histogram_quantile` 官方用法
- 社区常见的 Kubernetes requests/limits / ingress-nginx 观测实践

后续如果网络条件允许，建议再补充实际 dashboard 链接/ID 到本文附录中。