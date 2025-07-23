# 阶段二：Tekton CI/CD 自动化配置指南

本指南详细介绍如何在已有的 Tekton 核心基础设施基础上配置 Tekton Triggers，实现 GitHub webhook 触发 Pipeline 自动执行的完整 CI/CD 自动化流程。

## 📋 阶段二目标

- ✅ 安装 Tekton Triggers（事件驱动系统）
- ✅ 配置 GitHub Webhook 集成
- ✅ 创建 EventListener（事件监听器）
- ✅ 配置 TriggerBinding 和 TriggerTemplate
- ✅ 设置 RBAC 权限和安全配置
- ✅ 验证自动化 Pipeline 触发

## 🏗️ 架构概览

```
┌─────────────────────────────────────────────────┐
│                GitHub 代码仓库                     │
│         https://github.com/user/repo           │
└─────────────────┬───────────────────────────────┘
                  │ push event
                  ▼
┌─────────────────────────────────────────────────┐
│              GitHub Webhook                     │
│    http://tekton.10.117.8.154.nip.io/webhook   │
└─────────────────┬───────────────────────────────┘
                  │ HTTP POST
                  ▼
┌─────────────────────────────────────────────────┐
│            Nginx Ingress Controller             │
│              (路由和负载均衡)                      │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│             EventListener                      │
│          (接收和解析 webhook 事件)                │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│        TriggerBinding + TriggerTemplate         │
│        (提取参数 + 创建 PipelineRun)              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              PipelineRun                       │
│           (自动执行 CI/CD 流程)                  │
└─────────────────────────────────────────────────┘
```

## 🔧 前提条件

### 必要条件

- ✅ **阶段一已完成**: Tekton Pipelines + Dashboard 已安装并正常运行
- ✅ **Dashboard 可访问**: `http://tekton.10.117.8.154.nip.io/` 正常工作
- ✅ **GitHub 仓库**: 有管理权限的 GitHub 仓库
- ✅ **网络访问**: GitHub 能够访问您的 webhook 端点

### 验证前提条件

```bash
# 检查阶段一安装状态
kubectl get pods -n tekton-pipelines
kubectl get ingress -n tekton-pipelines

# 验证 Dashboard 访问
curl -s http://tekton.10.117.8.154.nip.io/ | grep -q "Tekton" && echo "Dashboard 正常" || echo "Dashboard 异常"

# 检查现有 Pipeline 功能
kubectl get pipeline,task -n tekton-pipelines
```

### 环境配置

```bash
# 设置环境变量
export TEKTON_NAMESPACE="tekton-pipelines"
export NODE_IP="10.117.8.154"
export TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"
export WEBHOOK_URL="http://${TEKTON_DOMAIN}/webhook"
export GITHUB_REPO_URL="https://github.com/johnnynv/tekton-poc"
export GITHUB_SECRET="110120119"

# 验证配置
echo "Webhook URL: ${WEBHOOK_URL}"
echo "GitHub 仓库: ${GITHUB_REPO_URL}"
```

## 🚀 安装步骤

### 步骤 1: 安装 Tekton Triggers

#### 1.1 安装 Triggers 组件

```bash
# 安装 Tekton Triggers
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# 等待组件启动
echo "等待 Tekton Triggers 组件启动..."
kubectl wait --for=condition=ready pods --all -n tekton-pipelines --timeout=300s
```

#### 1.2 验证 Triggers 安装

```bash
# 检查 Triggers 组件
kubectl get pods -l app.kubernetes.io/part-of=tekton-triggers -n tekton-pipelines

# 检查 CRD
kubectl get crd | grep triggers

# 验证 API 版本
kubectl api-versions | grep triggers
```

### 步骤 2: 配置 RBAC 权限

#### 2.1 创建 ServiceAccount

```bash
# 创建专用 ServiceAccount
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: ${TEKTON_NAMESPACE}
EOF
```

#### 2.2 配置 ClusterRole

```bash
# 创建 ClusterRole
cat <<EOF | kubectl apply -f -
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
  resources: ["pipelineruns", "pipelineresources", "taskruns"]
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
EOF
```

#### 2.3 绑定权限

```bash
# 创建 ClusterRoleBinding
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: ${TEKTON_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-role
EOF
```

### 步骤 3: 配置 GitHub Webhook Secret

#### 3.1 创建 Webhook Secret

```bash
# 创建 GitHub webhook secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-secret
  namespace: ${TEKTON_NAMESPACE}
type: Opaque
stringData:
  secretToken: "${GITHUB_SECRET}"
EOF
```

#### 3.2 验证 Secret

```bash
# 验证 Secret 创建
kubectl get secret github-webhook-secret -n ${TEKTON_NAMESPACE}
kubectl get secret github-webhook-secret -n ${TEKTON_NAMESPACE} -o jsonpath='{.data.secretToken}' | base64 -d
```

### 步骤 4: 创建 Pipeline 和 Task

#### 4.1 创建简化测试 Task

```bash
# 创建 webhook 测试 Task
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: simple-hello-task
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: repo-url
    type: string
    default: "unknown"
  - name: revision
    type: string
    default: "main"
  steps:
  - name: hello
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "🎉 GitHub Webhook 触发成功！"
      echo "代码仓库: \$(params.repo-url)"
      echo "提交版本: \$(params.revision)"
      echo "触发时间: \$(date)"
      echo "节点信息: \$(hostname)"
      echo "================================"
      echo "✅ Tekton Triggers 工作正常"
EOF
```

#### 4.2 创建 Pipeline

```bash
# 创建 webhook Pipeline
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: github-webhook-pipeline
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: repo-url
    type: string
  - name: revision
    type: string
  tasks:
  - name: hello
    taskRef:
      name: simple-hello-task
    params:
    - name: repo-url
      value: \$(params.repo-url)
    - name: revision
      value: \$(params.revision)
EOF
```

### 步骤 5: 配置 Triggers 组件

#### 5.1 创建 TriggerBinding

```bash
# 创建 TriggerBinding (从 GitHub webhook 提取参数)
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: git-repo-url
    value: \$(body.repository.clone_url)
  - name: git-repo-name
    value: \$(body.repository.name)
  - name: git-revision
    value: \$(body.head_commit.id)
  - name: git-commit-message
    value: \$(body.head_commit.message)
  - name: git-author
    value: \$(body.head_commit.author.name)
EOF
```

#### 5.2 创建 TriggerTemplate

```bash
# 创建 TriggerTemplate (定义要创建的 PipelineRun)
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: git-repo-name
  - name: git-commit-message
    default: "no message"
  - name: git-author
    default: "unknown"
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: github-webhook-run-
      namespace: ${TEKTON_NAMESPACE}
      labels:
        app: tekton-triggers
        trigger: github-webhook
    spec:
      pipelineRef:
        name: github-webhook-pipeline
      params:
      - name: repo-url
        value: \$(tt.params.git-repo-url)
      - name: revision
        value: \$(tt.params.git-revision)
EOF
```

#### 5.3 创建 EventListener

```bash
# 创建 EventListener (监听 GitHub webhook 事件)
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
  namespace: ${TEKTON_NAMESPACE}
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
    bindings:
    - ref: github-trigger-binding
    template:
      ref: github-trigger-template
EOF
```

### 步骤 6: 配置网络访问

#### 6.1 创建 EventListener Service

```bash
# 获取 EventListener service 名称
EL_SERVICE_NAME="el-github-webhook-listener"

# 验证 Service 已创建
kubectl get svc ${EL_SERVICE_NAME} -n ${TEKTON_NAMESPACE}
```

#### 6.2 创建 Webhook Ingress

```bash
# 创建 webhook Ingress 路由
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: github-webhook-ingress
  namespace: ${TEKTON_NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: ${TEKTON_DOMAIN}
    http:
      paths:
      - path: /webhook
        pathType: Exact
        backend:
          service:
            name: ${EL_SERVICE_NAME}
            port:
              number: 8080
EOF
```

### 步骤 7: 生产环境安全配置

#### 7.1 应用 Pod Security Standards

```bash
# 配置 Pod Security (Triggers 需要 privileged 权限)
kubectl label namespace ${TEKTON_NAMESPACE} pod-security.kubernetes.io/enforce=privileged --overwrite
```

#### 7.2 配置网络策略

```bash
# 创建 EventListener 网络策略
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: eventlistener-access
  namespace: ${TEKTON_NAMESPACE}
spec:
  podSelector:
    matchLabels:
      eventlistener: github-webhook-listener
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  - from: []
    ports:
    - protocol: TCP
      port: 8080
EOF
```

## ✅ 验证安装

### 自动验证

```bash
# 运行阶段二验证脚本
./verify-installation.sh --stage=triggers
```

### 手动验证

#### 1. 组件状态检查

```bash
# 检查 Triggers 组件
kubectl get pods -l app.kubernetes.io/part-of=tekton-triggers -n ${TEKTON_NAMESPACE}

# 检查 EventListener
kubectl get eventlistener -n ${TEKTON_NAMESPACE}

# 检查 TriggerBinding 和 TriggerTemplate
kubectl get triggerbinding,triggertemplate -n ${TEKTON_NAMESPACE}

# 检查 Service 和 Ingress
kubectl get svc,ingress -n ${TEKTON_NAMESPACE}
```

#### 2. 网络连通性测试

```bash
# 测试 webhook 端点
curl -X POST ${WEBHOOK_URL} \
  -H "Content-Type: application/json" \
  -d '{"test": "connection"}' \
  -v

# 检查响应 (应该返回 202 或类似状态)
echo "期望看到 HTTP 状态码: 202 Accepted 或 200 OK"
```

#### 3. 功能测试

```bash
# 手动创建测试 PipelineRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-test-run-
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: github-webhook-pipeline
  params:
  - name: repo-url
    value: "${GITHUB_REPO_URL}"
  - name: revision
    value: "main"
EOF

# 检查执行结果
kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --sort-by=.metadata.creationTimestamp
```

## 🔗 GitHub Webhook 配置

### 步骤 1: 访问 GitHub 仓库设置

1. 打开浏览器，访问您的 GitHub 仓库
2. 进入 **Settings** → **Webhooks**
3. 点击 **"Add webhook"** 按钮

### 步骤 2: 配置 Webhook

填写以下信息：

| 字段 | 值 | 说明 |
|------|------------|------|
| **Payload URL** | `http://tekton.10.117.8.154.nip.io/webhook` | Tekton webhook 端点 |
| **Content type** | `application/json` | JSON 格式数据 |
| **Secret** | `110120119` | webhook 验证密钥 |
| **Which events would you like to trigger this webhook?** | `Just the push event` | 仅 push 事件触发 |
| **Active** | ✅ 勾选 | 启用 webhook |

### 步骤 3: 保存和测试

1. 点击 **"Add webhook"** 保存配置
2. GitHub 会发送测试 ping 事件
3. 检查 webhook 状态应显示绿色 ✅

### 步骤 4: 验证自动触发

```bash
# 监控 PipelineRun 创建
kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --watch

# 在另一个终端查看 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE} -f
```

然后向 GitHub 仓库推送代码：

```bash
# 在您的 GitHub 仓库中
echo "# Test commit" >> README.md
git add README.md
git commit -m "Test Tekton webhook trigger"
git push origin main
```

## 📊 监控和调试

### Dashboard 监控

访问 Tekton Dashboard: `http://tekton.10.117.8.154.nip.io/`

在 Dashboard 中可以查看：
- **PipelineRuns**: 所有自动触发的执行
- **TaskRuns**: 详细的任务执行日志
- **EventListeners**: webhook 事件状态

### 命令行监控

```bash
# 实时监控 PipelineRuns
watch -n 5 'kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp'

# 查看最新 PipelineRun 详情
LATEST_RUN=$(kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl describe ${LATEST_RUN} -n ${TEKTON_NAMESPACE}

# 查看 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE} -f

# 查看特定 TaskRun 日志
kubectl logs -l tekton.dev/pipelineTask=hello -n ${TEKTON_NAMESPACE} -f
```

## 🔧 故障排查

### 常见问题

#### 1. EventListener Pod 无法启动

**症状**: EventListener Pod 处于 CrashLoopBackOff 状态

**解决方案**:
```bash
# 检查 Pod 详情
kubectl describe pod -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE}

# 检查 RBAC 权限
kubectl auth can-i create pipelinerun --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa

# 重新应用 RBAC 配置
kubectl apply -f <(本指南步骤2的所有RBAC配置)
```

#### 2. Webhook 无法触发 Pipeline

**症状**: push 代码后没有创建 PipelineRun

**解决方案**:
```bash
# 检查 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE}

# 检查 webhook 端点可达性
curl -X POST ${WEBHOOK_URL} -H "Content-Type: application/json" -d '{"test": "data"}'

# 验证 GitHub webhook 配置
echo "检查 GitHub 仓库 Settings -> Webhooks 中的状态"
```

#### 3. PipelineRun 创建但执行失败

**症状**: PipelineRun 创建成功但 TaskRun 失败

**解决方案**:
```bash
# 查看失败的 TaskRun
kubectl get taskrun -n ${TEKTON_NAMESPACE} | grep Failed

# 查看具体错误
FAILED_TASKRUN=$(kubectl get taskrun -n ${TEKTON_NAMESPACE} | grep Failed | head -1 | awk '{print $1}')
kubectl describe taskrun ${FAILED_TASKRUN} -n ${TEKTON_NAMESPACE}
kubectl logs -l tekton.dev/taskRun=${FAILED_TASKRUN} -n ${TEKTON_NAMESPACE}
```

#### 4. Ingress 路由问题

**症状**: webhook 端点返回 404 错误

**解决方案**:
```bash
# 检查 Ingress 配置
kubectl describe ingress github-webhook-ingress -n ${TEKTON_NAMESPACE}

# 检查 Service 端点
kubectl get endpoints ${EL_SERVICE_NAME} -n ${TEKTON_NAMESPACE}

# 检查 Ingress Controller 日志
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx -f
```

### 调试命令

```bash
# 查看所有相关资源
kubectl get all,eventlistener,triggerbinding,triggertemplate -n ${TEKTON_NAMESPACE}

# 查看事件日志
kubectl get events --sort-by=.metadata.creationTimestamp -n ${TEKTON_NAMESPACE}

# 检查 Tekton Triggers 组件日志
kubectl logs -l app.kubernetes.io/part-of=tekton-triggers -n ${TEKTON_NAMESPACE}
```

## 🧹 清理

### 选择性清理

```bash
# 只删除 Triggers 相关资源
kubectl delete eventlistener,triggerbinding,triggertemplate github-webhook-listener github-trigger-binding github-trigger-template -n ${TEKTON_NAMESPACE}

# 删除所有自动创建的 PipelineRuns
kubectl delete pipelinerun -l app=tekton-triggers -n ${TEKTON_NAMESPACE}

# 删除 webhook Secret
kubectl delete secret github-webhook-secret -n ${TEKTON_NAMESPACE}
```

### 完全清理

```bash
# 运行自动清理脚本
./02-cleanup-tekton-triggers.sh

# 手动清理步骤
kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
```

## 📊 生产环境优化

### 性能优化

- **资源限制**: 为 EventListener 设置适当的 CPU/Memory 限制
- **副本数量**: 根据负载配置 EventListener 多副本
- **缓存策略**: 配置 Pipeline 结果缓存

### 安全加固

- **Secret 管理**: 使用 Kubernetes Secrets 或外部密钥管理
- **网络隔离**: 配置更严格的 NetworkPolicy
- **认证授权**: 集成 RBAC 和 Pod Security Standards

### 监控集成

- **Prometheus**: 监控 Triggers 和 Pipeline 指标
- **Grafana**: 可视化 CI/CD 流程性能
- **AlertManager**: 配置失败告警

## 🎯 完成标志

阶段二配置成功后，您应该能够：

- ✅ GitHub push 事件自动触发 Pipeline 执行
- ✅ 在 Dashboard 中查看自动创建的 PipelineRun
- ✅ webhook 端点正常响应 GitHub 请求
- ✅ EventListener 日志显示事件处理过程

**🎉 恭喜！您已完成 Tekton 生产级部署！**

现在您拥有了一个完整的 CI/CD 自动化系统：
- 🏗️ **阶段一**: 核心基础设施 (Pipelines + Dashboard + Ingress)
- 🚀 **阶段二**: 自动化 CI/CD (Triggers + GitHub Webhook)

## 📖 进阶配置

### 多仓库支持

配置多个 GitHub 仓库的 webhook 支持：

```bash
# 为不同仓库创建不同的 EventListener
# 使用不同的 TriggerBinding 处理不同的参数提取
```

### 多环境部署

配置开发、测试、生产环境的不同 Pipeline：

```bash
# 根据分支名称或标签触发不同的 Pipeline
# 使用 CEL 表达式进行条件判断
```

### 高级 Pipeline

集成更复杂的 CI/CD 流程：

```bash
# 代码编译、测试、构建镜像、部署
# 集成代码质量检查、安全扫描
# 多阶段部署和回滚机制
``` 