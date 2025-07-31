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
- **Kubernetes 集群**: v1.24+ (支持kubeadm/minikube/云厂商)
- **kubectl**: 已配置并可访问集群
- **管理员权限**: 集群级别的 RBAC 权限

### kubeadm环境配置kubectl
如果使用kubeadm搭建的集群，需要先配置kubectl：
```bash
# 创建kubectl配置目录
mkdir -p ~/.kube

# 复制kubeadm管理员配置（需要sudo权限）
sudo cp /etc/kubernetes/admin.conf ~/.kube/config

# 修改文件所有权为当前用户
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### 检查集群状态
```bash
# 检查 Kubernetes 版本
kubectl version

# 检查集群连接状态
kubectl cluster-info

# 检查集群节点状态
kubectl get nodes

# 检查可用资源（如果metrics-server已安装）
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

### ⚠️ 重要：Kubernetes 1.24+ Pod Security Standards 配置

**Kubernetes 1.24+ 默认启用了 Pod Security Standards**，会阻止 Tekton 任务运行！

#### 问题现象
```bash
# TaskRun 会失败，显示类似错误：
# pods "task-run-xxx-pod" is forbidden: violates PodSecurity "restricted:latest"
```

#### 解决方案
```bash
# 为 tekton-pipelines 命名空间设置 privileged 安全策略
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/audit=privileged
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/warn=privileged

# 验证设置
kubectl get namespace tekton-pipelines -o yaml | grep pod-security
```

🔥 **这一步是必须的**，否则所有 Tekton 任务都会因安全策略违规而失败！

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

## 🌐 步骤3：配置 Dashboard 访问

### 安装 Nginx Ingress Controller
```bash
# 安装 nginx ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

# 等待启动完成
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# 配置使用标准端口 (80/443)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx -p '{"spec":{"template":{"spec":{"hostNetwork":true,"dnsPolicy":"ClusterFirstWithHostNet"}}}}'

# 等待重新部署完成
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s
```

### 配置域名访问
```bash
# 获取节点IP
NODE_IP=$(hostname -I | awk '{print $1}')
DOMAIN="tekton.$NODE_IP.nip.io"

# 将Dashboard服务改为ClusterIP（Ingress要求）
kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"type":"ClusterIP"}}'

# 配置基础 Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: tekton-pipelines
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: $DOMAIN
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

### 配置 HTTPS 访问（可选）
```bash
# 生成自签名证书（包含SAN以避免现代浏览器警告）
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key \
  -out /tmp/tls.crt \
  -subj "/CN=$DOMAIN/O=tekton-dashboard" \
  -addext "subjectAltName=DNS:$DOMAIN"

# 创建 TLS Secret
kubectl create secret tls tekton-dashboard-tls \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n tekton-pipelines

# 更新 Ingress 启用 HTTPS
kubectl patch ingress tekton-dashboard -n tekton-pipelines --type='merge' -p='
{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/ssl-redirect": "true",
      "nginx.ingress.kubernetes.io/force-ssl-redirect": "true"
    }
  },
  "spec": {
    "tls": [
      {
        "hosts": ["'$DOMAIN'"],
        "secretName": "tekton-dashboard-tls"
      }
    ]
  }
}'
```

### 配置 Dashboard 基本认证（生产环境推荐）
```bash
# 生成随机密码
DASHBOARD_PASSWORD=$(openssl rand -base64 12)
echo "admin:$(openssl passwd -apr1 $DASHBOARD_PASSWORD)" > /tmp/dashboard-auth

# 创建认证Secret
kubectl create secret generic tekton-dashboard-auth \
  --from-file=auth=/tmp/dashboard-auth \
  -n tekton-pipelines

# 更新Ingress启用基本认证
kubectl patch ingress tekton-dashboard -n tekton-pipelines --type='merge' -p='
{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/auth-type": "basic",
      "nginx.ingress.kubernetes.io/auth-secret": "tekton-dashboard-auth",
      "nginx.ingress.kubernetes.io/auth-realm": "Tekton Dashboard"
    }
  }
}'

# 保存认证信息
echo "Dashboard访问信息:" > dashboard-access-info.txt
echo "URL: https://tekton.$(hostname -I | awk '{print $1}').nip.io" >> dashboard-access-info.txt
echo "用户名: admin" >> dashboard-access-info.txt
echo "密码: $DASHBOARD_PASSWORD" >> dashboard-access-info.txt

echo "🔐 Dashboard认证配置完成"
echo "🔑 用户名: admin"
echo "🔑 密码: $DASHBOARD_PASSWORD"
echo "📝 认证信息已保存到: dashboard-access-info.txt"
```

⚠️ **安全提示**：
- 基本认证为生产环境提供必要的访问控制
- 密码已随机生成并保存到 `dashboard-access-info.txt`
- 请妥善保管认证信息

### 获取访问地址
```bash
# 获取节点IP和域名
NODE_IP=$(hostname -I | awk '{print $1}')
DOMAIN="tekton.$NODE_IP.nip.io"

echo "🌐 HTTP访问:  http://$DOMAIN (自动重定向到HTTPS)"
echo "🔒 HTTPS访问: https://$DOMAIN"
```

## ✅ 验证安装

### 1. 运行验证脚本
```bash
# 运行完整验证
chmod +x scripts/utils/verify-step1-installation.sh
./scripts/utils/verify-step1-installation.sh
```

### 2. 测试 TaskRun
```bash
# 创建并运行测试任务
cat <<EOF | kubectl create -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: hello-world-run-
  namespace: tekton-pipelines
spec:
  taskRef:
    name: hello-world
EOF

# 查看执行日志
kubectl logs -l tekton.dev/task=hello-world -n tekton-pipelines --tail=10
```

### 3. 访问 Dashboard
```bash
# 获取访问地址
NODE_IP=$(hostname -I | awk '{print $1}')
echo "🌐 Dashboard访问: https://tekton.$NODE_IP.nip.io"
echo "   (HTTP会自动重定向到HTTPS)"
```

打开浏览器访问 **https://tekton.10.34.2.129.nip.io**，应该能看到：
- ✅ Tekton Dashboard 界面
- ✅ Tasks 和 TaskRuns 列表  
- ✅ 实时日志查看功能
- ✅ 使用标准443端口，无需指定端口号

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

# 检查Ingress配置
kubectl get ingress tekton-dashboard -n tekton-pipelines

# 检查SSL证书
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=10
```

⚠️ **常见访问问题**：
- **SSL证书问题**：请参考 [故障排除文档 - SSL证书SAN警告](troubleshooting.md#问题dashboard-https访问失败---ssl证书san警告)
- **完全无法访问**：请参考 [故障排除文档 - Ingress Controller配置冲突](troubleshooting.md#问题dashboard完全无法访问---ingress-controller配置冲突)

## 📚 下一步

安装完成后，您可以：
1. 配置 Tekton Triggers（自动化触发）
2. 设置 GitHub Webhooks（CI/CD 集成）  
3. 部署 GPU Pipeline（科学计算工作流）

继续阅读：[02-tekton-triggers-setup.md](02-tekton-triggers-setup.md) 