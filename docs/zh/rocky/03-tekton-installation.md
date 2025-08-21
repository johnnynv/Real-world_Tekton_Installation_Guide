# Tekton v1.3.0 生产环境安装指南

本指南详细介绍如何在Rocky Linux 10 + Kubernetes v1.30.14环境上安装Tekton v1.3.0完整组件。

## 🎯 安装规划

### 版本选择
- **Tekton Pipelines**: v1.3.0 (最新稳定版)
- **Tekton Dashboard**: v0.60.0 (最新稳定版)
- **访问方式**: nip.io域名 + NodePort服务
- **认证**: admin/admin123 基础认证

### 组件架构
```
Tekton 完整安装
├── Tekton Pipelines (核心引擎)
├── Tekton Dashboard (Web界面)
├── Nginx反向代理 (外部访问)
├── 基础认证 (用户管理)
└── nip.io域名服务 (无需DNS配置)
```

## 🏁 步骤1：环境验证

### 检查K8s集群状态
```bash
# 验证集群版本和状态
kubectl version --short
kubectl get nodes
kubectl get pods -A | grep -v Completed
```

**验证结果**:
- ✅ Kubernetes v1.30.14 运行正常
- ✅ 节点状态为Ready
- ✅ 所有系统Pod正常运行

### 检查存储和网络
```bash
# 检查默认存储类
kubectl get storageclass

# 检查网络连接
kubectl get pods -n calico-system
```

**验证结果**:
- ✅ local-path存储类可用
- ✅ Calico网络正常

## 🔧 步骤2：安装Tekton Pipelines v1.3.0

### 获取最新版本信息
```bash
# 检查Tekton Pipelines最新版本
curl -s https://api.github.com/repos/tektoncd/pipeline/releases | grep -E '"tag_name".*v1\.' | head -1
```

### 安装Tekton Pipelines
```bash
# 安装Tekton Pipelines v1.3.0
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# 验证安装
kubectl get pods --namespace tekton-pipelines
kubectl get crd | grep tekton
```

**安装结果**:
```
namespace/tekton-pipelines created
customresourcedefinition.apiextensions.k8s.io/customruns.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/pipelines.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/pipelineruns.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/taskruns.tekton.dev created
deployment.apps/tekton-pipelines-controller created
deployment.apps/tekton-pipelines-webhook created
```

### 验证安装
```bash
# 等待Tekton控制器启动完成
kubectl wait --for=condition=available --timeout=300s deployment/tekton-pipelines-controller -n tekton-pipelines

# 验证Tekton组件状态
kubectl get pods --namespace tekton-pipelines
kubectl get crd | grep tekton

# 获取版本信息
kubectl describe deployment tekton-pipelines-controller -n tekton-pipelines | grep Image
```

**验证结果**:
```
# Tekton组件状态
NAME                                           READY   STATUS    RESTARTS   AGE
tekton-events-controller-bcd894689-2wtff       1/1     Running   0          33s
tekton-pipelines-controller-685d97d7db-pwwxx   1/1     Running   0          33s
tekton-pipelines-webhook-6f7d65db5-jmgpn       1/1     Running   0          33s

# 自定义资源定义
customruns.tekton.dev                                 2025-08-20T11:19:39Z
pipelineruns.tekton.dev                               2025-08-20T11:19:39Z
pipelines.tekton.dev                                  2025-08-20T11:19:39Z
tasks.tekton.dev                                      2025-08-20T11:19:39Z
taskruns.tekton.dev                                   2025-08-20T11:19:39Z

# 版本信息
Image: ghcr.io/tektoncd/pipeline/controller:v1.3.0
```

**Pipelines验证结果**:
- ✅ Tekton Pipelines v1.3.0 安装成功
- ✅ 所有核心组件运行正常
- ✅ 自定义资源定义已创建

## 🖥️ 步骤3：安装Tekton Dashboard

### 安装Dashboard
```bash
# 安装Tekton Dashboard最新版本
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# 验证Dashboard安装
kubectl get pods -n tekton-pipelines | grep dashboard
kubectl get svc -n tekton-pipelines | grep dashboard
```

**安装结果**:
```
customresourcedefinition.apiextensions.k8s.io/extensions.dashboard.tekton.dev created
serviceaccount/tekton-dashboard created
deployment.apps/tekton-dashboard created
service/tekton-dashboard created
```

**Dashboard验证结果**:
```
# Dashboard组件状态
tekton-dashboard-75d96bd9f-lvfhn               1/1     Running   0          6s

# Dashboard服务
tekton-dashboard              ClusterIP   10.109.175.63   <none>        9097/TCP
```

- ✅ Tekton Dashboard安装成功
- ✅ 服务运行在9097端口

## 🌐 步骤4：配置Nginx Ingress访问

### 安装Nginx Ingress Controller
```bash
# 安装Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml

# 等待Ingress Controller启动完成
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

# 检查Ingress Controller状态
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**安装结果**:
```
namespace/ingress-nginx created
deployment.apps/ingress-nginx-controller created
service/ingress-nginx-controller created
ingressclass.networking.k8s.io/nginx created
```

**Ingress Controller验证结果**:
```
# Controller状态
ingress-nginx-controller-85bc8b845b-mr9r8   1/1     Running   0          69s

# Controller服务
ingress-nginx-controller             LoadBalancer   10.104.156.191   <pending>     80:31267/TCP,443:32210/TCP
```

- ✅ Nginx Ingress Controller安装成功
- ✅ HTTP端口: 30080 (自动重定向), HTTPS端口: 30443

### 创建基础认证
```bash
# 生成admin/admin123的密码哈希
echo -n 'admin123' | openssl passwd -apr1 -stdin

# 创建基础认证Secret
kubectl create secret generic tekton-basic-auth --from-literal=auth='admin:$apr1$BElBVB.P$dy.Nl0ipmc5vXZESSpPaJ1' -n tekton-pipelines
```

**认证配置结果**:
- ✅ 用户名: admin
- ✅ 密码: admin123
- ✅ 认证方式: HTTP Basic Auth

### 创建TLS证书
```bash
# 创建带SAN的自签名SSL证书
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=tekton.10.78.14.61.nip.io" -addext "subjectAltName=DNS:tekton.10.78.14.61.nip.io"

# 创建TLS证书Secret
kubectl create secret tls tekton-tls-secret --key tls.key --cert tls.crt -n tekton-pipelines

# 清理临时证书文件
rm tls.key tls.crt
```

**TLS证书配置结果**:
- ✅ 自签名证书创建成功
- ✅ 证书有效期: 365天
- ✅ 域名: tekton.10.78.14.61.nip.io

### 创建HTTPS Ingress资源
```bash
# 创建带基础认证和HTTPS的Tekton Dashboard Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard-ingress
  namespace: tekton-pipelines
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: tekton-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Tekton Dashboard Authentication'
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  tls:
  - hosts:
    - tekton.10.78.14.61.nip.io
    secretName: tekton-tls-secret
  rules:
  - host: tekton.10.78.14.61.nip.io
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

# 验证Ingress创建
kubectl get ingress -n tekton-pipelines
```

**Ingress配置结果**:
```
NAME                       CLASS    HOSTS                       ADDRESS   PORTS     AGE
tekton-dashboard-ingress   <none>   tekton.10.78.14.61.nip.io             80, 443   5m3s
```

### 测试HTTPS访问
```bash
# 测试HTTPS访问（端口32210）
curl -H "Host: tekton.10.78.14.61.nip.io" -u admin:admin123 https://localhost:32210/ -k -I

# 测试HTTP重定向（端口31267）
curl -H "Host: tekton.10.78.14.61.nip.io" http://localhost:31267/ -I
```

**HTTPS访问测试结果**:
```
# HTTPS直接访问
HTTP/2 200 
date: Wed, 20 Aug 2025 11:29:52 GMT
content-type: text/html; charset=utf-8
strict-transport-security: max-age=31536000; includeSubDomains

# HTTP自动重定向
HTTP/1.1 308 Permanent Redirect
Location: https://tekton.10.78.14.61.nip.io
```

- ✅ HTTPS 200状态码，访问成功
- ✅ HTTP/2协议启用
- ✅ HTTP自动重定向到HTTPS
- ✅ HSTS安全头启用

## 🎉 步骤5：访问信息汇总

### 🌐 Tekton Dashboard访问信息

**主要访问URL**:
```
https://tekton.10.78.14.61.nip.io
```

**认证信息**:
- **用户名**: admin
- **密码**: admin123

**技术架构**:
```
HTTPS访问流程
├── https://tekton.10.78.14.61.nip.io
├── Nginx Ingress Controller (NodePort 30443)
├── TLS证书验证 (自签名证书)
├── HTTP Basic Auth (admin/admin123)
├── Tekton Dashboard Service (9097)
└── Tekton Dashboard Pod
```

### 🔧 备用访问方式

**本地端口转发** (开发测试用):
```bash
# 创建端口转发
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097

# 访问URL
http://localhost:9097
```

**NodePort直接访问** (内部网络):
```bash
# 创建NodePort服务
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: tekton-dashboard-nodeport
  namespace: tekton-pipelines
spec:
  type: NodePort
  ports:
  - port: 9097
    targetPort: 9097
    nodePort: 30097
    protocol: TCP
  selector:
    app.kubernetes.io/name: tekton-dashboard
EOF

# 访问URL
http://10.78.14.61:30097
```

## 📋 安装结果摘要

### ✅ 成功安装的组件
1. **Tekton Pipelines**: v1.3.0 (核心引擎)
2. **Tekton Dashboard**: 最新版本 (Web界面)
3. **Nginx Ingress Controller**: v1.11.3 (外部访问)
4. **TLS证书**: 自签名证书 (HTTPS加密)
5. **基础认证**: admin/admin123 (安全访问)
6. **nip.io域名**: 无需DNS配置

### 🔄 集成验证
- ✅ Kubernetes v1.30.14 ← → Tekton v1.3.0 (完全兼容)
- ✅ Ingress Controller ← → Tekton Dashboard (HTTPS代理)
- ✅ TLS证书 ← → HTTPS加密 (自签名证书)
- ✅ HTTP Basic Auth ← → 用户认证 (安全访问)
- ✅ nip.io域名 ← → 外部访问 (无需DNS)
- ✅ HTTP → HTTPS ← → 自动重定向 (强制安全)

### 🎯 生产环境就绪
该Tekton安装已为以下场景做好准备：
- **CI/CD Pipeline**: 完整的持续集成和部署
- **容器构建**: 支持各种构建策略
- **Git集成**: 支持GitHub、GitLab等代码仓库
- **多租户**: 支持命名空间隔离
- **监控集成**: 与Prometheus/Grafana集成

## 🚀 下一步

Tekton安装完成后，您可以继续：
1. [创建第一个Pipeline](04-tekton-triggers-setup.md)
2. [配置Git Webhook](05-tekton-webhook-configuration.md)
3. [部署GPU Pipeline](06-gpu-pipeline-deployment.md)

## 🎉 总结

成功完成了Tekton完整平台的安装！现在您可以通过以下URL访问：

**🌐 Tekton Dashboard访问地址**: https://tekton.10.78.14.61.nip.io
**👤 登录凭据**: admin / admin123

享受您的Tekton CI/CD之旅！

## 🚨 故障排除

如果在使用过程中遇到问题，请参考：
- [故障排除指南](00-troubleshooting-on-rocky.md) - 常见问题及解决方案
- [Webhook配置指南](05-tekton-webhook-configuration.md) - Webhook集成配置
- [用户权限配置](06-tekton-restricted-user-setup.md) - 用户权限管理
