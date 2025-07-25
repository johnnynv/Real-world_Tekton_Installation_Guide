# Tekton CLI 入门教程

本教程将带您一步步了解 Tekton 的核心概念，并通过 `tkn` 命令行工具进行实践操作。

## 📋 目录

1. [环境准备](#环境准备)
2. [Tekton 核心概念](#tekton-核心概念)
3. [Task 基础操作](#task-基础操作)
4. [Pipeline 管道操作](#pipeline-管道操作)
5. [PipelineRun 执行管理](#pipelinerun-执行管理)
6. [Dashboard UI 查看](#dashboard-ui-查看)
7. [常用 CLI 命令](#常用-cli-命令)
8. [故障排查](#故障排查)

## 🔧 环境准备

### 1. 检查 Tekton 环境

```bash
# 检查 Tekton 命名空间
kubectl get namespaces | grep tekton

# 检查 Tekton 组件状态
kubectl get pods -n tekton-pipelines

# 检查 tkn CLI 版本
tkn version
```

### 2. 安装 tkn CLI 工具（如果未安装）

```bash
# 下载最新版本 tkn CLI
curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | \
  grep "browser_download_url.*Linux_x86_64" | \
  cut -d '"' -f 4 | xargs curl -LO

# 解压并安装
tar xzf tkn_*_Linux_x86_64.tar.gz
sudo mv tkn /usr/local/bin/
rm tkn_*_Linux_x86_64.tar.gz

# 验证安装
tkn version
```

## 📚 Tekton 核心概念

### Task（任务）
- **定义**: 最小的可执行单元，包含一系列步骤（steps）
- **特点**: 可重用，可参数化
- **用途**: 执行特定的操作，如构建、测试、部署

### Pipeline（管道）
- **定义**: 多个 Task 的有序集合
- **特点**: 定义任务间的依赖关系和执行顺序
- **用途**: 实现复杂的 CI/CD 工作流

### PipelineRun（管道运行）
- **定义**: Pipeline 的具体执行实例
- **特点**: 包含实际的参数值和运行状态
- **用途**: 触发和监控 Pipeline 的执行

### TaskRun（任务运行）
- **定义**: Task 的具体执行实例
- **特点**: 由 PipelineRun 自动创建或手动创建
- **用途**: 执行具体的任务并记录结果

## 🎯 Task 基础操作

### 1. 查看现有 Task

```bash
# 列出所有 Task
tkn task list

# 查看特定 Task 详情
tkn task describe hello-world

# 以 YAML 格式查看 Task
kubectl get task hello-world -n tekton-pipelines -o yaml
```

### 2. 创建和应用 Task

```bash
# 应用示例 Task
kubectl apply -f examples/tasks/hello-world-task.yaml

# 验证 Task 创建成功
tkn task list | grep hello-world
```

### 3. 运行 Task

```bash
# 手动运行 Task
tkn task start hello-world -n tekton-pipelines

# 查看 TaskRun 状态
tkn taskrun list

# 查看 TaskRun 详情
tkn taskrun describe <taskrun-name>

# 查看 TaskRun 日志
tkn taskrun logs <taskrun-name>
```

### 📊 在 Dashboard 中查看 Task

1. 访问 Tekton Dashboard（通常在 `http://localhost:9097`）
2. 导航到 "Tasks" 页面
3. 查看 Task 列表和详情
4. 点击 TaskRun 查看执行日志和状态

## 🔄 Pipeline 管道操作

### 1. 查看现有 Pipeline

```bash
# 列出所有 Pipeline
tkn pipeline list

# 查看 Pipeline 详情
tkn pipeline describe hello-world-pipeline

# 查看 Pipeline 的图形化表示
tkn pipeline describe hello-world-pipeline --graph
```

### 2. 创建和应用 Pipeline

```bash
# 应用示例 Pipeline
kubectl apply -f examples/pipelines/hello-world-pipeline.yaml

# 验证 Pipeline 创建成功
tkn pipeline list | grep hello-world
```

### 3. 运行 Pipeline

```bash
# 手动启动 Pipeline
tkn pipeline start hello-world-pipeline -n tekton-pipelines

# 或者使用交互式启动
tkn pipeline start hello-world-pipeline -n tekton-pipelines --use-pipelinerun-prefix

# 查看 Pipeline 的所有运行记录
tkn pipelinerun list
```

## 🚀 PipelineRun 执行管理

### 1. 查看 PipelineRun 状态

```bash
# 列出所有 PipelineRun
tkn pipelinerun list

# 查看特定 PipelineRun 详情
tkn pipelinerun describe <pipelinerun-name>

# 实时查看 PipelineRun 日志
tkn pipelinerun logs <pipelinerun-name> -f

# 查看 PipelineRun 的图形化状态
tkn pipelinerun describe <pipelinerun-name> --graph
```

### 2. 使用 PipelineRun 资源文件

```bash
# 应用 PipelineRun 资源文件
kubectl apply -f examples/pipelines/hello-world-pipeline-run.yaml

# 查看刚创建的 PipelineRun
kubectl get pipelinerun -n tekton-pipelines -l app=tekton-example
```

### 3. 管理 PipelineRun

```bash
# 取消正在运行的 PipelineRun
tkn pipelinerun cancel <pipelinerun-name>

# 删除 PipelineRun
tkn pipelinerun delete <pipelinerun-name>

# 删除所有已完成的 PipelineRun
tkn pipelinerun delete --all -n tekton-pipelines
```

## 🖥️ Dashboard UI 查看

### 访问 Dashboard

```bash
# 检查 Dashboard 服务状态
kubectl get service -n tekton-pipelines | grep dashboard

# 如果使用 port-forward 访问
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097
```

### Dashboard 功能导览

1. **Overview 概览**
   - 查看集群中所有 Tekton 资源的概况
   - 显示最近的运行状态和统计信息

2. **Pipelines 管道**
   - 浏览所有 Pipeline 定义
   - 查看 Pipeline 的图形化表示
   - 启动新的 PipelineRun

3. **PipelineRuns 管道运行**
   - 查看所有 PipelineRun 的状态
   - 实时监控执行进度
   - 查看详细的执行日志

4. **Tasks 任务**
   - 浏览所有 Task 定义
   - 查看 Task 的详细配置

5. **TaskRuns 任务运行**
   - 查看所有 TaskRun 的状态
   - 查看任务执行日志

## 🛠️ 常用 CLI 命令

### 查看命令

```bash
# 查看所有资源
tkn list

# 查看帮助信息
tkn --help
tkn task --help
tkn pipeline --help

# 以不同格式输出
tkn pipelinerun list -o json
tkn pipelinerun list -o yaml
```

### 日志命令

```bash
# 查看最新的 PipelineRun 日志
tkn pipelinerun logs --last

# 跟踪日志输出
tkn pipelinerun logs <name> -f

# 查看特定 Task 的日志
tkn pipelinerun logs <name> -t <task-name>
```

### 清理命令

```bash
# 删除所有已完成的运行
tkn pipelinerun delete --all

# 删除特定时间之前的运行
tkn pipelinerun delete --keep 5

# 强制删除
tkn pipelinerun delete <name> --force
```

## 🔍 故障排查

### 1. 检查资源状态

```bash
# 检查 Pod 状态
kubectl get pods -n tekton-pipelines

# 查看 Pod 详细信息
kubectl describe pod <pod-name> -n tekton-pipelines

# 查看 Pod 日志
kubectl logs <pod-name> -n tekton-pipelines
```

### 2. 常见问题

**Task/Pipeline 未找到**
```bash
# 检查资源是否存在
kubectl get task,pipeline -n tekton-pipelines

# 检查命名空间
tkn task list -n tekton-pipelines
```

**权限问题**
```bash
# 检查 ServiceAccount
kubectl get serviceaccount -n tekton-pipelines

# 检查 RBAC 配置
kubectl get rolebinding,clusterrolebinding | grep tekton
```

**执行失败**
```bash
# 查看失败的详细信息
tkn pipelinerun describe <failed-run-name>

# 查看相关事件
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'
```

## 📝 实践练习

### 练习 1: 创建简单 Task

1. 创建一个显示当前时间的 Task
2. 运行该 Task 并查看输出
3. 在 Dashboard 中查看执行结果

### 练习 2: 创建 Pipeline

1. 创建包含多个 Task 的 Pipeline
2. 设置 Task 之间的依赖关系
3. 运行 Pipeline 并监控执行过程

### 练习 3: 参数化配置

1. 为 Task 添加参数
2. 在 Pipeline 中传递参数
3. 通过 CLI 运行时提供参数值

## 🎉 总结

通过本教程，您已经学习了：

- ✅ Tekton 的核心概念（Task、Pipeline、PipelineRun）
- ✅ 使用 `tkn` CLI 工具管理 Tekton 资源
- ✅ 在 Dashboard UI 中查看和监控执行状态
- ✅ 常用的故障排查方法

接下来建议学习：
- Tekton Triggers 和 Webhook 集成
- 高级参数配置和资源管理
- 与 Git 和容器注册表的集成 