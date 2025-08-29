# Tekton Triggers 安装配置指南

本指南介绍如何安装和配置 Tekton Triggers，实现事件驱动的 Pipeline 自动触发。

## 📋 配置目标

- ✅ 安装 Tekton Triggers
- ✅ 配置 RBAC 权限
- ✅ 创建 EventListener 服务
- ✅ 验证 Triggers 功能

## 🔧 前提条件

- ✅ 已完成 [Tekton 核心安装](04-tekton-installation.md)
- ✅ Tekton Pipelines 正常运行
- ✅ kubectl 访问权限

## 🚀 步骤1：安装 Tekton Triggers

### 安装 Triggers 组件
```bash
# 安装最新版本 Tekton Triggers
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# 安装 Interceptors（事件拦截器）
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# 等待所有 Pod 运行
kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
```

### 验证 Triggers 安装
```bash
# 检查 Triggers Pod 状态
kubectl get pods -n tekton-pipelines | grep triggers

# 检查 Triggers CRD
kubectl get crd | grep triggers.tekton.dev
```

预期输出：
```
tekton-triggers-controller-xxx    Running
tekton-triggers-webhook-xxx       Running
tekton-triggers-core-interceptors-xxx    Running
```

## 🔐 步骤2：配置 RBAC 权限

### 创建服务账户和权限
```bash
# 创建基础 RBAC 配置
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: tekton-pipelines
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
# Tekton Pipelines 权限
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "pipelineruns", "tasks", "taskruns"]
  verbs: ["get", "list", "create", "update", "patch", "watch"]

# Tekton Triggers 权限
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates", "triggers", "clusterinterceptors", "interceptors", "clustertriggerbindings"]
  verbs: ["get", "list", "create", "update", "patch", "watch"]

# 核心 Kubernetes 资源
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "watch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: tekton-pipelines
roleRef:
  kind: ClusterRole
  name: tekton-triggers-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tekton-triggers-namespace-role
  namespace: tekton-pipelines
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-triggers-namespace-binding
  namespace: tekton-pipelines
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: tekton-pipelines
roleRef:
  kind: Role
  name: tekton-triggers-namespace-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 📝 步骤3：创建基础 Trigger 组件

### 创建示例 TriggerTemplate
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: hello-world-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    description: Git repository URL
  - name: git-revision
    description: Git revision
    default: main
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: TaskRun
    metadata:
      generateName: hello-world-run-
    spec:
      taskSpec:
        params:
        - name: repo-url
          type: string
        - name: revision
          type: string
        steps:
        - name: hello
          image: ubuntu
          script: |
            #!/bin/bash
            echo "Triggered by event!"
            echo "Repository: \$(params.repo-url)"
            echo "Revision: \$(params.revision)"
      params:
      - name: repo-url
        value: \$(tt.params.git-repo-url)
      - name: revision
        value: \$(tt.params.git-revision)
EOF
```

### 创建 TriggerBinding
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: hello-world-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: \$(body.repository.clone_url)
  - name: git-revision
    value: \$(body.head_commit.id)
EOF
```

### 创建 EventListener
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: hello-world-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: hello-world-trigger
    bindings:
    - ref: hello-world-binding
    template:
      ref: hello-world-template
EOF
```

## 🌐 步骤4：配置 EventListener 访问

### 获取 EventListener 服务信息
```bash
# 查看 EventListener 服务
kubectl get svc -n tekton-pipelines | grep el-

# 配置为 NodePort 服务（用于外部访问）
kubectl patch svc el-hello-world-listener -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'

# 获取访问地址
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc el-hello-world-listener -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')

echo "EventListener 访问地址: http://${NODE_IP}:${NODE_PORT}"
```

## ✅ 验证 Triggers 配置

### 1. 运行验证脚本（推荐）
```bash
# 运行完整验证脚本
chmod +x scripts/utils/verify-step2-triggers-setup.sh
./scripts/utils/verify-step2-triggers-setup.sh
```

验证脚本会自动检查：
- ✅ Tekton Triggers 组件状态
- ✅ Tekton Triggers CRDs
- ✅ RBAC 权限配置
- ✅ Trigger 资源配置
- ✅ EventListener 就绪状态
- ✅ EventListener 功能测试（自动触发测试）

### 2. 手动检查组件（可选）
```bash
# 检查 EventListener 状态
kubectl get eventlistener -n tekton-pipelines

# 检查 TriggerTemplate 和 TriggerBinding
kubectl get triggertemplate,triggerbinding -n tekton-pipelines

# 检查服务和端点
kubectl get svc,endpoints -n tekton-pipelines | grep el-
```

### 3. 手动测试 EventListener（可选）
```bash
# 测试 EventListener 响应
curl -X POST http://${NODE_IP}:${NODE_PORT} \
  -H 'Content-Type: application/json' \
  -d '{
    "repository": {
      "clone_url": "https://github.com/example/test-repo.git"
    },
    "head_commit": {
      "id": "abcd1234"
    }
  }'
```

### 3. 验证触发的 TaskRun
```bash
# 查看触发的 TaskRun
kubectl get taskruns -n tekton-pipelines

# 查看最新 TaskRun 的日志
kubectl logs -l tekton.dev/task -n tekton-pipelines --tail=50
```

### 4. Dashboard 验证
在 Tekton Dashboard 中验证：
- ✅ EventListeners 页面显示监听器
- ✅ TaskRuns 页面显示触发的任务
- ✅ 可以查看实时执行日志

## 🔧 故障排除

### 常见问题

**1. EventListener Pod 无法启动**
```bash
# 检查 RBAC 权限
kubectl auth can-i create taskruns --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa -n tekton-pipelines

# 检查 Pod 日志
kubectl logs -l app.kubernetes.io/component=eventlistener -n tekton-pipelines

# 如果看到权限错误，可能需要更新ClusterRole权限
# 常见错误：cannot list resource "clusterinterceptors"/"interceptors"/"clustertriggerbindings"
kubectl patch clusterrole tekton-triggers-role --type='merge' -p='
{
  "rules": [
    {
      "apiGroups": ["tekton.dev"],
      "resources": ["pipelines", "pipelineruns", "tasks", "taskruns"],
      "verbs": ["get", "list", "create", "update", "patch", "watch"]
    },
    {
      "apiGroups": ["triggers.tekton.dev"],
      "resources": ["eventlisteners", "triggerbindings", "triggertemplates", "triggers", "clusterinterceptors", "interceptors", "clustertriggerbindings"],
      "verbs": ["get", "list", "create", "update", "patch", "watch"]
    },
    {
      "apiGroups": [""],
      "resources": ["pods", "services", "endpoints", "persistentvolumeclaims", "configmaps", "secrets"],
      "verbs": ["get", "list", "create", "update", "patch", "watch", "delete"]
    }
  ]
}'

# 重启 EventListener Pod 使新权限生效
kubectl delete pod -l eventlistener=hello-world-listener -n tekton-pipelines
```

**2. Webhook 调用失败**
```bash
# 检查服务端点
kubectl get endpoints el-hello-world-listener -n tekton-pipelines

# 检查网络连接
kubectl run test-curl --image=curlimages/curl -it --rm -- curl -v http://el-hello-world-listener.tekton-pipelines.svc.cluster.local:8080
```

**3. TriggerTemplate 参数错误**
```bash
# 检查 TriggerTemplate 语法
kubectl describe triggertemplate hello-world-template -n tekton-pipelines

# 检查参数绑定
kubectl get triggerbinding hello-world-binding -o yaml -n tekton-pipelines
```

## 📊 性能优化

### EventListener 配置优化
```bash
# 为高负载场景配置多副本
kubectl patch eventlistener hello-world-listener -n tekton-pipelines --type='merge' -p='
{
  "spec": {
    "resources": {
      "kubernetesResource": {
        "replicas": 3,
        "serviceType": "LoadBalancer"
      }
    }
  }
}'
```

## 📚 下一步

Triggers 配置完成后，您可以：
1. 配置 GitHub Webhooks（自动化 CI/CD）
2. 部署 GPU 科学计算 Pipeline

继续阅读：[06-tekton-webhook-configuration.md](06-tekton-webhook-configuration.md) 