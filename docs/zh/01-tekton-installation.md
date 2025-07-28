# Tekton 核心组件安装指南

本指南详细介绍如何在 Kubernetes 集群上安装 Tekton 核心组件。

## 📋 安装目标

- ✅ 安装 Tekton Pipelines（核心引擎）
- ✅ 安装 Tekton Dashboard（Web UI）
- ✅ 配置 Ingress 访问（可选）
- ✅ 验证安装完整性

## 🔧 前提条件

### 系统要求
- **Kubernetes 集群**: v1.24+ 
- **kubectl**: 已配置并可访问集群
- **管理员权限**: 集群级别的 RBAC 权限

### 检查集群状态
```bash
# 检查 Kubernetes 版本
kubectl version --short

# 检查集群节点状态
kubectl get nodes

# 检查可用资源
kubectl top nodes
```

## 🚀 步骤1：安装 Tekton Pipelines

### 安装核心组件
```bash
# 安装最新稳定版 Tekton Pipelines
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# 等待所有 Pod 运行
kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
```

### 验证 Pipelines 安装
```bash
# 检查命名空间
kubectl get namespace tekton-pipelines

# 检查 Pod 状态
kubectl get pods -n tekton-pipelines

# 检查 CRD 是否创建
kubectl get crd | grep tekton
```

预期输出：
```
tekton-pipelines-controller-xxx    Running
tekton-pipelines-webhook-xxx       Running
```

## 🎨 步骤2：安装 Tekton Dashboard

### 安装 Dashboard
```bash
# 安装最新版本 Dashboard
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# 等待 Dashboard Pod 运行
kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
```

### 验证 Dashboard 安装
```bash
# 检查 Dashboard Pod
kubectl get pods -n tekton-pipelines | grep dashboard

# 检查 Dashboard Service
kubectl get svc -n tekton-pipelines | grep dashboard
```

## 🌐 步骤3：配置访问方式

### 方式1：端口转发（开发环境）
```bash
# 启动端口转发
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097

# 在浏览器访问
# http://localhost:9097
```

### 方式2：NodePort 服务（推荐）
```bash
# 创建 NodePort 服务
kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'

# 获取访问端口
kubectl get svc tekton-dashboard -n tekton-pipelines
```

访问 Dashboard：
```bash
# 获取节点 IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 获取端口
NODE_PORT=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')

echo "Dashboard 访问地址: http://${NODE_IP}:${NODE_PORT}"
```

## ✅ 验证完整安装

### 1. 检查所有组件状态
```bash
# 运行验证脚本
./scripts/zh/utils/verify-installation.sh
```

### 2. 创建测试 Task
```bash
# 创建测试任务
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: tekton-pipelines
spec:
  steps:
  - name: hello
    image: ubuntu
    script: |
      #!/bin/bash
      echo "Hello from Tekton!"
      echo "Installation successful!"
EOF
```

### 3. 运行测试 TaskRun
```bash
# 创建 TaskRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: hello-world-run-
  namespace: tekton-pipelines
spec:
  taskRef:
    name: hello-world
EOF

# 查看运行状态
kubectl get taskruns -n tekton-pipelines

# 查看日志
kubectl logs -l tekton.dev/task=hello-world -n tekton-pipelines
```

### 4. Dashboard 验证
在 Dashboard 中您应该能看到：
- ✅ Tasks 列表
- ✅ TaskRuns 执行历史
- ✅ 实时日志查看

## 🔧 故障排除

### 常见问题

**1. Pod 无法启动**
```bash
# 检查 Pod 事件
kubectl describe pod <pod-name> -n tekton-pipelines

# 检查日志
kubectl logs <pod-name> -n tekton-pipelines
```

**2. CRD 安装失败**
```bash
# 手动安装 CRD
kubectl apply -f https://raw.githubusercontent.com/tektoncd/pipeline/main/config/500-controller.yaml
```

**3. Dashboard 无法访问**
```bash
# 检查服务状态
kubectl get svc -n tekton-pipelines
kubectl get endpoints -n tekton-pipelines
```

## 📚 下一步

安装完成后，您可以：
1. 配置 Tekton Triggers（自动化触发）
2. 设置 GitHub Webhooks（CI/CD 集成）  
3. 部署 GPU Pipeline（科学计算工作流）

继续阅读：[02-tekton-triggers-setup.md](02-tekton-triggers-setup.md) 