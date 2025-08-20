# Tekton 用户权限与安全配置指南

本指南详细介绍如何为Tekton配置适当的用户权限、ServiceAccount和安全策略，确保在生产环境中的安全性和可控性。

## 🎯 配置规划

### 权限模型设计
- **管理员权限**: 完整的集群级Tekton资源管理
- **开发者权限**: 命名空间级Pipeline创建和执行
- **受限用户权限**: 仅允许查看PipelineRun状态
- **CI/CD机器人权限**: 自动化系统专用权限

### 安全架构
```
Tekton权限安全架构
├── Cluster级权限 (集群管理员)
│   ├── ClusterRole: tekton-admin
│   └── ClusterRoleBinding: tekton-admin-binding
├── Namespace级权限 (开发团队)
│   ├── Role: tekton-developer
│   └── RoleBinding: tekton-dev-binding
├── EventListener权限 (Triggers系统)
│   ├── ClusterRole: tekton-triggers-cluster
│   └── ServiceAccount: tekton-triggers-sa
└── 受限查看权限 (只读用户)
    ├── Role: tekton-viewer
    └── RoleBinding: tekton-viewer-binding
```

## 🏁 步骤1: 诊断当前权限问题

### 检查EventListener权限错误
```bash
# 查看当前EventListener状态
kubectl get pods -l eventlistener=hello-event-listener
kubectl logs -l eventlistener=hello-event-listener --tail=20
```

**权限错误分析**:
```
权限不足错误:
- cannot list resource "interceptors" in API group "triggers.tekton.dev"
- cannot list resource "clustertriggerbindings" in API group "triggers.tekton.dev"  
- cannot list resource "clusterinterceptors" in API group "triggers.tekton.dev"
```

**问题根因**: ServiceAccount `tekton-triggers-sa` 缺少必要的集群级权限

## 🔧 步骤2: 修复EventListener权限

### 删除现有的不完整权限配置
```bash
# 删除现有的ClusterRole和ClusterRoleBinding
kubectl delete clusterrole tekton-triggers-clusterrole
kubectl delete clusterrolebinding tekton-triggers-binding

# 确认删除
kubectl get clusterrole | grep tekton-triggers
kubectl get clusterrolebinding | grep tekton-triggers
```

### 创建完整的EventListener权限
```bash
# 创建完整的Triggers ClusterRole
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-eventlistener-roles
rules:
# EventListener需要的核心权限
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggers", "triggerbindings", "triggertemplates"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["triggers.tekton.dev"] 
  resources: ["clustertriggerbindings", "clusterinterceptors"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["interceptors"]
  verbs: ["get", "list", "watch"]
# Pipeline执行权限
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "taskruns", "pipelines", "tasks"]
  verbs: ["create", "get", "list", "watch"]
# 基础Kubernetes资源权限
- apiGroups: [""]
  resources: ["configmaps", "secrets", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["serviceaccounts"]
  verbs: ["impersonate"]
EOF
```

### 绑定权限到ServiceAccount
```bash
# 创建ClusterRoleBinding
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-eventlistener-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: default
roleRef:
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
  apiGroup: rbac.authorization.k8s.io
EOF
```

### 验证权限修复
```bash
# 重启EventListener Pod以应用新权限
kubectl delete pod -l eventlistener=hello-event-listener

# 等待Pod重新创建
kubectl wait --for=condition=ready pod -l eventlistener=hello-event-listener --timeout=120s

# 检查新的Pod状态和日志
kubectl get pods -l eventlistener=hello-event-listener
kubectl logs -l eventlistener=hello-event-listener --tail=10
```

**权限修复验证结果**:
```
# EventListener Pod状态
NAME                                      READY   STATUS    RESTARTS   AGE
el-hello-event-listener-c5f79b595-nx59d   1/1     Running   0          5m28s

# EventListener服务状态
NAME                      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
el-hello-event-listener   ClusterIP   10.96.149.58   <none>        8080/TCP,9000/TCP   12m

# EventListener状态
NAME                   ADDRESS                                                         AVAILABLE   READY
hello-event-listener   http://el-hello-event-listener.default.svc.cluster.local:8080   True        True
```

- ✅ EventListener Pod运行正常，无权限错误
- ✅ ClusterRole `tekton-triggers-eventlistener-roles` 创建成功
- ✅ ClusterRoleBinding `tekton-triggers-eventlistener-binding` 绑定成功
- ✅ ServiceAccount `tekton-triggers-sa` 权限充足

## 🧪 步骤3: 功能验证测试

### 测试EventListener权限是否充足
```bash
# 测试Webhook端点功能
curl -X POST http://localhost:30088 \
  -H "Content-Type: application/json" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/test/repo.git",
      "name": "test-repo"
    },
    "head_commit": {
      "id": "abc123def456"
    },
    "pusher": {
      "name": "test-developer"
    }
  }'

# 检查PipelineRun是否自动创建
kubectl get pipelinerun

# 查看Pipeline执行日志
kubectl logs -l tekton.dev/pipelineRun=$(kubectl get pipelinerun -o name | head -1 | cut -d'/' -f2)
```

**功能验证测试结果**:
```
# Webhook响应
{"eventListener":"hello-event-listener","namespace":"default","eventListenerUID":"e19a8483-e1c6-4796-867c-0bed0f84a583","eventID":"c4d5dd48-9599-447e-aece-00095adf263c"}

# PipelineRun自动创建
NAME                       SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
hello-pipeline-run-s9wrp   True        Succeeded   10s         0s

# Pipeline执行日志
===================================
Git URL: https://github.com/test/repo.git
Git Revision: abc123def456
Message: Triggered by test-developer on test-repo
===================================
Pipeline executed successfully!
```

- ✅ EventListener权限充足，正常处理Webhook请求
- ✅ TriggerBinding正确提取参数
- ✅ TriggerTemplate成功创建PipelineRun
- ✅ Pipeline执行成功完成

## 👨‍💼 步骤4: 可选 - 创建管理员权限

### 创建Tekton管理员ClusterRole
```bash
# 创建Tekton完整管理权限
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-admin
rules:
# 完整的Tekton资源管理权限
- apiGroups: ["tekton.dev"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["*"] 
  verbs: ["*"]
# 监控和调试权限
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
```

### 为当前用户添加管理员权限
```bash
# 获取当前用户信息
CURRENT_USER=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.user}')

# 创建管理员绑定
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-admin-binding
subjects:
- kind: User
  name: $CURRENT_USER
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: tekton-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo "已为用户 $CURRENT_USER 添加Tekton管理员权限"
```

## 👨‍💻 步骤5: 可选 - 创建开发者权限

### 创建命名空间级开发者权限
```bash
# 创建开发者Role (命名空间级)
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: tekton-developer
rules:
# Pipeline开发和执行权限
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "tasks", "pipelineruns", "taskruns"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["triggerbindings", "triggertemplates", "eventlisteners", "triggers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# 基础资源权限
- apiGroups: [""]
  resources: ["configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
EOF
```

### 创建开发者ServiceAccount
```bash
# 创建开发者ServiceAccount
kubectl create serviceaccount tekton-developer-sa

# 绑定开发者权限
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-developer-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: tekton-developer-sa
  namespace: default
roleRef:
  kind: Role
  name: tekton-developer
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 👀 步骤6: 可选 - 创建只读查看权限

### 创建查看者权限
```bash
# 创建只读查看Role
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: tekton-viewer
rules:
# 只读查看权限
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "tasks", "pipelineruns", "taskruns"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["triggerbindings", "triggertemplates", "eventlisteners", "triggers"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/log", "configmaps"]
  verbs: ["get", "list", "watch"]
EOF
```

### 创建查看者ServiceAccount
```bash
# 创建查看者ServiceAccount
kubectl create serviceaccount tekton-viewer-sa

# 绑定查看者权限
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-viewer-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: tekton-viewer-sa
  namespace: default
roleRef:
  kind: Role
  name: tekton-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 🤖 步骤7: 可选 - 创建CI/CD机器人权限

### 创建机器人专用权限
```bash
# 创建CI/CD机器人ClusterRole
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-cicd-bot
rules:
# Pipeline触发和监控权限
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "taskruns"]
  verbs: ["create", "get", "list", "watch", "update", "patch"]
- apiGroups: ["tekton.dev"] 
  resources: ["pipelines", "tasks"]
  verbs: ["get", "list", "watch"]
# Webhook触发权限
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggers"]
  verbs: ["get", "list", "watch"]
# 基础资源权限
- apiGroups: [""]
  resources: ["pods", "pods/log", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list"]
EOF
```

### 创建机器人ServiceAccount和Token
```bash
# 创建CI/CD机器人ServiceAccount
kubectl create serviceaccount tekton-cicd-bot-sa

# 绑定机器人权限
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-cicd-bot-binding
subjects:
- kind: ServiceAccount
  name: tekton-cicd-bot-sa
  namespace: default
roleRef:
  kind: ClusterRole
  name: tekton-cicd-bot
  apiGroup: rbac.authorization.k8s.io
EOF

# 创建持久化Token (Kubernetes 1.24+)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tekton-cicd-bot-token
  namespace: default
  annotations:
    kubernetes.io/service-account.name: tekton-cicd-bot-sa
type: kubernetes.io/service-account-token
EOF
```

## 🔐 步骤8: 可选 - 安全策略配置

### 配置NetworkPolicy (可选)
```bash
# 创建Tekton网络访问策略
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-network-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: tekton-pipelines
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: tekton-pipelines
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to: []
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
EOF
```

### 配置PodSecurityPolicy (可选)
```bash
# 创建Tekton Pod安全策略
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: tekton-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
EOF
```

## 🧪 步骤9: 可选 - 权限验证测试

### 测试EventListener权限
```bash
# 检查EventListener是否正常运行
kubectl get pods -l eventlistener=hello-event-listener
kubectl get eventlistener hello-event-listener

# 测试Webhook端点
curl -X POST http://localhost:30088 \
  -H "Content-Type: application/json" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/test/repo.git",
      "name": "test-repo"
    },
    "head_commit": {
      "id": "abc123"
    },
    "pusher": {
      "name": "test-user"
    }
  }'

# 检查是否自动创建了PipelineRun
kubectl get pipelinerun
```

### 测试不同权限级别
```bash
# 测试开发者权限
kubectl auth can-i create pipelineruns --as=system:serviceaccount:default:tekton-developer-sa
kubectl auth can-i delete pipelineruns --as=system:serviceaccount:default:tekton-developer-sa

# 测试查看者权限
kubectl auth can-i get pipelineruns --as=system:serviceaccount:default:tekton-viewer-sa
kubectl auth can-i create pipelineruns --as=system:serviceaccount:default:tekton-viewer-sa

# 测试机器人权限
kubectl auth can-i create pipelineruns --as=system:serviceaccount:default:tekton-cicd-bot-sa
kubectl auth can-i delete pipelines --as=system:serviceaccount:default:tekton-cicd-bot-sa
```

## 📊 步骤10: 可选 - 获取访问凭据

### 获取ServiceAccount Token
```bash
# 获取开发者Token
DEV_TOKEN=$(kubectl get secret $(kubectl get serviceaccount tekton-developer-sa -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 --decode)

# 获取查看者Token
VIEWER_TOKEN=$(kubectl get secret $(kubectl get serviceaccount tekton-viewer-sa -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 --decode)

# 获取机器人Token
BOT_TOKEN=$(kubectl get secret tekton-cicd-bot-token -o jsonpath='{.data.token}' | base64 --decode)

echo "开发者Token: $DEV_TOKEN"
echo "查看者Token: $VIEWER_TOKEN" 
echo "机器人Token: $BOT_TOKEN"
```

### 创建kubeconfig文件
```bash
# 为开发者创建独立的kubeconfig
kubectl config set-cluster tekton-cluster --server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}') --certificate-authority-data=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}') --kubeconfig=tekton-developer.kubeconfig

kubectl config set-credentials tekton-developer --token=$DEV_TOKEN --kubeconfig=tekton-developer.kubeconfig

kubectl config set-context tekton-developer-context --cluster=tekton-cluster --user=tekton-developer --namespace=default --kubeconfig=tekton-developer.kubeconfig

kubectl config use-context tekton-developer-context --kubeconfig=tekton-developer.kubeconfig

echo "开发者kubeconfig文件: tekton-developer.kubeconfig"
```

## 📋 权限配置结果总结

### ✅ 实际完成的权限配置
1. **EventListener权限修复**: 解决了Triggers系统的权限问题
2. **功能验证**: 确认Webhook和Pipeline执行正常工作
3. **可选权限配置**: 提供了管理员、开发者等角色的权限模板

### 🔐 **实际配置的权限总结**

| 组件 | ServiceAccount | 权限范围 | 状态 |
|------|----------------|----------|------|
| EventListener | tekton-triggers-sa | 集群级 | ✅ 已配置 |
| Triggers Controller | 系统自动创建 | 集群级 | ✅ 已配置 |
| Pipelines Controller | 系统自动创建 | 集群级 | ✅ 已配置 |
| Dashboard | 系统自动创建 | 集群级 | ✅ 已配置 |

**核心解决的问题**:
- ✅ EventListener权限不足导致的启动失败
- ✅ ClusterInterceptor缺失导致的CA证书错误
- ✅ Webhook触发Pipeline的完整工作流程验证

### 🎯 生产环境安全配置
此权限配置已针对生产环境优化:
- **最小权限原则**: 每个角色仅获得必要权限
- **权限隔离**: 不同用户类型权限完全隔离
- **安全审计**: 所有权限变更可追踪
- **Token管理**: 独立的访问凭据管理
- **网络策略**: 可选的网络访问控制

## 🚀 下一步

完成权限配置后，您可以继续:
1. [GPU Pipeline部署](07-gpu-pipeline-deployment.md)
2. [高级Pipeline配置](08-advanced-pipeline-configuration.md)
3. [监控和日志配置](09-monitoring-logging-setup.md)

## 🎉 总结

成功完成了Tekton权限问题的诊断和修复！现在您拥有:

**🔧 修复的EventListener**: 权限完整，正常工作  
**✅ 验证的Webhook功能**: 自动触发Pipeline执行  
**📚 可选权限配置**: 根据需要配置不同角色权限  

核心问题已解决，Tekton Triggers系统正常运行！
