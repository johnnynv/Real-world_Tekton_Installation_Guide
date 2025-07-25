# Tekton Webhook 触发入门教程

本教程将指导您如何配置和使用 Tekton Triggers 来实现 GitHub Webhook 自动触发 Pipeline 执行，基于 [johnnynv/tekton-poc](https://github.com/johnnynv/tekton-poc) 项目进行最佳实践演示。

## 📋 目录

1. [Tekton Triggers 概述](#tekton-triggers-概述)
2. [环境准备](#环境准备)
3. [核心组件详解](#核心组件详解)
4. [配置 GitHub Webhook](#配置-github-webhook)
5. [创建 Trigger 资源](#创建-trigger-资源)
6. [测试 Webhook 触发](#测试-webhook-触发)
7. [Dashboard 监控](#dashboard-监控)
8. [故障排查](#故障排查)
9. [进阶配置](#进阶配置)

## 🌟 Tekton Triggers 概述

### 什么是 Tekton Triggers？

Tekton Triggers 是 Tekton 生态系统的组件，用于根据外部事件（如 Git 提交、Pull Request）自动启动 Pipeline 执行。

### 核心组件

- **EventListener**: 监听 HTTP 事件的服务
- **TriggerBinding**: 从事件数据中提取参数
- **TriggerTemplate**: 定义如何创建 Tekton 资源
- **Interceptor**: 处理和过滤传入的事件

## 🔧 环境准备

### 1. 验证 Tekton Triggers 安装

```bash
# 检查 Tekton Triggers 组件
kubectl get pods -n tekton-pipelines | grep trigger

# 检查 Triggers 版本
tkn version | grep Triggers

# 查看 EventListener
kubectl get eventlistener -n tekton-pipelines
```

### 2. 克隆示例项目

```bash
# 克隆 tekton-poc 项目
git clone https://github.com/johnnynv/tekton-poc.git
cd tekton-poc

# 查看项目结构
tree examples/
```

### 3. 检查现有配置

```bash
# 查看现有的 EventListener
kubectl get eventlistener -n tekton-pipelines -o yaml

# 查看 Trigger 相关资源
kubectl get triggertemplate,triggerbinding -n tekton-pipelines
```

## 📦 核心组件详解

### EventListener 配置

查看当前的 EventListener 配置：

```bash
# 查看 EventListener 配置
cat examples/triggers/github-eventlistener.yaml
```

**配置说明**:
- **服务账户**: `tekton-triggers-sa` - 执行权限管理
- **拦截器**: GitHub 拦截器验证 webhook 签名
- **事件类型**: 只处理 "push" 事件
- **绑定引用**: 连接到 TriggerBinding 和 TriggerTemplate

### TriggerBinding 创建

创建 TriggerBinding 从 GitHub 事件中提取参数：

```yaml
# examples/triggers/github-trigger-binding.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: $(body.repository.clone_url)
  - name: git-revision
    value: $(body.head_commit.id)
  - name: git-repo-name
    value: $(body.repository.name)
```

### TriggerTemplate 创建

创建 TriggerTemplate 定义要启动的 Pipeline：

```yaml
# examples/triggers/github-trigger-template.yaml
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
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: webhook-pipeline-run-
      namespace: tekton-pipelines
      labels:
        app: tekton-webhook
        trigger: github-push
    spec:
      pipelineRef:
        name: git-clone-and-build-pipeline
      params:
      - name: repo-url
        value: $(tt.params.git-repo-url)
      - name: revision
        value: $(tt.params.git-revision)
      - name: repo-name
        value: $(tt.params.git-repo-name)
```

## 🔐 配置 GitHub Webhook

### 1. 创建 Webhook Secret

```bash
# 生成随机 token
WEBHOOK_SECRET=$(openssl rand -hex 20)
echo "Generated webhook secret: $WEBHOOK_SECRET"

# 创建 Kubernetes Secret
kubectl create secret generic github-webhook-secret \
  --from-literal=secretToken=$WEBHOOK_SECRET \
  -n tekton-pipelines

# 验证 Secret 创建
kubectl get secret github-webhook-secret -n tekton-pipelines
```

### 2. 获取 EventListener 服务地址

```bash
# 查看 EventListener 服务
kubectl get service -n tekton-pipelines | grep listener

# 如果使用 LoadBalancer
kubectl get service el-github-webhook-listener -n tekton-pipelines

# 如果使用 NodePort 或需要端口转发
kubectl port-forward service/el-github-webhook-listener -n tekton-pipelines 8080:8080
```

### 3. 在 GitHub 上配置 Webhook

1. 进入您的 GitHub 仓库 (johnnynv/tekton-poc)
2. 点击 **Settings** → **Webhooks** → **Add webhook**
3. 配置以下信息：
   - **Payload URL**: `http://your-eventlistener-url:8080`
   - **Content type**: `application/json`
   - **Secret**: 输入之前生成的 `$WEBHOOK_SECRET`
   - **Events**: 选择 "Just the push event"
   - **Active**: ✅ 勾选

## 🛠️ 创建 Trigger 资源

### 1. 创建 Git Clone Pipeline

```bash
# 创建用于 Git 克隆和构建的 Pipeline
cat << 'EOF' > examples/pipelines/git-clone-build-pipeline.yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: git-clone-and-build-pipeline
  namespace: tekton-pipelines
spec:
  description: |
    Pipeline triggered by GitHub webhook to clone and build
  params:
  - name: repo-url
    type: string
    description: Git repository URL
  - name: revision
    type: string
    description: Git revision to checkout
    default: main
  - name: repo-name
    type: string
    description: Repository name
  tasks:
  - name: fetch-repository
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.repo-url)
    - name: revision
      value: $(params.revision)
    workspaces:
    - name: output
      workspace: shared-data
  - name: build-project
    taskRef:
      name: hello-world
    runAfter:
    - fetch-repository
  workspaces:
  - name: shared-data
EOF
```

### 2. 应用所有 Trigger 资源

```bash
# 创建 TriggerBinding
kubectl apply -f - << 'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: $(body.repository.clone_url)
  - name: git-revision
    value: $(body.head_commit.id)
  - name: git-repo-name
    value: $(body.repository.name)
EOF

# 创建 TriggerTemplate
kubectl apply -f - << 'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: git-repo-name
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: webhook-pipeline-run-
      namespace: tekton-pipelines
      labels:
        app: tekton-webhook
        trigger: github-push
    spec:
      pipelineRef:
        name: hello-world-pipeline
      workspaces:
      - name: shared-data
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
EOF

# 应用现有的 EventListener
kubectl apply -f examples/triggers/github-eventlistener.yaml

# 验证资源创建
kubectl get triggertemplate,triggerbinding,eventlistener -n tekton-pipelines
```

## 🧪 测试 Webhook 触发

### 1. 手动触发测试

```bash
# 获取 EventListener 服务地址
EL_URL=$(kubectl get route el-github-webhook-listener -n tekton-pipelines -o jsonpath='{.spec.host}' 2>/dev/null || echo "localhost:8080")

# 如果使用端口转发
kubectl port-forward service/el-github-webhook-listener -n tekton-pipelines 8080:8080 &

# 发送测试 webhook 请求
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{"repository":{"clone_url":"https://github.com/johnnynv/tekton-poc.git","name":"tekton-poc"},"head_commit":{"id":"test123"}}' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | cut -d' ' -f2)" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/johnnynv/tekton-poc.git",
      "name": "tekton-poc"
    },
    "head_commit": {
      "id": "test123"
    }
  }'
```

### 2. 通过 Git Push 触发

```bash
# 在本地克隆的项目中进行修改
echo "# Test webhook trigger $(date)" >> README.md

# 提交并推送更改
git add README.md
git commit -m "Test webhook trigger"
git push origin main
```

### 3. 监控触发结果

```bash
# 查看新创建的 PipelineRun
tkn pipelinerun list -n tekton-pipelines | head -5

# 查看最新的 PipelineRun 日志
tkn pipelinerun logs --last -f -n tekton-pipelines

# 查看 EventListener pod 日志
kubectl logs -l app.kubernetes.io/name=eventlistener -n tekton-pipelines -f
```

## 📊 Dashboard 监控

### 访问 Dashboard

```bash
# 检查 Dashboard 状态
kubectl get pods -n tekton-pipelines | grep dashboard

# 端口转发访问 Dashboard
kubectl port-forward service/tekton-dashboard -n tekton-pipelines 9097:9097
```

打开浏览器访问 `http://localhost:9097`

### Dashboard 功能

1. **PipelineRuns 页面**
   - 查看 webhook 触发的运行记录
   - 实时监控执行状态
   - 筛选标签为 `trigger: github-push` 的运行

2. **Events 页面**
   - 查看 EventListener 接收的事件
   - 监控 webhook 触发历史

3. **Logs 查看**
   - 点击具体的 PipelineRun 查看详细日志
   - 查看每个 Task 的执行输出

## 🔧 故障排查

### 1. EventListener 问题

```bash
# 检查 EventListener pod 状态
kubectl get pods -l app.kubernetes.io/name=eventlistener -n tekton-pipelines

# 查看 EventListener 详细信息
kubectl describe eventlistener github-webhook-listener -n tekton-pipelines

# 查看 EventListener 日志
kubectl logs -l app.kubernetes.io/name=eventlistener -n tekton-pipelines
```

### 2. Webhook 验证问题

```bash
# 检查 webhook secret
kubectl get secret github-webhook-secret -n tekton-pipelines -o yaml

# 测试 webhook 签名验证
PAYLOAD='{"test":"data"}'
SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | cut -d' ' -f2)
echo "X-Hub-Signature-256: sha256=$SIGNATURE"
```

### 3. Pipeline 执行问题

```bash
# 查看失败的 PipelineRun
tkn pipelinerun list -n tekton-pipelines | grep Failed

# 查看具体错误信息
tkn pipelinerun describe <failed-pipelinerun> -n tekton-pipelines

# 查看相关事件
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp' | tail -10
```

### 4. 权限问题

```bash
# 检查 ServiceAccount
kubectl get serviceaccount tekton-triggers-sa -n tekton-pipelines

# 检查 ClusterRoleBinding
kubectl get clusterrolebinding | grep tekton-triggers

# 检查权限
kubectl auth can-i create pipelineruns --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa
```

## 🚀 进阶配置

### 1. 多事件类型支持

```yaml
# 支持多种 GitHub 事件
spec:
  triggers:
  - name: github-push-trigger
    interceptors:
    - ref:
        name: "github"
      params:
      - name: "eventTypes"
        value: ["push", "pull_request"]
```

### 2. 条件触发

```yaml
# 只有特定分支才触发
interceptors:
- ref:
    name: "cel"
  params:
  - name: "filter"
    value: "body.ref == 'refs/heads/main'"
```

### 3. 参数映射

```yaml
# 更多参数提取
spec:
  params:
  - name: git-branch
    value: $(body.ref)
  - name: git-author
    value: $(body.head_commit.author.name)
  - name: git-message
    value: $(body.head_commit.message)
```

### 4. 工作空间配置

```yaml
# 持久化工作空间
workspaces:
- name: shared-data
  persistentVolumeClaim:
    claimName: tekton-workspace-pvc
```

## 📝 实践练习

### 练习 1: 基础 Webhook 设置

1. 配置 GitHub webhook
2. 创建简单的触发流程
3. 验证推送代码后自动执行

### 练习 2: 多阶段 Pipeline

1. 创建包含构建、测试、部署的 Pipeline
2. 配置参数传递
3. 测试完整的 CI/CD 流程

### 练习 3: 条件执行

1. 设置分支过滤条件
2. 配置不同分支执行不同 Pipeline
3. 测试条件触发逻辑

## 🎉 总结

通过本教程，您已经学习了：

- ✅ Tekton Triggers 的核心概念和组件
- ✅ 配置 GitHub Webhook 自动触发 Pipeline
- ✅ 创建 EventListener、TriggerBinding 和 TriggerTemplate
- ✅ 在 Dashboard 中监控 webhook 触发的执行
- ✅ 故障排查和问题解决方法

### 🔗 相关资源

- [Tekton Triggers 官方文档](https://tekton.dev/docs/triggers/)
- [GitHub Webhook 文档](https://docs.github.com/en/developers/webhooks-and-events/webhooks)
- [Tekton POC 项目](https://github.com/johnnynv/tekton-poc)

接下来建议学习：
- 高级 Interceptor 配置
- 多云环境部署
- 安全最佳实践 