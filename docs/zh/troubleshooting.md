# Tekton 生产环境部署问题排查指南

本文档总结了在部署 Tekton 生产级系统过程中遇到的常见问题、根本原因和解决方案，按两个阶段进行分类。

## 📋 问题分类概览

### 阶段一：核心基础设施问题
1. **Ingress Controller 安装失败**
2. **Tekton Pipelines 组件启动异常**
3. **Dashboard 无法访问**
4. **DNS 解析和网络连通性问题**
5. **资源限制和权限问题**

### 阶段二：CI/CD 自动化问题
1. **API版本兼容性问题**
2. **RBAC权限不足问题**
3. **Pod Security Standards限制问题**
4. **EventListener 无法启动**
5. **GitHub Webhook 连接失败**
6. **Pipeline 自动触发失败**

---

## 🏗️ 阶段一：核心基础设施问题排查

### 1. Ingress Controller 安装失败

#### 问题现象
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx
Error: INSTALLATION FAILED: failed to create resource: Internal error occurred: admission webhook failed
```

#### 根本原因
- Helm 仓库未更新或版本冲突
- 集群权限不足
- 网络策略阻止 webhook 通信
- 节点资源不足

#### 解决方案

1. **更新 Helm 仓库和重试**：
```bash
helm repo update
helm repo list
helm search repo ingress-nginx/ingress-nginx
```

2. **检查集群权限**：
```bash
kubectl auth can-i create clusterrole
kubectl auth can-i create namespace
```

3. **验证节点资源**：
```bash
kubectl describe nodes
kubectl top nodes
```

4. **清理并重新安装**：
```bash
helm uninstall ingress-nginx -n ingress-nginx || true
kubectl delete namespace ingress-nginx || true
./01-cleanup-tekton-core.sh
./01-install-tekton-core.sh
```

---

### 2. Tekton Pipelines 组件启动异常

#### 问题现象
```bash
kubectl get pods -n tekton-pipelines
NAME                                        READY   STATUS    RESTARTS   AGE
tekton-pipelines-controller-xxx             0/1     Pending   0          5m
tekton-pipelines-webhook-xxx                0/1     Error     3          5m
```

#### 根本原因
- 镜像拉取失败（网络问题或镜像仓库不可达）
- 资源不足（CPU/Memory）
- 存储配置问题
- 服务账户权限不足

#### 解决方案

1. **检查 Pod 详细状态**：
```bash
kubectl describe pod -l app=tekton-pipelines-controller -n tekton-pipelines
kubectl describe pod -l app=tekton-pipelines-webhook -n tekton-pipelines
```

2. **查看 Pod 日志**：
```bash
kubectl logs -l app=tekton-pipelines-controller -n tekton-pipelines
kubectl logs -l app=tekton-pipelines-webhook -n tekton-pipelines
```

3. **检查镜像拉取**：
```bash
# 在节点上手动拉取镜像测试
docker pull gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/controller:latest
```

4. **检查资源使用**：
```bash
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

### 3. Dashboard 无法访问

#### 问题现象
- 访问 `http://tekton.10.117.8.154.nip.io/` 返回 502/503 错误
- 或者页面显示"This site can't be reached"

#### 根本原因
- Dashboard Pod 未运行
- Ingress 配置错误
- DNS 解析失败
- 防火墙或网络策略阻止访问

#### 解决方案

1. **检查 Dashboard Pod 状态**：
```bash
kubectl get pods -l app=tekton-dashboard -n tekton-pipelines
kubectl describe pod -l app=tekton-dashboard -n tekton-pipelines
kubectl logs -l app=tekton-dashboard -n tekton-pipelines -f
```

2. **检查 Service 和 Endpoints**：
```bash
kubectl get svc tekton-dashboard -n tekton-pipelines
kubectl get endpoints tekton-dashboard -n tekton-pipelines
```

3. **检查 Ingress 配置**：
```bash
kubectl get ingress tekton-dashboard -n tekton-pipelines
kubectl describe ingress tekton-dashboard -n tekton-pipelines
```

4. **测试内部连接**：
```bash
kubectl run debug --image=nicolaka/netshoot --rm -it --restart=Never -- \
  curl -v http://tekton-dashboard.tekton-pipelines.svc.cluster.local:9097
```

5. **检查 Ingress Controller 日志**：
```bash
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx -f
```

---

### 4. DNS 解析和网络连通性问题

#### 问题现象
```bash
ping tekton.10.117.8.154.nip.io
ping: cannot resolve tekton.10.117.8.154.nip.io: Unknown host
```

#### 根本原因
- nip.io 服务不可用
- 本地 DNS 配置问题
- 网络防火墙阻止访问

#### 解决方案

1. **检查 nip.io 服务状态**：
```bash
nslookup 10.117.8.154.nip.io
dig 10.117.8.154.nip.io
```

2. **手动添加 hosts 记录**：
```bash
echo "10.117.8.154 tekton.10.117.8.154.nip.io" | sudo tee -a /etc/hosts
```

3. **验证节点 IP 可达性**：
```bash
ping 10.117.8.154
curl -I http://10.117.8.154/
```

4. **检查防火墙规则**：
```bash
# Ubuntu/Debian
sudo ufw status
# CentOS/RHEL
sudo firewall-cmd --list-all
```

---

### 5. 资源限制和权限问题

#### 问题现象
```bash
pods "tekton-dashboard-xxx" is forbidden: violates PodSecurity "restricted:latest"
```

#### 根本原因
- Pod Security Standards 配置过于严格
- 资源限制配置不当
- ServiceAccount 权限不足

#### 解决方案

1. **调整 Pod Security Standards**：
```bash
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/audit=restricted --overwrite
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/warn=restricted --overwrite
```

2. **检查资源配置**：
```bash
kubectl describe limitrange -n tekton-pipelines
kubectl describe resourcequota -n tekton-pipelines
```

3. **验证 ServiceAccount 权限**：
```bash
kubectl get serviceaccount -n tekton-pipelines
kubectl describe clusterrolebinding | grep tekton
```

---

## 🚀 阶段二：CI/CD 自动化问题排查

### 1. API版本兼容性问题

#### 问题现象
```bash
Error from server: error when creating "STDIN": conversion webhook for tekton.dev/v1beta1, Kind=Task failed: Post "https://tekton-pipelines-webhook.tekton-pipelines.svc:443/resource-conversion?timeout=30s": dial tcp 10.102.150.150:443: connect: connection refused
```

#### 根本原因
- 使用了已废弃的 `tekton.dev/v1beta1` API版本
- 新版本 Tekton Pipeline (v1.2.0+) 已将API升级到稳定版 `tekton.dev/v1`
- Tekton Pipeline webhook 组件缺失，无法处理API版本转换

#### 解决方案

1. **更新所有资源的 API 版本**：
```yaml
# 修改前
apiVersion: tekton.dev/v1beta1
kind: Task

# 修改后  
apiVersion: tekton.dev/v1
kind: Task
```

2. **批量更新现有资源**：
```bash
# 导出现有资源
kubectl get task,pipeline -n tekton-pipelines -o yaml > backup.yaml

# 编辑 API 版本
sed -i 's/apiVersion: tekton.dev\/v1beta1/apiVersion: tekton.dev\/v1/g' backup.yaml

# 重新应用
kubectl apply -f backup.yaml
```

**影响资源类型**: Task, Pipeline, PipelineRun, TaskRun

---

### 2. RBAC权限不足问题

#### 问题现象
```bash
EventListener Pod 持续崩溃：
triggers.tekton.dev is forbidden: User "system:serviceaccount:tekton-pipelines:tekton-triggers-sa" cannot list resource "triggers" in API group "triggers.tekton.dev"
```

#### 根本原因
- ClusterRole 权限配置不完整
- 缺少对 Tekton Triggers 资源的访问权限
- ServiceAccount 绑定不正确

#### 解决方案

1. **创建完整的 ClusterRole**：
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
# EventListener 权限
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates", "triggers"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create"]

# Pipeline 执行权限  
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "taskruns"]
  verbs: ["create", "get", "list", "watch"]
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "tasks"]
  verbs: ["get", "list", "watch"]

# 基础资源权限
- apiGroups: [""]
  resources: ["serviceaccounts", "secrets", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
```

2. **验证权限配置**：
```bash
kubectl auth can-i create pipelinerun --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa
kubectl auth can-i list eventlistener --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa
```

---

### 3. Pod Security Standards限制问题

#### 问题现象
```bash
TaskRun Pod 创建失败：
pods "webhook-run-xyz-hello-pod" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false
```

#### 根本原因
- 命名空间配置了过于严格的 Pod Security Standards
- Tekton 组件需要特权权限执行某些操作
- 容器安全上下文配置不当

#### 解决方案

1. **调整命名空间 Pod Security Standards**：
```bash
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
```

2. **为特定 Task 配置安全上下文**：
```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: secure-task
spec:
  podTemplate:
    securityContext:
      runAsNonRoot: true
      runAsUser: 65532
      fsGroup: 65532
  steps:
  - name: step
    image: alpine:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL
```

---

### 4. EventListener 无法启动

#### 问题现象
```bash
kubectl get pods -l eventlistener=github-webhook-listener -n tekton-pipelines
NAME                                         READY   STATUS             RESTARTS   AGE
el-github-webhook-listener-xxx               0/1     CrashLoopBackOff   5          10m
```

#### 根本原因
- RBAC 权限配置错误
- EventListener 配置语法错误
- Interceptor 配置问题
- 网络策略阻止通信

#### 解决方案

1. **检查 EventListener 配置**：
```bash
kubectl describe eventlistener github-webhook-listener -n tekton-pipelines
kubectl get eventlistener github-webhook-listener -n tekton-pipelines -o yaml
```

2. **查看 Pod 日志**：
```bash
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines
```

3. **验证依赖资源**：
```bash
kubectl get triggerbinding,triggertemplate -n tekton-pipelines
kubectl get secret github-webhook-secret -n tekton-pipelines
```

4. **重新创建 EventListener**：
```bash
kubectl delete eventlistener github-webhook-listener -n tekton-pipelines
# 然后重新运行安装脚本中的 EventListener 部分
```

---

### 5. GitHub Webhook 连接失败

#### 问题现象
- GitHub webhook 显示红色 ❌ 状态
- webhook 历史显示连接超时或 DNS 解析失败

#### 根本原因
- webhook URL 不可从外部访问
- Ingress 路由配置错误
- 防火墙阻止 GitHub 访问
- nip.io 服务不稳定

#### 解决方案

1. **验证 webhook 端点可达性**：
```bash
# 从外部测试访问
curl -X POST http://tekton.10.117.8.154.nip.io/webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "connection"}'
```

2. **检查 Ingress 配置**：
```bash
kubectl get ingress github-webhook-ingress -n tekton-pipelines
kubectl describe ingress github-webhook-ingress -n tekton-pipelines
```

3. **验证 Service 端点**：
```bash
kubectl get svc el-github-webhook-listener -n tekton-pipelines
kubectl get endpoints el-github-webhook-listener -n tekton-pipelines
```

4. **检查防火墙和网络**：
```bash
# 确保端口 80/443 开放
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
```

5. **使用替代域名方案**：
```bash
# 如果 nip.io 不稳定，配置自定义域名或直接使用 IP
echo "10.117.8.154 tekton.local" | sudo tee -a /etc/hosts
```

---

### 6. Pipeline 自动触发失败

#### 问题现象
- GitHub push 事件发送成功，但没有创建 PipelineRun
- EventListener 日志显示事件接收但处理失败

#### 根本原因
- TriggerBinding 参数提取错误
- TriggerTemplate 模板配置错误
- Pipeline 引用不存在
- GitHub payload 格式变化

#### 解决方案

1. **检查 EventListener 日志**：
```bash
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f
```

2. **验证 TriggerBinding 参数**：
```bash
kubectl get triggerbinding github-trigger-binding -n tekton-pipelines -o yaml
```

3. **测试 TriggerTemplate**：
```bash
# 手动创建 PipelineRun 测试模板
kubectl apply -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-test-
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: github-webhook-pipeline
  params:
  - name: repo-url
    value: "https://github.com/johnnynv/tekton-poc"
  - name: revision
    value: "main"
EOF
```

4. **验证 GitHub payload 格式**：
```bash
# 在 EventListener 中添加调试日志
# 或使用 webhook 测试工具验证 payload 结构
```

---

## 🛠️ 通用调试技巧

### 快速诊断命令

```bash
# 1. 整体状态检查
kubectl get all -n tekton-pipelines
kubectl get all -n ingress-nginx

# 2. 查看事件日志
kubectl get events --sort-by=.metadata.creationTimestamp -n tekton-pipelines

# 3. 检查资源使用
kubectl top nodes
kubectl top pods -n tekton-pipelines

# 4. 网络连通性测试
kubectl run debug --image=nicolaka/netshoot --rm -it --restart=Never -- bash

# 5. 组件健康检查
curl -s http://tekton.10.117.8.154.nip.io/health || echo "Dashboard 不可访问"
curl -s http://tekton.10.117.8.154.nip.io/webhook || echo "Webhook 端点不可访问"
```

### 日志收集

```bash
# 收集所有相关日志
mkdir -p tekton-logs
kubectl logs -l app=tekton-pipelines-controller -n tekton-pipelines > tekton-logs/controller.log
kubectl logs -l app=tekton-pipelines-webhook -n tekton-pipelines > tekton-logs/webhook.log
kubectl logs -l app=tekton-dashboard -n tekton-pipelines > tekton-logs/dashboard.log
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines > tekton-logs/eventlistener.log
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx > tekton-logs/ingress.log
```

### 清理和重新部署

```bash
# 完全清理并重新部署
./02-cleanup-tekton-triggers.sh  # 清理阶段二
./01-cleanup-tekton-core.sh      # 清理阶段一

# 重新部署
./01-install-tekton-core.sh      # 安装阶段一
./verify-installation.sh --stage=core

./02-install-tekton-triggers.sh  # 安装阶段二
./verify-installation.sh --stage=triggers
```

## 📞 获得帮助

如果遇到本文档未涵盖的问题：

1. **运行验证脚本**：`./verify-installation.sh --stage=all`
2. **查看官方文档**：[Tekton Documentation](https://tekton.dev/docs/)
3. **社区支持**：[Tekton GitHub Issues](https://github.com/tektoncd/pipeline/issues)
4. **收集详细日志**：使用上述日志收集命令

---

## 🔄 文档版本

- **创建日期**：2024年
- **最后更新**：生产环境验证后
- **适用版本**：Tekton Pipelines v0.50+, Tekton Triggers v0.25+
- **环境**：Kubernetes v1.20+, 单节点集群 