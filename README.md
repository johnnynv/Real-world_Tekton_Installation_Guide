# Tekton Triggers GitHub Webhook 配置指南

本指南将帮助您在已有的 Kubernetes 集群上安装和配置 Tekton Triggers，实现 GitHub webhook 触发 CI/CD pipeline 的功能。

**🎯 本指南已经过实际部署验证，包含了所有常见问题的解决方案，确保一次性成功部署。**

## 📋 目录

- [前提条件](#前提条件)
- [环境信息](#环境信息)
- [快速开始](#快速开始)
- [详细配置](#详细配置)
- [GitHub Webhook 配置](#github-webhook-配置)
- [验证和测试](#验证和测试)
- [监控和日志](#监控和日志)
- [故障排除](#故障排除)
- [常见问题解决](#常见问题解决)
- [清理](#清理)

## 🔧 前提条件

确保您的环境满足以下条件：

- ✅ Kubernetes 集群 (v1.20+)
- ✅ Tekton Pipelines 已安装
- ✅ Tekton Dashboard 已安装
- ✅ Ingress Controller 已安装 (Nginx)
- ✅ kubectl 命令行工具
- ✅ 对集群的管理员权限

## 🌐 环境信息

- **Kubernetes 版本**: v1.31.6
- **Tekton Dashboard**: `http://tekton.10.117.8.154.nip.io/`
- **GitHub 仓库**: `https://github.com/johnnynv/tekton-poc`
- **Webhook Secret**: `110120119`
- **命名空间**: `tekton-pipelines`

## 🚀 快速开始

### 1. 清理现有资源（可选）

如果之前已经配置过相关资源，先运行清理脚本：

```bash
chmod +x cleanup-tekton-triggers.sh
./cleanup-tekton-triggers.sh
```

### 2. 安装和配置

运行自动安装脚本：

```bash
chmod +x install-tekton-triggers.sh
./install-tekton-triggers.sh
```

此脚本将完成：
- 安装 Tekton Triggers
- **自动检测和修复 Pod Security 配置**
- 创建完整的 RBAC 权限
- 配置 GitHub webhook secret
- 创建简化的 Task、Pipeline（使用可靠镜像）
- 配置 Service 和 Ingress
- **包含所有已知问题的自动修复**

### 3. 验证安装

运行验证脚本：

```bash
chmod +x verify-tekton-triggers.sh
./verify-tekton-triggers.sh
```

## 📖 详细配置

### 架构概述

```
GitHub Push Event → Webhook → Ingress → EventListener → TriggerBinding → TriggerTemplate → PipelineRun
```

### 核心组件

#### 1. EventListener
监听 GitHub webhook 事件的组件，配置如下：

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: github-push-trigger
    interceptors:
    - ref:
        name: "github"
      params:
      - name: "secretRef"
        value:
          secretName: github-webhook-secret
          secretKey: secretToken
      - name: "eventTypes"
        value: ["push"]
```

#### 2. TriggerBinding
从 GitHub webhook payload 中提取参数：

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
spec:
  params:
  - name: git-repo-url
    value: $(body.repository.clone_url)
  - name: git-repo-name
    value: $(body.repository.name)
  - name: git-revision
    value: $(body.head_commit.id)
```

#### 3. TriggerTemplate
定义要创建的 PipelineRun 模板：

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: git-repo-name
  resourcetemplates:
  - apiVersion: tekton.dev/v1beta1
    kind: PipelineRun
    # ... PipelineRun 定义
```

#### 4. Pipeline 和 Task
执行实际 CI/CD 逻辑的组件：

- **Task**: `simple-hello-task` - 简单的 webhook 测试任务（使用 Alpine 镜像）
- **Pipeline**: `github-webhook-pipeline` - 编排 Task 执行

> **注意**: 为确保可靠性，使用了简化的 Task 配置，避免了存储依赖和镜像拉取问题。

## 🔗 GitHub Webhook 配置

### 步骤 1: 访问 GitHub 仓库设置

1. 打开浏览器，访问：`https://github.com/johnnynv/tekton-poc/settings/hooks`
2. 点击 **"Add webhook"** 按钮

### 步骤 2: 配置 Webhook

填写以下信息：

| 字段 | 值 |
|------|------------|
| **Payload URL** | `http://tekton.10.117.8.154.nip.io/webhook` |
| **Content type** | `application/json` |
| **Secret** | `110120119` |
| **Which events would you like to trigger this webhook?** | `Just the push event` |
| **Active** | ✅ 勾选 |

### 步骤 3: 保存配置

点击 **"Add webhook"** 完成配置。

### 步骤 4: 验证配置

GitHub 会立即发送一个 ping 事件来测试 webhook。您可以在 webhook 设置页面查看发送结果。

## ✅ 验证和测试

### 自动验证

运行验证脚本：

```bash
./verify-tekton-triggers.sh
```

### 手动验证

#### 1. 检查组件状态

```bash
# 检查 Tekton Triggers 组件
kubectl get pods -n tekton-pipelines

# 检查 EventListener
kubectl get eventlistener -n tekton-pipelines

# 检查 Service 和 Ingress
kubectl get svc,ingress -n tekton-pipelines
```

#### 2. 测试 Webhook 端点

```bash
curl -X POST http://tekton.10.117.8.154.nip.io/webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

#### 3. 手动触发 Pipeline

```bash
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-test-run-
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

#### 4. 测试 GitHub Push

1. 向 `https://github.com/johnnynv/tekton-poc` 推送代码
2. 检查 PipelineRun 是否自动创建：

```bash
kubectl get pipelinerun -n tekton-pipelines
```

## 📊 监控和日志

### Dashboard 访问

访问 Tekton Dashboard: `http://tekton.10.117.8.154.nip.io/`

在 Dashboard 中可以查看：
- PipelineRuns 执行状态
- TaskRuns 详细日志
- 资源使用情况

### 命令行监控

```bash
# 查看 PipelineRuns
kubectl get pipelinerun -n tekton-pipelines

# 查看最新的 PipelineRun 详情
kubectl describe pipelinerun $(kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp -o name | tail -1) -n tekton-pipelines

# 查看 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f

# 查看特定 TaskRun 日志
kubectl logs -l tekton.dev/taskRun=<task-run-name> -n tekton-pipelines -f
```

### 实时监控命令

可以使用以下 kubectl 命令监控状态：

```bash
# 监控 PipelineRuns 和 TaskRuns
watch -n 5 'kubectl get pipelinerun,taskrun -n tekton-pipelines --sort-by=.metadata.creationTimestamp'

# 查看 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f
```

## 🔧 故障排除

### 常见问题

#### 1. EventListener Pod 未启动

**症状**: EventListener Pod 处于 Pending 状态

**解决方案**:
```bash
# 检查 Pod 状态
kubectl describe pod -l eventlistener=github-webhook-listener -n tekton-pipelines

# 检查 RBAC 权限
kubectl get serviceaccount,clusterrole,clusterrolebinding | grep tekton-triggers
```

#### 2. Webhook 端点不可访问

**症状**: GitHub webhook 发送失败

**解决方案**:
```bash
# 检查 Ingress 状态
kubectl get ingress github-webhook-ingress -n tekton-pipelines

# 检查 Service 状态
kubectl get svc github-webhook-listener-service -n tekton-pipelines

# 测试内部连接
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- curl -v http://github-webhook-listener-service.tekton-pipelines.svc.cluster.local:8080
```

#### 3. Pipeline 未触发

**症状**: Push 代码后没有创建 PipelineRun

**解决方案**:
```bash
# 检查 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines

# 检查 TriggerBinding 和 TriggerTemplate
kubectl get triggerbinding,triggertemplate -n tekton-pipelines

# 验证 GitHub webhook secret
kubectl get secret github-webhook-secret -n tekton-pipelines -o yaml
```

#### 4. Task 执行失败

**症状**: PipelineRun 创建了但 Task 执行失败

**解决方案**:
```bash
# 查看失败的 TaskRun
kubectl get taskrun -n tekton-pipelines | grep Failed

# 查看具体错误日志
kubectl logs -l tekton.dev/taskRun=<failed-task-run-name> -n tekton-pipelines

# 检查镜像和权限
kubectl describe task git-clone-and-run -n tekton-pipelines
```

### 调试命令

```bash
# 查看所有相关资源
kubectl get all,eventlistener,triggerbinding,triggertemplate -n tekton-pipelines

# 查看事件日志
kubectl get events --sort-by=.metadata.creationTimestamp -n tekton-pipelines

# 检查 Tekton Triggers 组件日志
kubectl logs -l app.kubernetes.io/part-of=tekton-triggers -n tekton-pipelines
```

## ⚠️ 常见问题解决

### 快速诊断

如果遇到问题，请运行我们提供的验证脚本：

```bash
./verify-tekton-triggers.sh
```

### 常见问题及解决方案

#### 1. EventListener Pod 崩溃 (CrashLoopBackOff)

**现象**: EventListener Pod 不断重启
```bash
kubectl get pods -l eventlistener=github-webhook-listener -n tekton-pipelines
# NAME                                READY   STATUS             RESTARTS   AGE
# el-github-webhook-listener-xxx      0/1     CrashLoopBackOff   5          10m
```

**解决方案**: 
```bash
# 自动修复 - 重新运行安装脚本
./install-tekton-triggers.sh

# 或手动修复 RBAC 权限
kubectl delete clusterrole tekton-triggers-role
# 然后重新运行安装脚本
```

#### 2. TaskRun Pod 无法创建 (PodAdmissionFailed)

**现象**: TaskRun 失败，提示 Pod Security 违规
```bash
violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false
```

**解决方案**:
```bash
# 修复 Pod Security 配置
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
```

#### 3. 镜像拉取失败

**现象**: TaskRun 失败，无法拉取 gcr.io 镜像
```bash
failed to pull and unpack image "gcr.io/tekton-releases/..."
```

**解决方案**: 安装脚本已使用 Alpine 镜像避免此问题。如需自定义，请使用可靠的公共镜像。

#### 4. 存储问题 (PVC 无法绑定)

**现象**: Pod 处于 Pending 状态，提示 PVC 无法绑定
```bash
pod has unbound immediate PersistentVolumeClaims
```

**解决方案**: 安装脚本已移除 PVC 依赖。如需存储，请配置 StorageClass 或使用 emptyDir。

### 完整问题排查指南

详细的问题分析和解决方案请参考：**[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

该文档包含：
- 5个主要问题的详细分析
- 根本原因解释
- 具体解决步骤
- 预防措施
- 快速修复脚本

## 🧹 清理

### 完全清理

如果需要完全清理所有相关资源：

```bash
./cleanup-tekton-triggers.sh
```

### 选择性清理

```bash
# 只删除 webhook 相关资源
kubectl delete eventlistener,triggerbinding,triggertemplate github-webhook-listener github-trigger-binding github-trigger-template -n tekton-pipelines

# 删除所有 PipelineRuns
kubectl delete pipelinerun --all -n tekton-pipelines

# 删除 Secret
kubectl delete secret github-webhook-secret -n tekton-pipelines
```

## 📝 文件清单

项目包含以下文件：

- `install-tekton-triggers.sh` - **优化的**自动安装和配置脚本
- `cleanup-tekton-triggers.sh` - 清理脚本
- `verify-tekton-triggers.sh` - 验证脚本
- `README.md` - 本说明文档
- `TROUBLESHOOTING.md` - **详细的问题排查指南**

## 🤝 支持

如遇到问题，请：

1. **首先运行验证脚本**: `./verify-tekton-triggers.sh`
2. **查看问题排查文档**: [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
3. **检查组件日志**: `kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f`
4. **重新运行安装脚本**: `./install-tekton-triggers.sh`（包含自动修复）

## 📄 许可证

本项目采用 MIT 许可证。

---

## ⚡ 重要提示

- **本配置已经过实际验证，解决了5个主要部署问题**
- **安装脚本包含自动修复功能，确保一次性成功**
- **使用简化配置以确保最大兼容性**
- **生产环境请根据实际需求调整安全配置和资源限制**

---

🎉 **享受您的 Tekton Triggers GitHub Webhook 体验吧！** 