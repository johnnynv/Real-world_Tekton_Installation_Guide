# Tekton 入门教程指南

欢迎使用 Tekton 入门教程！本指南包含两个主要教程，帮助您从零开始掌握 Tekton 的核心功能。

## 📚 教程概览

### 1. [CLI 手动操作教程](01-tekton-cli-tutorial.md)
学习 Tekton 的核心概念和基础操作：
- 🎯 **目标**: 通过 `tkn` 命令行工具理解 Task、Pipeline、PipelineRun 等核心概念
- 🛠️ **内容**: 手动创建和执行 Tekton 资源
- 📊 **监控**: 使用 Dashboard UI 和 CLI 查看执行结果
- ⏱️ **学习时间**: 约 1-2 小时

### 2. [Webhook 触发教程](02-tekton-webhook-tutorial.md)
学习自动化 CI/CD 流程：
- 🌐 **目标**: 配置 GitHub Webhook 自动触发 Pipeline
- 🔧 **内容**: EventListener、TriggerBinding、TriggerTemplate 配置
- 🚀 **实践**: 基于 [johnnynv/tekton-poc](https://github.com/johnnynv/tekton-poc) 项目
- ⏱️ **学习时间**: 约 2-3 小时

## 🚀 快速开始

### 环境要求

- ✅ Kubernetes 集群已部署 Tekton Pipelines
- ✅ Tekton Dashboard 已安装
- ✅ `kubectl` 命令行工具可用
- ✅ 网络访问 GitHub（用于 Webhook 教程）

### 学习路径

#### 📖 建议的学习顺序

1. **第一步**: 阅读 [CLI 手动操作教程](01-tekton-cli-tutorial.md)
   - 理解 Tekton 基础概念
   - 练习手动创建和执行资源
   - 熟悉 CLI 工具和 Dashboard

2. **第二步**: 阅读 [Webhook 触发教程](02-tekton-webhook-tutorial.md)
   - 学习自动化触发机制
   - 配置 GitHub 集成
   - 实现完整的 CI/CD 流程

#### 🎯 核心概念学习重点

| 概念 | CLI 教程 | Webhook 教程 | 重要性 |
|------|----------|--------------|--------|
| Task | ⭐⭐⭐ | ⭐⭐ | 基础 |
| Pipeline | ⭐⭐⭐ | ⭐⭐⭐ | 核心 |
| PipelineRun | ⭐⭐⭐ | ⭐⭐⭐ | 核心 |
| EventListener | ⭐ | ⭐⭐⭐ | 进阶 |
| TriggerBinding | - | ⭐⭐⭐ | 进阶 |
| TriggerTemplate | - | ⭐⭐⭐ | 进阶 |

## 🛠️ 准备工作

### 1. 验证环境

```bash
# 检查 Tekton 安装
kubectl get namespaces | grep tekton

# 检查组件状态
kubectl get pods -n tekton-pipelines

# 安装 tkn CLI
curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | \
  grep "browser_download_url.*Linux_x86_64" | \
  cut -d '"' -f 4 | xargs curl -LO
tar xzf tkn_*_Linux_x86_64.tar.gz
sudo mv tkn /usr/local/bin/
```

### 2. 克隆示例项目

```bash
# 克隆本项目（如果还没有）
git clone <your-repo-url>
cd <your-repo-name>

# 查看示例文件
ls examples/
```

### 3. 访问 Dashboard

```bash
# 端口转发访问 Dashboard
kubectl port-forward service/tekton-dashboard -n tekton-pipelines 9097:9097

# 浏览器访问 http://localhost:9097
```

## 📝 实践练习

### 基础练习（CLI 教程配套）

1. **Hello World 任务**
   ```bash
   kubectl apply -f examples/tasks/hello-world-task.yaml
   tkn task start hello-world -n tekton-pipelines --showlog
   ```

2. **简单管道**
   ```bash
   kubectl apply -f examples/pipelines/hello-world-pipeline.yaml
   tkn pipeline start hello-world-pipeline -n tekton-pipelines --showlog
   ```

### 进阶练习（Webhook 教程配套）

1. **配置 Webhook**
   ```bash
   # 创建 webhook secret
   WEBHOOK_SECRET=$(openssl rand -hex 20)
   kubectl create secret generic github-webhook-secret \
     --from-literal=secretToken=$WEBHOOK_SECRET \
     -n tekton-pipelines
   ```

2. **部署触发器**
   ```bash
   kubectl apply -f examples/triggers/github-trigger-binding.yaml
   kubectl apply -f examples/triggers/github-trigger-template.yaml
   kubectl apply -f examples/triggers/github-eventlistener.yaml
   ```

## 🔍 监控和调试

### Dashboard 功能

1. **实时监控**
   - PipelineRuns 执行状态
   - TaskRuns 详细日志
   - 资源概览

2. **历史记录**
   - 执行历史查询
   - 失败原因分析
   - 性能统计

### CLI 调试命令

```bash
# 查看最新运行
tkn pipelinerun logs --last -f

# 查看特定运行
tkn pipelinerun describe <name>

# 查看事件
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'
```

## 🚨 常见问题

### 1. tkn 命令未找到
```bash
# 重新安装 tkn CLI
curl -LO https://github.com/tektoncd/cli/releases/latest/download/tkn_*_Linux_x86_64.tar.gz
```

### 2. Pipeline 执行失败
```bash
# 检查资源状态
kubectl get pods -n tekton-pipelines
tkn pipelinerun describe <failed-run>
```

### 3. Webhook 无法触发
```bash
# 检查 EventListener
kubectl logs -l app.kubernetes.io/name=eventlistener -n tekton-pipelines
```

## 📚 扩展学习

完成这些教程后，建议学习：

- 🔒 **安全配置**: ServiceAccount、RBAC、Secret 管理
- 🏗️ **高级 Pipeline**: 条件执行、并行任务、工作空间
- 🌐 **多环境部署**: 开发、测试、生产环境配置
- 🔧 **自定义 Task**: 创建可重用的任务模板
- 📊 **监控集成**: Prometheus、Grafana 集成

## 🤝 贡献

如果您发现教程中的问题或有改进建议：

1. 提交 Issue 报告问题
2. 提交 Pull Request 改进内容
3. 分享您的使用经验

## 📞 获取帮助

- 📖 [Tekton 官方文档](https://tekton.dev/docs/)
- 💬 [Tekton Slack 社区](https://tektoncd.slack.com/)
- 🐛 [GitHub Issues](https://github.com/tektoncd/pipeline/issues)

---

💡 **提示**: 建议先完成 CLI 教程建立基础概念，再进行 Webhook 教程的实践。每个教程都有详细的步骤说明和故障排查指南。 