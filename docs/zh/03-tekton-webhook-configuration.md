# Tekton Webhook 配置指南

本指南详细介绍如何配置 GitHub Webhooks 与 Tekton Triggers 集成，实现自动化 CI/CD 流程。

## 📋 配置目标

- ✅ 配置 GitHub Webhook 密钥认证
- ✅ 创建 GitHub 事件过滤器
- ✅ 设置自动触发条件
- ✅ 验证 Webhook 集成

## 🔧 前提条件

- ✅ 已完成 [Tekton Triggers 配置](02-tekton-triggers-setup.md)
- ✅ 拥有 GitHub 仓库管理权限
- ✅ EventListener 服务可外部访问

## 🔐 步骤1：创建 Webhook 密钥

### 生成安全密钥
```bash
# 生成随机密钥
WEBHOOK_SECRET=$(openssl rand -base64 32)
echo "GitHub Webhook Secret: ${WEBHOOK_SECRET}"

# 创建 Kubernetes Secret
kubectl create secret generic github-webhook-secret \
  --from-literal=webhook-secret="${WEBHOOK_SECRET}" \
  -n tekton-pipelines

# 保存密钥（用于 GitHub 配置）
echo "${WEBHOOK_SECRET}" > webhook-secret.txt
echo "密钥已保存到 webhook-secret.txt"
```

## 📝 步骤2：创建 GitHub 集成组件

### 创建 GitHub TriggerBinding
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: \$(body.repository.clone_url)
  - name: git-revision
    value: \$(body.head_commit.id)
  - name: git-repo-name
    value: \$(body.repository.name)
  - name: git-branch
    value: \$(body.ref)
  - name: git-author
    value: \$(body.head_commit.author.name)
  - name: git-message
    value: \$(body.head_commit.message)
EOF
```

### 创建 GitHub TriggerTemplate
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    description: Git repository URL
  - name: git-revision
    description: Git revision
  - name: git-repo-name
    description: Git repository name
  - name: git-branch
    description: Git branch reference
  - name: git-author
    description: Git commit author
  - name: git-message
    description: Git commit message
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: TaskRun
    metadata:
      generateName: github-webhook-run-
      labels:
        tekton.dev/trigger: github-webhook
        git.repository: \$(tt.params.git-repo-name)
    spec:
      taskSpec:
        params:
        - name: repo-url
          type: string
        - name: revision
          type: string
        - name: repo-name
          type: string
        - name: branch
          type: string
        - name: author
          type: string
        - name: message
          type: string
        steps:
        - name: log-webhook-info
          image: ubuntu
          script: |
            #!/bin/bash
            echo "=== GitHub Webhook Triggered ==="
            echo "Repository: \$(params.repo-url)"
            echo "Branch: \$(params.branch)"
            echo "Commit: \$(params.revision)"
            echo "Author: \$(params.author)"
            echo "Message: \$(params.message)"
            echo "================================"
            
        - name: process-webhook
          image: alpine/git
          script: |
            #!/bin/sh
            echo "Processing webhook for repository: \$(params.repo-name)"
            echo "Webhook integration successful!"
      params:
      - name: repo-url
        value: \$(tt.params.git-repo-url)
      - name: revision
        value: \$(tt.params.git-revision)
      - name: repo-name
        value: \$(tt.params.git-repo-name)
      - name: branch
        value: \$(tt.params.git-branch)
      - name: author
        value: \$(tt.params.git-author)
      - name: message
        value: \$(tt.params.git-message)
EOF
```

### 创建带过滤器的 EventListener
```bash
cat <<EOF | kubectl apply -f -
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
    # GitHub webhook 验证
    - ref:
        name: "github"
      params:
      - name: "secretRef"
        value:
          secretName: github-webhook-secret
          secretKey: webhook-secret
      - name: "eventTypes"
        value: ["push", "pull_request"]
    
    # CEL 过滤器（条件触发）
    - ref:
        name: "cel"
      params:
      - name: "filter"
        value: >
          (body.ref == 'refs/heads/main' || 
           body.ref == 'refs/heads/develop' ||
           body.pull_request.base.ref == 'main')
      - name: "overlays"
        value:
        - key: "trigger_reason"
          expression: >
            body.ref == 'refs/heads/main' ? 'main_push' :
            body.ref == 'refs/heads/develop' ? 'develop_push' :
            'pull_request'
    
    bindings:
    - ref: github-trigger-binding
    
    template:
      ref: github-trigger-template
EOF
```

## 🌐 步骤3：配置 EventListener 外部访问

### 获取 Webhook URL
```bash
# 配置 NodePort 服务
kubectl patch svc el-github-webhook-listener -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'

# 获取访问信息
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc el-github-webhook-listener -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')

WEBHOOK_URL="http://${NODE_IP}:${NODE_PORT}"
echo "GitHub Webhook URL: ${WEBHOOK_URL}"

# 保存配置信息
cat > webhook-config.txt << EOF
GitHub Webhook 配置信息
====================
Webhook URL: ${WEBHOOK_URL}
Secret: $(cat webhook-secret.txt)
Content Type: application/json
Events: Push events, Pull requests
====================
EOF

echo "配置信息已保存到 webhook-config.txt"
```

## 📱 步骤4：在 GitHub 中配置 Webhook

### 1. 进入 GitHub 仓库设置
1. 打开您的 GitHub 仓库
2. 点击 **Settings** 标签
3. 在左侧菜单选择 **Webhooks**
4. 点击 **Add webhook** 按钮

### 2. 配置 Webhook 参数

| 参数 | 值 | 说明 |
|------|-----|------|
| **Payload URL** | `http://YOUR_NODE_IP:NODE_PORT` | EventListener 服务地址 |
| **Content type** | `application/json` | 必须选择 JSON 格式 |
| **Secret** | `webhook-secret.txt 中的密钥` | 用于验证请求 |
| **Which events?** | `Just the push event` | 推送事件触发 |
| **Active** | ✅ 勾选 | 启用 Webhook |

### 3. 保存配置
点击 **Add webhook** 完成配置

## ✅ 验证 Webhook 配置

### 1. 检查 Webhook 状态
```bash
# 检查 EventListener 状态
kubectl get eventlistener github-webhook-listener -n tekton-pipelines

# 检查服务状态
kubectl get svc el-github-webhook-listener -n tekton-pipelines

# 检查端点
kubectl get endpoints el-github-webhook-listener -n tekton-pipelines
```

### 2. 手动测试 Webhook
```bash
# 读取保存的密钥
WEBHOOK_SECRET=$(cat webhook-secret.txt)

# 生成测试载荷
cat > test-payload.json << EOF
{
  "repository": {
    "name": "test-repo",
    "clone_url": "https://github.com/example/test-repo.git"
  },
  "ref": "refs/heads/main",
  "head_commit": {
    "id": "abc123def456",
    "author": {
      "name": "Test User"
    },
    "message": "Test webhook trigger"
  }
}
EOF

# 计算签名
SIGNATURE=$(echo -n "$(cat test-payload.json)" | openssl dgst -sha256 -hmac "${WEBHOOK_SECRET}" | cut -d' ' -f2)

# 发送测试请求
curl -X POST "${WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=${SIGNATURE}" \
  -d @test-payload.json

echo "测试 Webhook 请求已发送"
```

### 3. 验证触发结果
```bash
# 查看触发的 TaskRuns
kubectl get taskruns -n tekton-pipelines -l tekton.dev/trigger=github-webhook

# 查看最新日志
kubectl logs -l tekton.dev/trigger=github-webhook -n tekton-pipelines --tail=20

# 在 Dashboard 中查看
echo "在 Dashboard 中查看: http://${NODE_IP}:${DASHBOARD_PORT}"
```

### 4. 实际推送测试
```bash
# 在本地仓库中创建测试提交
echo "Test webhook integration" >> README.md
git add README.md
git commit -m "Test Tekton webhook [trigger]"
git push origin main
```

## 🔧 高级配置

### 分支过滤配置
```bash
# 更新 EventListener 以支持多分支过滤
kubectl patch eventlistener github-webhook-listener -n tekton-pipelines --type='merge' -p='
{
  "spec": {
    "triggers": [{
      "name": "github-push-trigger",
      "interceptors": [{
        "ref": {
          "name": "github"
        },
        "params": [{
          "name": "secretRef",
          "value": {
            "secretName": "github-webhook-secret",
            "secretKey": "webhook-secret"
          }
        }, {
          "name": "eventTypes",
          "value": ["push"]
        }]
      }, {
        "ref": {
          "name": "cel"
        },
        "params": [{
          "name": "filter",
          "value": "body.ref.startsWith(\"refs/heads/main\") || body.ref.startsWith(\"refs/heads/develop\") || body.ref.startsWith(\"refs/heads/feature/\")"
        }]
      }]
    }]
  }
}'
```

### 标签触发配置
```bash
# 支持特定提交消息标签触发
kubectl patch eventlistener github-webhook-listener -n tekton-pipelines --type='merge' -p='
{
  "spec": {
    "triggers": [{
      "interceptors": [{
        "ref": {
          "name": "cel"
        },
        "params": [{
          "name": "filter",
          "value": "body.head_commit.message.contains(\"[trigger]\") || body.head_commit.message.contains(\"[build]\")"
        }]
      }]
    }]
  }
}'
```

## 🔧 故障排除

### 常见问题

**1. Webhook 验证失败**
```bash
# 检查密钥配置
kubectl get secret github-webhook-secret -n tekton-pipelines -o yaml

# 验证密钥内容
kubectl get secret github-webhook-secret -n tekton-pipelines -o jsonpath='{.data.webhook-secret}' | base64 -d
```

**2. EventListener 无响应**
```bash
# 检查 EventListener 日志
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines

# 检查网络连接
kubectl run test-webhook --image=curlimages/curl -it --rm -- curl -v "${WEBHOOK_URL}"
```

**3. GitHub Webhook 失败**
在 GitHub 仓库的 Webhooks 设置页面：
- 检查 **Recent Deliveries** 
- 查看具体的错误响应
- 验证 Response 状态码

## 📊 监控和日志

### 设置监控
```bash
# 查看 Webhook 活动
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'

# 监控 TaskRun 创建
kubectl get taskruns -n tekton-pipelines -w

# 查看详细日志
kubectl logs -f -l app.kubernetes.io/component=eventlistener -n tekton-pipelines
```

## 📚 下一步

Webhook 配置完成后，您可以：
1. 部署 GPU 科学计算 Pipeline
2. 配置更复杂的 CI/CD 流程

继续阅读：[04-gpu-pipeline-deployment.md](04-gpu-pipeline-deployment.md) 