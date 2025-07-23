# 阶段一：Tekton 核心基础设施安装指南

本指南详细介绍如何在 Kubernetes 集群上安装 Tekton 核心基础设施，包括 Pipelines、Dashboard 和 Ingress 配置，实现生产级的 Web UI 访问。

## 📋 阶段一目标

- ✅ 安装 Nginx Ingress Controller（生产级配置）
- ✅ 部署 Tekton Pipelines（最新稳定版）
- ✅ 部署 Tekton Dashboard（Web UI）
- ✅ 配置 Ingress 和 IngressClass（外部访问）
- ✅ 验证完整的安装和访问

## 🏗️ 架构概览

```
┌─────────────────────────────────────────────────┐
│                外部访问                            │
│         http://tekton.10.117.8.154.nip.io/     │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│           Nginx Ingress Controller               │
│          (Host Network + External IP)           │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│              Tekton Dashboard                   │
│           (Service: port 9097)                 │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│            Tekton Pipelines                     │
│        (Core Pipeline Engine)                  │
└─────────────────────────────────────────────────┘
```

## 🔧 前提条件

### 系统要求

- ✅ **Kubernetes 集群**: v1.20+ (推荐 v1.24+)
- ✅ **kubectl**: 配置并可访问集群
- ✅ **Helm**: v3.0+ (用于 Ingress Controller)
- ✅ **管理员权限**: 集群级别的 RBAC 权限
- ✅ **网络访问**: 外部 IP 可达

### 资源要求

| 组件 | CPU | Memory | 存储 |
|------|-----|--------|------|
| **Tekton Pipelines** | 200m | 256Mi | - |
| **Tekton Dashboard** | 100m | 128Mi | - |
| **Nginx Ingress** | 100m | 128Mi | - |
| **总计推荐** | 500m | 512Mi | - |

### 环境配置

```bash
# 设置环境变量
export TEKTON_NAMESPACE="tekton-pipelines"
export NODE_IP="10.117.8.154"
export TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"

# 验证环境
echo "集群信息:"
kubectl cluster-info
echo "节点信息:"
kubectl get nodes -o wide
```

## 🚀 安装步骤

### 步骤 1: 验证环境和清理

```bash
# 检查现有安装
kubectl get namespace ${TEKTON_NAMESPACE} || echo "命名空间不存在，可以继续安装"

# 如果需要清理（可选）
echo "如果需要清理现有安装，运行: ./01-cleanup-tekton-core.sh"
```

### 步骤 2: 安装和配置 Nginx Ingress Controller

#### 2.1 添加 Helm 仓库

```bash
# 添加和更新 Helm 仓库
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 验证仓库
helm search repo ingress-nginx/ingress-nginx
```

#### 2.2 生产级 Ingress 安装

```bash
# 安装 Nginx Ingress Controller (生产级配置)
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.hostNetwork=true \
  --set controller.service.type=ClusterIP \
  --set "controller.service.externalIPs[0]=${NODE_IP}" \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.compute-full-forwarded-for="true" \
  --set controller.config.use-proxy-protocol="false" \
  --set controller.metrics.enabled=true \
  --set controller.podSecurityContext.runAsUser=101 \
  --set controller.podSecurityContext.runAsGroup=101 \
  --set controller.podSecurityContext.fsGroup=101 \
  --timeout=600s \
  --wait
```

#### 2.3 验证 Ingress Controller

```bash
# 检查 Pod 状态
kubectl get pods -n ingress-nginx -o wide

# 检查服务配置
kubectl get svc -n ingress-nginx

# 验证外部访问
curl -I http://${NODE_IP}/ || echo "Ingress Controller 未响应，检查配置"
```

#### 2.4 创建 IngressClass

```bash
# 创建标准 IngressClass
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
EOF

# 验证 IngressClass
kubectl get ingressclass
```

### 步骤 3: 安装 Tekton Pipelines

#### 3.1 安装 Tekton Pipelines

```bash
# 安装最新稳定版 Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# 等待安装完成
echo "等待 Tekton Pipelines 组件启动..."
kubectl wait --for=condition=ready pods --all -n tekton-pipelines --timeout=300s
```

#### 3.2 验证 Pipelines 安装

```bash
# 检查所有 Pod
kubectl get pods -n tekton-pipelines

# 检查关键组件
kubectl get deployment -n tekton-pipelines
kubectl get service -n tekton-pipelines

# 验证 API 版本
kubectl api-versions | grep tekton
```

### 步骤 4: 安装 Tekton Dashboard

#### 4.1 安装 Dashboard

```bash
# 安装 Tekton Dashboard
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# 等待 Dashboard 启动
echo "等待 Tekton Dashboard 启动..."
kubectl wait --for=condition=ready pods -l app=tekton-dashboard -n tekton-pipelines --timeout=300s
```

#### 4.2 验证 Dashboard 安装

```bash
# 检查 Dashboard Pod
kubectl get pods -l app=tekton-dashboard -n tekton-pipelines

# 检查 Dashboard Service
kubectl get svc tekton-dashboard -n tekton-pipelines

# 测试内部连接
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -s http://tekton-dashboard.tekton-pipelines.svc.cluster.local:9097 | head -10
```

### 步骤 5: 配置外部访问 Ingress

#### 5.1 创建 Dashboard Ingress

```bash
# 创建 Tekton Dashboard Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: tekton-pipelines
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
  - host: ${TEKTON_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
EOF
```

#### 5.2 验证 Ingress 配置

```bash
# 检查 Ingress 状态
kubectl get ingress -n tekton-pipelines -o wide

# 验证 DNS 解析
ping -c 3 ${TEKTON_DOMAIN} || echo "DNS 解析失败，可能需要配置 hosts"

# 测试外部访问
curl -v http://${TEKTON_DOMAIN}/ | head -20
```

### 步骤 6: 生产环境优化配置

#### 6.1 资源限制配置

```bash
# 为 Tekton 组件设置资源限制
kubectl patch deployment tekton-dashboard -n tekton-pipelines -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "tekton-dashboard",
          "resources": {
            "requests": {"cpu": "100m", "memory": "128Mi"},
            "limits": {"cpu": "500m", "memory": "512Mi"}
          }
        }]
      }
    }
  }
}'
```

#### 6.2 安全配置

```bash
# 配置 Pod Security Standards
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=restricted
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/audit=restricted
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/warn=restricted

# 配置网络策略（可选）
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-dashboard-access
  namespace: tekton-pipelines
spec:
  podSelector:
    matchLabels:
      app: tekton-dashboard
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 9097
EOF
```

## ✅ 验证安装

### 自动验证

```bash
# 运行阶段一验证脚本
./verify-installation.sh --stage=core
```

### 手动验证

#### 1. 组件状态检查

```bash
# 检查所有组件
kubectl get all -n tekton-pipelines
kubectl get all -n ingress-nginx

# 检查 Ingress
kubectl get ingress -n tekton-pipelines

# 检查 IngressClass
kubectl get ingressclass
```

#### 2. 访问测试

```bash
# Web UI 访问
echo "Tekton Dashboard 访问地址: http://${TEKTON_DOMAIN}/"

# API 访问测试
curl -s http://${TEKTON_DOMAIN}/api/v1/namespaces | jq . || echo "Dashboard API 响应异常"

# 健康检查
curl -s http://${TEKTON_DOMAIN}/health || echo "健康检查失败"
```

#### 3. 功能验证

创建一个简单的测试 Pipeline：

```bash
# 创建测试 Task
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: tekton-pipelines
spec:
  steps:
  - name: echo
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "Hello from Tekton!"
      echo "安装验证成功 ✅"
      date
EOF

# 创建测试 Pipeline
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: hello-pipeline
  namespace: tekton-pipelines
spec:
  tasks:
  - name: say-hello
    taskRef:
      name: hello-world
EOF

# 运行测试 PipelineRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: hello-run-
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: hello-pipeline
EOF

# 检查执行结果
echo "等待 PipelineRun 完成..."
sleep 30
kubectl get pipelinerun -n tekton-pipelines
```

## 🔧 故障排查

### 常见问题

#### 1. Ingress Controller 无法启动

**症状**: Ingress Pod 处于 Pending 或 Error 状态

**解决方案**:
```bash
# 检查节点资源
kubectl describe nodes

# 检查事件
kubectl get events -n ingress-nginx --sort-by=.metadata.creationTimestamp

# 检查权限
kubectl auth can-i create pods --as=system:serviceaccount:ingress-nginx:ingress-nginx
```

#### 2. Dashboard 无法访问

**症状**: 访问 Dashboard URL 返回 502/503 错误

**解决方案**:
```bash
# 检查 Dashboard Pod 状态
kubectl describe pod -l app=tekton-dashboard -n tekton-pipelines

# 检查 Service 端点
kubectl get endpoints tekton-dashboard -n tekton-pipelines

# 检查 Ingress 配置
kubectl describe ingress tekton-dashboard -n tekton-pipelines

# 查看 Ingress Controller 日志
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx -f
```

#### 3. DNS 解析问题

**症状**: 无法解析 tekton.10.117.8.154.nip.io

**解决方案**:
```bash
# 方案 1: 使用 nip.io 自动解析
ping tekton.10.117.8.154.nip.io

# 方案 2: 手动添加 hosts 记录
echo "${NODE_IP} ${TEKTON_DOMAIN}" | sudo tee -a /etc/hosts

# 验证解析
nslookup ${TEKTON_DOMAIN}
```

### 调试命令

```bash
# 查看所有事件
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp

# 查看关键组件日志
kubectl logs -l app=tekton-pipelines-controller -n tekton-pipelines
kubectl logs -l app=tekton-dashboard -n tekton-pipelines
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx

# 检查资源使用
kubectl top nodes
kubectl top pods -n tekton-pipelines
kubectl top pods -n ingress-nginx
```

## 🧹 清理

### 选择性清理

```bash
# 只删除测试资源
kubectl delete pipelinerun --all -n tekton-pipelines
kubectl delete pipeline hello-pipeline -n tekton-pipelines
kubectl delete task hello-world -n tekton-pipelines

# 删除 Ingress 配置
kubectl delete ingress tekton-dashboard -n tekton-pipelines
```

### 完全清理

```bash
# 运行自动清理脚本
./01-cleanup-tekton-core.sh

# 手动清理步骤
kubectl delete -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
kubectl delete -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx tekton-pipelines
kubectl delete ingressclass nginx
```

## 📊 生产环境建议

### 监控和日志

- **Prometheus**: 监控 Tekton 组件性能
- **Grafana**: 可视化 Pipeline 执行状态
- **ELK Stack**: 集中日志管理
- **Alertmanager**: 故障告警

### 安全加固

- **HTTPS**: 配置 SSL/TLS 证书
- **认证**: 集成 OIDC/LDAP 认证
- **授权**: 细粒度 RBAC 权限控制
- **网络**: 限制网络访问策略

### 高可用性

- **多副本**: Dashboard 和 Controller 多实例
- **资源限制**: 合理的 CPU/Memory 限制
- **持久化**: 配置数据持久化存储
- **备份**: 定期备份配置和数据

## 🎯 完成标志

阶段一安装成功后，您应该能够：

- ✅ 访问 `http://tekton.10.117.8.154.nip.io/` 看到 Tekton Dashboard
- ✅ 在 Dashboard 中查看 Namespaces、Pipelines、Tasks
- ✅ 手动创建和运行 PipelineRun
- ✅ 监控 Pipeline 执行状态和日志

**🎉 阶段一完成！现在可以继续进行[阶段二：CI/CD 自动化配置](./02-tekton-triggers-setup.md)** 