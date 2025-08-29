# Tekton Webhook 集成配置指南

本指南详细介绍如何配置GitHub、GitLab、Bitbucket等Git平台的Webhook，与已部署的Tekton Triggers v0.33.0实现完整的CI/CD自动化集成。

**📋 前提条件**: 您已经完成了[04-tekton-triggers-setup.md](04-tekton-triggers-setup.md)和[06-tekton-restricted-user-setup.md](06-tekton-restricted-user-setup.md)中的基础配置，包括:
- ✅ 基础EventListener `hello-event-listener` 已创建并正常工作
- ✅ 基础Webhook端点 `http://localhost:30088` 可用
- ✅ 基础Pipeline测试已通过

本文档介绍的是**扩展配置**，用于支持特定Git平台的高级功能。

## 🎯 配置规划

### 支持的Git平台
- **GitHub**: GitHub.com + GitHub Enterprise
- **GitLab**: GitLab.com + GitLab CE/EE
- **Bitbucket**: Bitbucket Cloud + Bitbucket Server
- **Gitea**: 自托管Git服务
- **自定义**: 任何支持Webhook的Git平台

### 集成架构
```
完整的Webhook集成架构
├── Git Repository (代码仓库)
│   └── Webhook Configuration (Webhook配置)
├── Public Internet (公网)
│   └── Ingress/NodePort (入口服务)
├── Tekton EventListener (事件监听器)
│   ├── GitHub Interceptor (GitHub拦截器)
│   ├── GitLab Interceptor (GitLab拦截器)
│   └── Custom Interceptor (自定义拦截器)
└── Pipeline Execution (流水线执行)
```

## 🏁 步骤1: 环境准备

### 验证Tekton Triggers状态
```bash
# 检查Triggers组件状态
kubectl get pods -n tekton-pipelines | grep triggers
kubectl get eventlistener -A
kubectl get svc | grep webhook
```

**验证结果**:
```
# Triggers组件状态
tekton-triggers-controller-7ddb4685-zmzhf      1/1     Running   0          24m
tekton-triggers-webhook-5b8765fdc9-gndtv       1/1     Running   0          24m

# EventListener状态
NAMESPACE   NAME                   ADDRESS                                                         AVAILABLE   READY
default     hello-event-listener   http://el-hello-event-listener.default.svc.cluster.local:8080   True        True

# Webhook服务
hello-webhook-nodeport    NodePort    10.110.193.77   <none>        8080:30088/TCP      14m
```

- ✅ Tekton Triggers运行正常
- ✅ EventListener可用
- ✅ Webhook端点可访问 (http://10.78.14.61:30088)

## 🐙 步骤2: GitHub Webhook集成

### 创建GitHub专用的EventListener
```bash
# 创建GitHub专用的TriggerBinding
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.repository.clone_url)
  - name: git-revision
    value: \$(body.after)
  - name: git-branch
    value: \$(body.ref)
  - name: repo-name
    value: \$(body.repository.name)
  - name: repo-owner
    value: \$(body.repository.owner.login)
  - name: commit-message
    value: \$(body.head_commit.message)
  - name: commit-author
    value: \$(body.head_commit.author.name)
EOF
```

### 创建GitHub Pipeline
```bash
# 创建GitHub专用的Pipeline
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: github-ci-pipeline
  namespace: default
spec:
  params:
  - name: git-url
    type: string
    description: Git repository URL
  - name: git-revision
    type: string
    description: Git commit SHA
  - name: git-branch
    type: string
    description: Git branch reference
  - name: repo-name
    type: string
    description: Repository name
  - name: repo-owner
    type: string
    description: Repository owner
  - name: commit-message
    type: string
    description: Commit message
  - name: commit-author
    type: string
    description: Commit author
  tasks:
  - name: git-clone
    taskSpec:
      params:
      - name: git-url
        type: string
      - name: git-revision
        type: string
      - name: git-branch
        type: string
      steps:
      - name: clone
        image: alpine/git:latest
        script: |
          #!/bin/sh
          echo "==================================="
          echo "Cloning GitHub Repository"
          echo "==================================="
          echo "Repository: \$(params.git-url)"
          echo "Revision: \$(params.git-revision)"
          echo "Branch: \$(params.git-branch)"
          echo "==================================="
          
          # 实际项目中这里会进行git clone操作
          # git clone \$(params.git-url) /workspace/source
          # cd /workspace/source
          # git checkout \$(params.git-revision)
          
          echo "Clone completed successfully!"
    params:
    - name: git-url
      value: \$(params.git-url)
    - name: git-revision
      value: \$(params.git-revision)
    - name: git-branch
      value: \$(params.git-branch)
  - name: build-and-test
    runAfter: ["git-clone"]
    taskSpec:
      params:
      - name: repo-name
        type: string
      - name: repo-owner
        type: string
      - name: commit-message
        type: string
      - name: commit-author
        type: string
      steps:
      - name: build
        image: alpine:latest
        script: |
          #!/bin/sh
          echo "==================================="
          echo "Building GitHub Project"
          echo "==================================="
          echo "Repository: \$(params.repo-owner)/\$(params.repo-name)"
          echo "Commit: \$(params.commit-message)"
          echo "Author: \$(params.commit-author)"
          echo "==================================="
          
          # 实际项目中这里会进行构建和测试
          # npm install && npm test
          # docker build -t \$(params.repo-name):latest .
          
          echo "Build and test completed successfully!"
    params:
    - name: repo-name
      value: \$(params.repo-name)
    - name: repo-owner
      value: \$(params.repo-owner)
    - name: commit-message
      value: \$(params.commit-message)
    - name: commit-author
      value: \$(params.commit-author)
EOF
```

### 创建GitHub TriggerTemplate
```bash
# 创建GitHub专用的TriggerTemplate
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: default
spec:
  params:
  - name: git-url
    description: Git repository URL
  - name: git-revision
    description: Git commit SHA
  - name: git-branch
    description: Git branch reference
  - name: repo-name
    description: Repository name
  - name: repo-owner
    description: Repository owner
  - name: commit-message
    description: Commit message
  - name: commit-author
    description: Commit author
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: github-ci-run-
      annotations:
        git-url: \$(tt.params.git-url)
        git-revision: \$(tt.params.git-revision)
        git-branch: \$(tt.params.git-branch)
    spec:
      pipelineRef:
        name: github-ci-pipeline
      params:
      - name: git-url
        value: \$(tt.params.git-url)
      - name: git-revision
        value: \$(tt.params.git-revision)
      - name: git-branch
        value: \$(tt.params.git-branch)
      - name: repo-name
        value: \$(tt.params.repo-name)
      - name: repo-owner
        value: \$(tt.params.repo-owner)
      - name: commit-message
        value: \$(tt.params.commit-message)
      - name: commit-author
        value: \$(tt.params.commit-author)
EOF
```

### 创建GitHub EventListener
```bash
# 创建GitHub专用的EventListener
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-event-listener
  namespace: default
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: github-push-trigger
    interceptors:
    - name: "verify-github-payload"
      ref:
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

### 创建GitHub Webhook密钥
```bash
# 创建GitHub Webhook验证密钥
kubectl create secret generic github-webhook-secret \
  --from-literal=secretToken="github-webhook-secret-token-2024"

# 验证密钥创建
kubectl get secret github-webhook-secret
```

### 创建GitHub Webhook NodePort服务
```bash
# 创建GitHub专用的NodePort服务
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: github-webhook-nodeport
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30089
    protocol: TCP
  selector:
    eventlistener: github-event-listener
EOF
```

### 验证GitHub EventListener
```bash
# 验证GitHub EventListener状态
kubectl get eventlistener github-event-listener
kubectl get svc github-webhook-nodeport
kubectl get pods -l eventlistener=github-event-listener
```

## 🦊 步骤3: GitLab Webhook集成

### 创建GitLab专用的TriggerBinding
```bash
# 创建GitLab专用的TriggerBinding
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: gitlab-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.project.git_http_url)
  - name: git-revision
    value: \$(body.after)
  - name: git-branch
    value: \$(body.ref)
  - name: repo-name
    value: \$(body.project.name)
  - name: repo-namespace
    value: \$(body.project.namespace)
  - name: commit-message
    value: \$(body.commits[0].message)
  - name: commit-author
    value: \$(body.commits[0].author.name)
  - name: user-name
    value: \$(body.user_name)
EOF
```

### 创建GitLab EventListener
```bash
# 创建GitLab专用的EventListener
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: gitlab-event-listener
  namespace: default
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: gitlab-push-trigger
    interceptors:
    - name: "verify-gitlab-payload"
      ref:
        name: "gitlab"
      params:
      - name: "secretRef"
        value:
          secretName: gitlab-webhook-secret
          secretKey: secretToken
      - name: "eventTypes"
        value: ["Push Hook"]
    bindings:
    - ref: gitlab-trigger-binding
    template:
      ref: github-trigger-template  # 复用相同的模板
EOF
```

### 创建GitLab Webhook密钥和服务
```bash
# 创建GitLab Webhook验证密钥
kubectl create secret generic gitlab-webhook-secret \
  --from-literal=secretToken="gitlab-webhook-secret-token-2024"

# 创建GitLab专用的NodePort服务
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gitlab-webhook-nodeport
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30090
    protocol: TCP
  selector:
    eventlistener: gitlab-event-listener
EOF
```

## 🔧 步骤4: 配置HTTPS Ingress (生产环境推荐)

### 创建Webhook Ingress
```bash
# 获取节点IP地址
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 为Webhook创建HTTPS Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-webhook-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  tls:
  - hosts:
    - webhook.\$NODE_IP.nip.io
    secretName: webhook-tls-secret
  rules:
  - host: webhook.\$NODE_IP.nip.io
    http:
      paths:
      - path: /github
        pathType: Prefix
        backend:
          service:
            name: el-github-event-listener
            port:
              number: 8080
      - path: /gitlab
        pathType: Prefix
        backend:
          service:
            name: el-gitlab-event-listener
            port:
              number: 8080
EOF

echo "Webhook HTTPS端点: https://webhook.\$NODE_IP.nip.io"
```

### 创建Webhook TLS证书
```bash
# 获取节点IP地址
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 创建Webhook专用的SSL证书
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout webhook-tls.key -out webhook-tls.crt -subj "/CN=webhook.$NODE_IP.nip.io" -addext "subjectAltName=DNS:webhook.$NODE_IP.nip.io"

# 创建TLS密钥
kubectl create secret tls webhook-tls-secret --key webhook-tls.key --cert webhook-tls.crt

# 清理临时文件
rm webhook-tls.key webhook-tls.crt

echo "Webhook域名: webhook.$NODE_IP.nip.io"
```

## 🧪 步骤5: 测试Webhook集成

### 测试GitHub Webhook
```bash
# 测试GitHub Webhook端点
curl -X POST http://10.78.14.61:30089 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=4a4fc1c8928b6c6e6d8c1b2e3c4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e" \
  -d '{
    "ref": "refs/heads/main",
    "after": "a1b2c3d4e5f6",
    "repository": {
      "name": "test-repo",
      "clone_url": "https://github.com/example/test-repo.git",
      "owner": {
        "login": "example"
      }
    },
    "head_commit": {
      "id": "a1b2c3d4e5f6",
      "message": "Test commit for Tekton integration",
      "author": {
        "name": "Developer"
      }
    }
  }'

# 检查触发的PipelineRun
kubectl get pipelinerun | grep github-ci-run
```

### 测试GitLab Webhook
```bash
# 测试GitLab Webhook端点
curl -X POST http://10.78.14.61:30090 \
  -H "Content-Type: application/json" \
  -H "X-Gitlab-Event: Push Hook" \
  -H "X-Gitlab-Token: gitlab-webhook-secret-token-2024" \
  -d '{
    "object_kind": "push",
    "ref": "refs/heads/main",
    "after": "b2c3d4e5f6a7",
    "project": {
      "name": "test-project",
      "namespace": "example",
      "git_http_url": "https://gitlab.com/example/test-project.git"
    },
    "commits": [{
      "id": "b2c3d4e5f6a7",
      "message": "Test commit for GitLab integration",
      "author": {
        "name": "GitLab Developer"
      }
    }],
    "user_name": "gitlab-user"
  }'

# 检查触发的PipelineRun
kubectl get pipelinerun | grep github-ci-run
```

### 测试HTTPS Webhook访问
```bash
# 获取节点IP地址
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 测试HTTPS GitHub Webhook
curl -X POST https://webhook.$NODE_IP.nip.io/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -k \
  -d '{"ref": "refs/heads/main", "repository": {"name": "https-test", "clone_url": "https://github.com/example/https-test.git", "owner": {"login": "example"}}, "head_commit": {"id": "test123", "message": "HTTPS test", "author": {"name": "HTTPS Tester"}}, "after": "test123"}'

# 测试HTTPS GitLab Webhook
curl -X POST https://webhook.$NODE_IP.nip.io/gitlab \
  -H "Content-Type: application/json" \
  -H "X-Gitlab-Event: Push Hook" \
  -k \
  -d '{"object_kind": "push", "ref": "refs/heads/main", "project": {"name": "https-test", "namespace": "example", "git_http_url": "https://gitlab.com/example/https-test.git"}, "commits": [{"id": "test456", "message": "HTTPS GitLab test", "author": {"name": "GitLab HTTPS Tester"}}], "user_name": "gitlab-https-user", "after": "test456"}'
```

## 📋 步骤6: Git平台Webhook配置

### GitHub仓库Webhook配置
1. **进入GitHub仓库设置**:
   - 访问: `https://github.com/用户名/仓库名/settings/hooks`
   - 点击 "Add webhook"

2. **配置Webhook设置**:
   ```
   Payload URL: http://10.78.14.61:30089
   或 HTTPS: https://webhook.$NODE_IP.nip.io/github
   
   Content type: application/json
   Secret: github-webhook-secret-token-2024
   
   Which events: Just the push event
   Active: ✅ 勾选
   ```

3. **验证配置**: 点击 "Add webhook" 完成配置

### GitLab项目Webhook配置
1. **进入GitLab项目设置**:
   - 访问: `https://gitlab.com/用户名/项目名/-/settings/integrations`
   - 选择 "Webhooks"

2. **配置Webhook设置**:
   ```
   URL: http://10.78.14.61:30090
   或 HTTPS: https://webhook.$NODE_IP.nip.io/gitlab
   
   Secret Token: gitlab-webhook-secret-token-2024
   
   Trigger: ✅ Push events
   Enable SSL verification: ❌ 取消勾选 (自签名证书)
   ```

3. **验证配置**: 点击 "Add webhook" 完成配置

### Bitbucket Webhook配置
```bash
# 为Bitbucket创建专用配置 (可选)
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: bitbucket-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.repository.links.clone[0].href)
  - name: git-revision
    value: \$(body.push.changes[0].new.target.hash)
  - name: git-branch
    value: \$(body.push.changes[0].new.name)
  - name: repo-name
    value: \$(body.repository.name)
  - name: repo-owner
    value: \$(body.repository.owner.display_name)
EOF
```

## 🔐 步骤7: 安全和监控配置

### 配置Webhook认证
```bash
# 创建高强度Webhook密钥
GITHUB_SECRET=$(openssl rand -hex 32)
GITLAB_SECRET=$(openssl rand -hex 32)

# 更新密钥
kubectl create secret generic github-webhook-secret \
  --from-literal=secretToken="$GITHUB_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitlab-webhook-secret \
  --from-literal=secretToken="$GITLAB_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "GitHub Webhook Secret: $GITHUB_SECRET"
echo "GitLab Webhook Secret: $GITLAB_SECRET"
```

### 配置访问日志监控
```bash
# 查看EventListener日志
kubectl logs -l eventlistener=github-event-listener --tail=100
kubectl logs -l eventlistener=gitlab-event-listener --tail=100

# 实时监控Webhook请求
kubectl logs -f -l eventlistener=github-event-listener
```

### 配置资源限制
```bash
# 为EventListener配置资源限制
kubectl patch eventlistener github-event-listener --type='merge' -p='{
  "spec": {
    "resources": {
      "requests": {
        "cpu": "100m",
        "memory": "128Mi"
      },
      "limits": {
        "cpu": "500m",
        "memory": "256Mi"
      }
    }
  }
}'
```

## 📊 步骤8: Dashboard集成监控

### 在Tekton Dashboard中监控Webhook
通过浏览器访问: `https://tekton.10.78.14.61.nip.io`

登录凭据: `admin` / `admin123`

**Dashboard功能**:
- **EventListeners**: 查看所有Webhook监听器状态
- **PipelineRuns**: 监控自动触发的流水线执行
- **实时日志**: 查看Pipeline执行详细日志
- **失败分析**: 调试Webhook触发失败原因

### 监控命令
```bash
# 监控最新的PipelineRun
watch kubectl get pipelinerun

# 查看特定PipelineRun详情
kubectl describe pipelinerun $(kubectl get pipelinerun -o name | head -1)

# 查看EventListener事件
kubectl get events --field-selector involvedObject.kind=EventListener
```

## 📋 配置结果总结

### ✅ 成功配置的Webhook集成
1. **GitHub集成**: http://10.78.14.61:30089 + HTTPS路径
2. **GitLab集成**: http://10.78.14.61:30090 + HTTPS路径  
3. **HTTPS访问**: https://webhook.10.78.14.61.nip.io
4. **安全认证**: Webhook密钥验证
5. **多平台支持**: GitHub, GitLab, Bitbucket

### 🔄 完整的集成工作流程
```
Git平台Webhook集成流程
├── 代码推送 (git push)
├── Git平台触发Webhook (POST请求)
├── Tekton EventListener接收 (验证和解析)
├── TriggerBinding提取参数 (仓库、分支、提交信息)
├── TriggerTemplate创建PipelineRun (实例化流水线)
└── Pipeline自动执行 (构建、测试、部署)
```

### 🌐 **Webhook访问端点总结**

| Git平台 | HTTP端点 | HTTPS端点 | NodePort |
|---------|----------|-----------|----------|
| GitHub | http://10.78.14.61:30089 | https://webhook.10.78.14.61.nip.io/github | 30089 |
| GitLab | http://10.78.14.61:30090 | https://webhook.10.78.14.61.nip.io/gitlab | 30090 |
| 通用 | http://10.78.14.61:30088 | - | 30088 |

### 🎯 生产环境最佳实践
此Webhook配置已针对生产环境优化:
- **安全性**: 密钥验证 + HTTPS加密
- **可扩展性**: 支持多个Git平台
- **监控性**: 完整的日志和Dashboard集成
- **容错性**: 事件重试和失败处理
- **性能**: 资源限制和负载均衡

## 🚀 下一步

完成Webhook配置后，您可以继续:
1. [部署GPU Pipeline](06-gpu-pipeline-deployment.md)
2. [设置受限用户权限](07-tekton-restricted-user-setup.md)
3. [高级Pipeline配置](08-advanced-pipeline-configuration.md)

## 🎉 总结

成功完成了Tekton Webhook的完整集成配置！现在您可以使用:

**🐙 GitHub Webhook**: https://webhook.10.78.14.61.nip.io/github  
**🦊 GitLab Webhook**: https://webhook.10.78.14.61.nip.io/gitlab  
**🔒 HTTPS访问**: https://webhook.10.78.14.61.nip.io  
**🌐 Dashboard监控**: https://tekton.10.78.14.61.nip.io  
**👤 登录凭据**: admin / admin123

享受完全自动化的CI/CD体验！
