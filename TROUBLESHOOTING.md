# Tekton Triggers GitHub Webhook 问题排查指南

本文档总结了在配置 Tekton Triggers GitHub Webhook 过程中遇到的常见问题、根本原因和解决方案。

## 📋 问题总览

在实际部署过程中，我们遇到了以下5个主要问题：

1. **API版本兼容性问题**
2. **RBAC权限不足问题**
3. **Pod Security Standards限制问题**
4. **存储配置问题**
5. **容器镜像拉取问题**

---

## 🔍 问题详细分析

### 1. API版本兼容性问题

#### 问题现象
```bash
Error from server: error when creating "STDIN": conversion webhook for tekton.dev/v1beta1, Kind=Task failed: Post "https://tekton-pipelines-webhook.tekton-pipelines.svc:443/resource-conversion?timeout=30s": dial tcp 10.102.150.150:443: connect: connection refused
```

#### 根本原因
- 使用了已废弃的 `tekton.dev/v1beta1` API版本
- 新版本 Tekton Pipeline (v1.2.0) 已将API升级到稳定版 `tekton.dev/v1`
- Tekton Pipeline webhook 组件缺失，无法处理API版本转换

#### 解决方案
将所有 Tekton Pipeline 资源的 API 版本从 `v1beta1` 更新为 `v1`：

```yaml
# 修改前
apiVersion: tekton.dev/v1beta1
kind: Task

# 修改后  
apiVersion: tekton.dev/v1
kind: Task
```

**影响资源类型**: Task, Pipeline, PipelineRun

---

### 2. RBAC权限不足问题

#### 问题现象
EventListener Pod 持续崩溃并出现以下错误：
```bash
triggers.tekton.dev is forbidden: User "system:serviceaccount:tekton-pipelines:tekton-triggers-sa" cannot list resource "triggers" in API group "triggers.tekton.dev"
```

#### 根本原因
- 初始 ClusterRole 权限配置不完整
- 缺少对 Tekton Triggers 资源的 `watch` 权限
- 缺少对额外资源类型的访问权限（如 `triggers`, `interceptors`, `clusterinterceptors`）

#### 解决方案
创建完整的 ClusterRole 权限配置：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
# Core resources
- apiGroups: [""]
  resources: ["configmaps", "secrets", "serviceaccounts", "events", "pods", "services"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
# Tekton Pipeline resources
- apiGroups: ["tekton.dev"]
  resources: ["tasks", "clustertasks", "pipelines", "pipelineruns", "taskruns", "runs", "customruns"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
# Tekton Triggers resources
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates", "clustertriggerbindings", "triggers", "interceptors", "clusterinterceptors"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
# For creating pods and other resources
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
```

**关键改进**:
- 添加 `watch` 权限
- 包含所有 Triggers 资源类型
- 添加 `patch` 权限

---

### 3. Pod Security Standards限制问题

#### 问题现象
TaskRun Pod 创建失败：
```bash
pods "manual-test-run-9mrf8-git-clone-and-run-pod" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false
```

#### 根本原因
- `tekton-pipelines` namespace 配置了 `pod-security.kubernetes.io/enforce=restricted`
- Tekton 的 Pod 需要特殊的安全上下文权限才能正常运行
- `restricted` 模式不允许 privilege escalation 和某些 capabilities

#### 解决方案
将 namespace 的 Pod Security 策略从 `restricted` 更改为 `privileged`：

```bash
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
```

**自动检测和修复**:
```bash
fix_pod_security() {
    local current_enforce=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
    
    if [ "$current_enforce" = "restricted" ]; then
        kubectl label namespace $NAMESPACE pod-security.kubernetes.io/enforce=privileged --overwrite
    fi
}
```

---

### 4. 存储配置问题

#### 问题现象
Pod 无法调度：
```bash
0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims
```

#### 根本原因
- 集群没有配置 StorageClass
- Pipeline 使用了 `volumeClaimTemplate` 但无法创建 PVC
- 单节点测试环境通常没有动态存储供应

#### 解决方案
移除工作空间配置或使用 `emptyDir`：

```yaml
# 修改前 - 使用 PVC
workspaces:
- name: shared-data
  volumeClaimTemplate:
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi

# 修改后 - 使用 emptyDir  
workspaces:
- name: shared-data
  emptyDir: {}

# 或者 - 完全移除工作空间（推荐用于简单测试）
# 不定义 workspaces 部分
```

---

### 5. 容器镜像拉取问题

#### 问题现象
```bash
failed to pull and unpack image "gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:v0.40.2": failed to authorize: failed to fetch anonymous token: 403 Forbidden
```

#### 根本原因
- GCR (Google Container Registry) 访问限制
- 网络环境无法访问 `gcr.io`
- 某些企业环境阻止访问外部镜像仓库

#### 解决方案
使用更可靠的公共镜像：

```yaml
# 修改前 - 使用 gcr.io 镜像
steps:
- name: clone
  image: gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:v0.40.2

# 修改后 - 使用 Alpine 等可靠镜像
steps:
- name: hello
  image: alpine:latest
  script: |
    echo "=== Tekton Triggers GitHub Webhook 测试成功! ==="
    echo "Repository: $(params.repo-url)"
    echo "GitHub webhook 正常工作!"
```

---

## 🛠️ 最佳实践和预防措施

### 1. 环境检查清单

部署前请确认以下环境配置：

```bash
# 检查 Kubernetes 版本
kubectl version

# 检查 Pod Security 配置
kubectl get namespace tekton-pipelines -o yaml | grep pod-security

# 检查存储类
kubectl get storageclass

# 检查网络连通性
curl -I https://gcr.io

# 检查 Tekton Pipeline 版本
kubectl get pods -n tekton-pipelines -l app.kubernetes.io/part-of=tekton-pipelines
```

### 2. 增量部署策略

1. **先部署基础组件**
   - 安装 Tekton Triggers
   - 配置 RBAC
   - 修复 Pod Security

2. **创建简单测试**
   - 使用 alpine 镜像的简单 Task
   - 不依赖外部存储
   - 验证基本功能

3. **逐步增加复杂性**
   - 添加 git clone 功能
   - 集成实际业务逻辑
   - 配置持久化存储

### 3. 监控和调试

```bash
# 实时监控 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f

# 检查 RBAC 权限
kubectl auth can-i --list --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa

# 测试 webhook 端点
curl -X POST http://tekton.10.117.8.154.nip.io/webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

---

## 🔧 快速修复脚本

如果遇到问题，可以运行以下快速修复命令：

```bash
#!/bin/bash
# 快速修复常见问题

# 1. 修复 Pod Security
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite

# 2. 重启 EventListener
kubectl delete pod -l eventlistener=github-webhook-listener -n tekton-pipelines

# 3. 检查和修复 RBAC
kubectl delete clusterrole tekton-triggers-role
# 然后重新创建完整的 ClusterRole（参见上文）

# 4. 清理失败的 PipelineRuns
kubectl delete pipelinerun --all -n tekton-pipelines
```

---

## 📞 故障排查流程

遇到问题时，请按以下顺序排查：

1. **检查 EventListener Pod 状态**
   ```bash
   kubectl get pods -l eventlistener=github-webhook-listener -n tekton-pipelines
   ```

2. **查看 Pod 详细错误**
   ```bash
   kubectl describe pod -l eventlistener=github-webhook-listener -n tekton-pipelines
   ```

3. **检查 RBAC 权限**
   ```bash
   kubectl get clusterrole tekton-triggers-role -o yaml
   ```

4. **验证 Pod Security 设置**
   ```bash
   kubectl get namespace tekton-pipelines -o yaml | grep pod-security
   ```

5. **测试镜像拉取**
   ```bash
   kubectl run test-pod --image=alpine:latest --rm -it -- echo "Image pull test"
   ```

6. **检查存储配置**
   ```bash
   kubectl get storageclass
   kubectl get pvc -n tekton-pipelines
   ```

---

## 🎯 总结

通过解决上述5个核心问题，Tekton Triggers GitHub Webhook 可以在大多数 Kubernetes 环境中成功部署。关键是：

1. **使用正确的API版本** (`v1` 而不是 `v1beta1`)
2. **配置完整的RBAC权限** (包括 `watch` 和 `patch`)
3. **适当的Pod Security设置** (`privileged` 而不是 `restricted`)
4. **简化存储需求** (使用 `emptyDir` 或移除工作空间)
5. **使用可靠的镜像** (避免 gcr.io 访问问题)

遵循这些最佳实践，可以确保一次性成功部署，避免常见的配置陷阱。 