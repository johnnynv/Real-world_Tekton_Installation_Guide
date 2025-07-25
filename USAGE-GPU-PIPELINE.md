# GPU 科学计算 Pipeline 使用说明 / GPU Scientific Computing Pipeline Usage Guide

## 🎯 概述 / Overview

本项目提供了完整的 GitHub Actions 到 Tekton GPU 科学计算工作流迁移解决方案。

This project provides a complete migration solution from GitHub Actions to Tekton for GPU scientific computing workflows.

## 📦 项目结构 / Project Structure

```
Real-world_Tekton_Installation_Guide/
├── examples/
│   ├── tasks/                           # Tekton Tasks 定义 / Tekton Tasks definitions
│   │   ├── gpu-env-preparation-task.yaml          # 环境准备 / Environment preparation
│   │   ├── gpu-papermill-execution-task.yaml      # GPU Notebook 执行 / GPU Notebook execution
│   │   ├── jupyter-nbconvert-task.yaml            # HTML 转换 / HTML conversion
│   │   └── pytest-execution-task.yaml             # 测试执行 / Test execution
│   ├── pipelines/                       # Tekton Pipelines 定义 / Tekton Pipelines definitions
│   │   └── gpu-scientific-computing-pipeline.yaml # 完整 Pipeline / Complete Pipeline
│   └── triggers/                        # Tekton Triggers 配置 / Tekton Triggers configuration
│       ├── gpu-pipeline-trigger-template.yaml     # 触发器模板 / Trigger template
│       └── gpu-pipeline-rbac.yaml                 # RBAC 配置 / RBAC configuration
├── scripts/                             # 部署脚本 / Deployment scripts
│   ├── zh/deploy-gpu-pipeline.sh                  # 中文部署脚本 / Chinese deployment script
│   └── en/deploy-gpu-pipeline.sh                  # 英文部署脚本 / English deployment script
├── docs/                                # 详细文档 / Detailed documentation
│   ├── zh/gpu-scientific-computing-pipeline-guide.md  # 中文指南 / Chinese guide
│   └── en/gpu-scientific-computing-pipeline-guide.md  # 英文指南 / English guide
└── USAGE-GPU-PIPELINE.md              # 本文件 / This file
```

## 🚀 快速开始 / Quick Start

### 1. 先决条件 / Prerequisites

- Kubernetes 集群 (1.24+) / Kubernetes cluster (1.24+)
- 配置了 GPU 的节点 / Nodes with GPU configuration
- kubectl 命令行工具 / kubectl command line tool
- Tekton Pipelines 已安装 / Tekton Pipelines installed

### 2. 一键部署 / One-Click Deployment

#### 中文环境 / Chinese Environment
```bash
# 克隆项目 / Clone the project
git clone <repository-url>
cd Real-world_Tekton_Installation_Guide

# 执行中文部署脚本 / Execute Chinese deployment script
chmod +x scripts/zh/deploy-gpu-pipeline.sh
./scripts/zh/deploy-gpu-pipeline.sh
```

#### 英文环境 / English Environment
```bash
# Clone the project
git clone <repository-url>
cd Real-world_Tekton_Installation_Guide

# Execute English deployment script
chmod +x scripts/en/deploy-gpu-pipeline.sh
./scripts/en/deploy-gpu-pipeline.sh
```

### 3. 验证部署 / Verify Deployment

```bash
# 检查所有组件 / Check all components
kubectl get tasks,pipelines,eventlisteners -n tekton-pipelines

# 查看 GPU Pipeline / View GPU Pipeline
kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines

# 检查 EventListener 服务 / Check EventListener service
kubectl get svc -n tekton-pipelines | grep eventlistener
```

## 📋 工作流说明 / Workflow Description

### 原始 GitHub Actions 工作流 / Original GitHub Actions Workflow

用户的原始工作流包含以下步骤：
Your original workflow includes the following steps:

1. 使用 docker-compose 启动 GPU 容器 / Start GPU container using docker-compose
2. 使用 papermill 执行 Jupyter Notebook (需要 GPU) / Execute Jupyter Notebook using papermill (requires GPU)
3. 使用 jupyter nbconvert 转换为 HTML / Convert to HTML using jupyter nbconvert
4. 下载测试仓库并执行 pytest / Download test repository and execute pytest
5. 生成 coverage.xml, pytest_results.xml, pytest_report.html / Generate coverage.xml, pytest_results.xml, pytest_report.html
6. 上传到 GitHub Artifacts / Upload to GitHub Artifacts

### 新的 Tekton Pipeline / New Tekton Pipeline

对应的 Tekton Tasks：
Corresponding Tekton Tasks:

| 原始步骤 / Original Step | Tekton Task | 描述 / Description |
|-------------------------|-------------|-------------------|
| Docker Compose + 环境配置 | `gpu-env-preparation` | 代码检出和环境准备 / Code checkout and environment preparation |
| Papermill 执行 | `gpu-papermill-execution` | GPU 加速的 Notebook 执行 / GPU-accelerated Notebook execution |
| Jupyter nbconvert | `jupyter-nbconvert` | Notebook 转 HTML / Notebook to HTML conversion |
| 测试执行 | `pytest-execution` | 下载测试仓库并运行 pytest / Download test repo and run pytest |
| 结果发布 | `publish-results` | 收集和发布所有结果 / Collect and publish all results |

## ⚙️ 配置说明 / Configuration Guide

### 1. GitHub Webhook 配置 / GitHub Webhook Configuration

部署完成后，您需要配置 GitHub Webhook：
After deployment, you need to configure GitHub Webhook:

1. 进入 GitHub 仓库设置 / Go to GitHub repository settings
2. 选择 "Webhooks" > "Add webhook" / Select "Webhooks" > "Add webhook"
3. 配置以下参数 / Configure the following parameters:

```
Payload URL: http://<EXTERNAL_IP>:8080
Content type: application/json
Secret: <使用部署脚本生成的密钥 / Use the secret generated by deployment script>
Events: Just the push event
```

### 2. 触发条件 / Trigger Conditions

Pipeline 会在以下情况自动触发：
The Pipeline will automatically trigger in the following cases:

- 推送到 `main` 或 `develop` 分支 / Push to `main` or `develop` branch
- 提交消息包含 `[gpu]` 或 `[notebook]` 标签 / Commit message contains `[gpu]` or `[notebook]` tags
- 修改 `notebooks/` 目录下的文件 / Modify files in the `notebooks/` directory

### 3. 参数配置 / Parameter Configuration

您可以通过以下参数自定义 Pipeline：
You can customize the Pipeline with the following parameters:

```yaml
params:
- name: git-repo-url              # 您的 Git 仓库 URL / Your Git repository URL
- name: notebook-path             # Notebook 文件路径 / Notebook file path
  default: "notebooks/01_scRNA_analysis_preprocessing.ipynb"
- name: gpu-count                 # 所需 GPU 数量 / Required GPU count
  default: "1"
- name: test-repo-url             # 测试仓库 URL / Test repository URL
  default: "https://github.com/NVIDIA-AI-Blueprints/blueprint-github-test.git"
```

## 🎮 手动执行 / Manual Execution

如果您想手动触发 Pipeline：
If you want to manually trigger the Pipeline:

```bash
# 创建 PipelineRun / Create PipelineRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: gpu-manual-run-
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: gpu-scientific-computing-pipeline
  params:
  - name: git-repo-url
    value: "https://github.com/your-org/your-repo.git"  # 替换为您的仓库 / Replace with your repository
  - name: git-revision
    value: "main"
  - name: notebook-path
    value: "notebooks/01_scRNA_analysis_preprocessing.ipynb"
  # ... 其他工作空间配置 / Other workspace configurations
EOF
```

## 📊 监控和日志 / Monitoring and Logs

### 查看执行状态 / View Execution Status

```bash
# 列出所有 Pipeline 运行 / List all Pipeline runs
kubectl get pipelineruns -n tekton-pipelines

# 查看特定运行详情 / View specific run details
kubectl describe pipelinerun <pipelinerun-name> -n tekton-pipelines

# 查看 Pod 状态 / View Pod status
kubectl get pods -n tekton-pipelines
```

### 查看日志 / View Logs

```bash
# GPU 执行任务日志 / GPU execution task logs
kubectl logs -f <gpu-papermill-pod> -n tekton-pipelines -c step-gpu-papermill-execute

# 测试执行日志 / Test execution logs
kubectl logs -f <pytest-pod> -n tekton-pipelines -c step-execute-tests

# 所有任务日志 / All task logs
kubectl logs -f <pod-name> -n tekton-pipelines
```

## 📋 输出文件 / Output Files

Pipeline 执行完成后，会生成以下文件：
After Pipeline execution completes, the following files will be generated:

1. `executed_notebook.ipynb` - 执行后的 Notebook / Executed Notebook
2. `executed_notebook.html` - HTML 格式报告 / HTML format report
3. `coverage.xml` - 代码覆盖率报告 / Code coverage report
4. `pytest_results.xml` - JUnit 格式测试结果 / JUnit format test results
5. `pytest_report.html` - HTML 格式测试报告 / HTML format test report

这些文件等同于原始 GitHub Actions 中上传到 Artifacts 的文件。
These files are equivalent to the files uploaded to Artifacts in the original GitHub Actions.

## 🔧 故障排除 / Troubleshooting

### 常见问题 / Common Issues

1. **GPU 调度失败** / **GPU Scheduling Failure**
   ```bash
   # 检查 GPU 节点 / Check GPU nodes
   kubectl get nodes -l accelerator=nvidia-tesla-gpu
   kubectl describe node <gpu-node-name>
   ```

2. **存储问题** / **Storage Issues**
   ```bash
   # 检查存储类 / Check storage classes
   kubectl get storageclass
   kubectl get pvc -n tekton-pipelines
   ```

3. **网络连接问题** / **Network Connection Issues**
   ```bash
   # 检查 EventListener 服务 / Check EventListener service
   kubectl get svc -n tekton-pipelines
   ```

### 日志收集 / Log Collection

详细的故障排除步骤请参考：
For detailed troubleshooting steps, please refer to:

- 中文指南：`docs/zh/gpu-scientific-computing-pipeline-guide.md`
- English Guide: `docs/en/gpu-scientific-computing-pipeline-guide.md`

## 📚 详细文档 / Detailed Documentation

更多详细信息，请查看：
For more detailed information, please check:

- **中文完整指南** / **Chinese Complete Guide**: `docs/zh/gpu-scientific-computing-pipeline-guide.md`
- **英文完整指南** / **English Complete Guide**: `docs/en/gpu-scientific-computing-pipeline-guide.md`

这些文档包含：
These documents include:

- 详细的架构设计 / Detailed architecture design
- 性能优化建议 / Performance optimization recommendations
- 最佳实践 / Best practices
- 完整的故障排除指南 / Complete troubleshooting guide

## 🆘 获取帮助 / Getting Help

如果您遇到问题：
If you encounter issues:

1. 检查详细文档中的故障排除部分 / Check the troubleshooting section in detailed documentation
2. 查看项目 Issues / Check project Issues
3. 联系维护团队 / Contact the maintenance team

## 📄 许可证 / License

请查看项目根目录的 LICENSE 文件。
Please see the LICENSE file in the project root directory. 