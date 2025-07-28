# Tekton 核心组件安装指南

本指南详细介绍如何在 Kubernetes 集群上安装 Tekton 核心组件。

## ⚠️ 重要：环境清理

**如果您的环境中已经安装了 Tekton 组件，请先执行完整清理！**

### 检查现有安装
```bash
# 检查是否存在 Tekton 命名空间
kubectl get namespaces | grep tekton

# 检查现有 Tekton 组件
kubectl get pods --all-namespaces | grep tekton
```

### 完整环境清理
如果发现已有 Tekton 组件，请执行完整清理：

```bash
# 赋予清理脚本执行权限
chmod +x scripts/cleanup/clean-tekton-environment.sh

# 执行完整清理（需要确认）
./scripts/cleanup/clean-tekton-environment.sh
```

⚠️ **清理确认**：
- 脚本会要求输入 `yes` 确认清理
- 清理操作不可逆，请谨慎操作
- 清理完成后环境将完全干净

## 📋 安装目标

- ✅ 完整清理现有环境（如需要）
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
kubectl version

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

## 🌐 步骤3：配置生产级访问（HTTPS + 认证）

### 生产级安全配置
```bash
# 安装必要工具
sudo apt-get update && sudo apt-get install -y apache2-utils openssl

# 赋予配置脚本执行权限
chmod +x scripts/install/02-configure-tekton-dashboard.sh

# 执行生产级配置（自动生成证书和密码）
./scripts/install/02-configure-tekton-dashboard.sh
```

### 自定义配置参数
```bash
# 使用自定义域名和密码
./scripts/install/02-configure-tekton-dashboard.sh \
  --host tekton.YOUR_IP.nip.io \
  --admin-user admin \
  --admin-password your-secure-password \
  --ingress-class nginx
```

### 配置域名访问
使用 nip.io 免费域名服务，无需配置 DNS 或 hosts 文件：
```bash
# 使用实际的外部IP地址配置域名
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Dashboard URL: https://tekton.${EXTERNAL_IP}.nip.io"
```

### 直接访问
```bash
# 示例：使用当前配置的域名
# https://tekton.10.117.8.154.nip.io
# 用户名: admin
# 密码: (脚本生成的密码)
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