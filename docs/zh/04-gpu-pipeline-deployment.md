# GPU 科学计算 Pipeline 部署指南

本指南详细介绍如何在 Tekton 上部署经过实战验证的 GPU 加速科学计算 Pipeline，包括 RMM (RAPIDS Memory Manager) 集成、错误处理和完整的 GitHub Actions 风格工作流。

## 📋 部署目标

- ✅ 部署经过验证的生产级 GPU Pipeline
- ✅ 配置 RMM 内存管理和错误处理  
- ✅ 实现完整的 8 步 GitHub Actions 风格工作流
- ✅ 支持轻量级和完整数据集两个版本
- ✅ 集成 GitHub 私有仓库访问
- ✅ 生成完整的测试报告和制品

## 🔧 前提条件

### 系统要求
- ✅ 已完成 [Tekton Webhook 配置](03-tekton-webhook-configuration.md)
- ✅ Kubernetes 集群支持 GPU (推荐: 8GB+ GPU 内存)
- ✅ NVIDIA GPU Operator 已安装
- ✅ 持久存储支持 (至少 50GB)
- ✅ GitHub 个人访问令牌 (用于私有仓库)

### GPU 环境验证
```bash
# 检查 GPU 节点
kubectl get nodes -l accelerator=nvidia-tesla-gpu

# 检查 GPU 资源
kubectl describe node <gpu-node-name> | grep nvidia.com/gpu

# 验证 GPU 可用性
kubectl run gpu-test --rm -i --tty --restart=Never \
  --image=nvidia/cuda:12.8-runtime-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi
```

## 🚀 步骤1：配置 GitHub 访问令牌

### 创建 GitHub Token Secret
```bash
# 创建用于私有仓库访问的 secret
kubectl create secret generic github-token \
  --from-literal=token=your-github-token-here \
  -n tekton-pipelines
```

### 验证 Secret
```bash
kubectl get secret github-token -n tekton-pipelines -o yaml
```

## 📦 步骤2：部署生产级 Pipeline 文件

项目已将所有文件整理到清晰的目录结构中：

```
examples/
├── production/          # 生产级文件
│   ├── pipelines/       # 主要工作流
│   ├── tasks/          # 核心任务定义
│   └── README.md       # 详细使用说明
└── troubleshooting/    # 调试和开发历史
    ├── pipelines/      # 各种迭代版本
    └── tasks/          # 调试任务
```

### 部署核心 Tasks
```bash
# 部署主要的 RMM 修复版本 task
kubectl apply -f examples/production/tasks/gpu-papermill-production-init-rmm-fixed.yaml

# 部署其他核心 tasks
kubectl apply -f examples/production/tasks/
```

### 部署 RMM 验证测试
```bash
# 首先部署简单的 RMM 验证测试
kubectl apply -f examples/production/pipelines/rmm-simple-verification-test.yaml

# 监控测试执行
kubectl get pipelinerun -n tekton-pipelines -w
```

## 🎯 步骤3：部署主要 GPU Workflows

### 3.1 部署轻量级版本（推荐用于测试）
```bash
# 部署 lite 版本 - 使用子采样数据集，内存友好
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml

# 监控执行
kubectl get pipelinerun gpu-real-8-step-workflow-lite -n tekton-pipelines -w
```

### 3.2 部署完整版本（生产环境）
```bash
# 部署 original 版本 - 使用完整数据集，需要更多内存
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-original.yaml

# 监控执行  
kubectl get pipelinerun gpu-real-8-step-workflow-original -n tekton-pipelines -w
```

## 📋 两个版本对比

| 特性 | Lite 版本 | Original 版本 |
|------|----------|--------------|
| **数据集大小** | 子采样 (50k 细胞, 10k 基因) | 完整数据集 |
| **GPU 内存需求** | 2-4GB | 8GB+ |
| **执行时间** | 快速 (~10-15 分钟) | 较慢 (~30-60 分钟) |
| **适用场景** | 测试, CI/CD, 演示 | 生产分析 |
| **成功率** | 高 (内存安全) | 中等 (可能遇到内存问题) |
| **生成文件** | 完整制品集 | 完整制品集 |

## 🔧 完整的 8 步工作流架构

两个版本都实现了相同的 8 步 GitHub Actions 风格工作流：

```
🔄 完整的 8 步 GPU 工作流:

1. 📋 Container Environment Setup
   - 设置环境变量
   - 初始化工作空间
   - 验证 GPU 可用性

2. 📂 Git Clone Blueprint Repository  
   - 克隆 single-cell-analysis-blueprint 仓库
   - 验证 notebooks 目录
   - 准备分析文件

3. 🧬 Papermill Notebook Execution (with RMM)
   - Init Container: 权限设置 + RMM 初始化
   - GPU 内存管理配置
   - Jupyter notebook 执行 (lite: 数据子采样)
   - 错误处理和日志记录

4. 🌐 Jupyter NBConvert to HTML
   - 将执行后的 notebook 转换为 HTML
   - 生成可视化报告
   - 准备测试输入

5. 📥 Download Test Repository  
   - 克隆 blueprint-github-test 私有仓库
   - 使用 GitHub token 认证
   - 准备测试环境

6. 🧪 Pytest Execution (with Coverage)
   - Poetry 环境设置
   - 安装测试依赖 (pytest-cov, pytest-html)
   - 执行测试套件
   - 生成覆盖率和 HTML 报告

7. 📦 Results Collection and Artifacts
   - 收集所有生成的文件
   - 组织制品结构
   - 验证文件完整性

8. 📊 Final Summary and Validation
   - 生成执行总结
   - 创建 GitHub Actions 风格的摘要
   - 列出所有制品
```

## 🔍 监控和日志查看

### 实时监控
```bash
# 查看 pipeline 状态
kubectl get pipelinerun -n tekton-pipelines

# 查看具体步骤
kubectl get pods -n tekton-pipelines | grep gpu-real-8-step-workflow

# 查看特定步骤日志
kubectl logs <pod-name> -n tekton-pipelines -f
```

### 查看生成的制品
```bash
# 进入共享存储查看文件
kubectl run temp-pod --rm -i --tty --restart=Never \
  --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"temp-pod","image":"busybox","command":["sh"],"volumeMounts":[{"mountPath":"/data","name":"shared-storage"}]}],"volumes":[{"name":"shared-storage","persistentVolumeClaim":{"claimName":"shared-pvc"}}]}}' \
  -n tekton-pipelines

# 在 pod 内查看文件
ls -la /data/
cat /data/STEP_SUMMARY_LITE.md  # 或 STEP_SUMMARY_ORIGINAL.md
```

## 📁 生成的制品文件

成功执行后会生成以下文件：

### Lite 版本制品
- **`output_analysis_lite.ipynb`** (4.3M) - 执行后的分析 notebook
- **`output_analysis_lite.html`** (4.6M) - HTML 格式分析报告  
- **`coverage_lite.xml`** - pytest 代码覆盖率报告
- **`pytest_results_lite.xml`** - JUnit 格式测试结果
- **`pytest_report_lite.html`** - HTML 格式测试报告
- **`papermill.log`** (20K) - Papermill 执行日志
- **`jupyter_nbconvert.log`** - HTML 转换日志
- **`pytest_output.log`** - pytest 执行日志
- **`STEP_SUMMARY_LITE.md`** - 完整工作流总结

### Original 版本制品  
类似于 lite 版本，但所有文件名不包含 `_lite` 后缀。

## 🔗 集成 GitHub Webhook（可选）

如需自动触发，可配置 GitHub webhook：

### 创建 TriggerTemplate
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: gpu-pipeline-trigger-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: pipeline-version
    default: "lite"
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: gpu-pipeline-run-
    spec:
      pipelineRef:
        name: gpu-real-8-step-workflow-\$(tt.params.pipeline-version)
      workspaces:
      - name: shared-storage
        volumeClaimTemplate:
          spec:
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 50Gi
EOF
```

## 🐛 故障排除

### 常见问题和解决方案

#### 1. RMM 初始化失败
```bash
# 检查 RMM 验证测试
kubectl logs <rmm-test-pod> -n tekton-pipelines

# 常见解决方案：确保 GPU 节点有足够内存
```

#### 2. GPU 内存不足
```bash
# 推荐使用 lite 版本
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml

# 或检查 GPU 内存使用
kubectl exec -it <gpu-pod> -n tekton-pipelines -- nvidia-smi
```

#### 3. GitHub 仓库访问失败
```bash
# 验证 GitHub token
kubectl get secret github-token -n tekton-pipelines

# 重新创建 token
kubectl delete secret github-token -n tekton-pipelines
kubectl create secret generic github-token --from-literal=token=new-token -n tekton-pipelines
```

#### 4. Poetry/依赖安装失败
工作流包含智能错误处理：
- 自动安装 curl 和必要工具
- Poetry 安装失败时自动切换到 pip
- 包含完整的依赖验证

### 调试资源
详细的故障排除文件和调试版本位于：
- `examples/troubleshooting/` - 包含开发历史和问题复现文件
- `examples/troubleshooting/README.md` - 详细的问题分类和解决方案

## ✅ 验证部署成功

### 1. 检查组件状态
```bash
# 检查主要 pipeline
kubectl get pipeline -n tekton-pipelines | grep gpu-real-8-step-workflow

# 检查最近的执行
kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp
```

### 2. 查看执行总结
```bash
# 查看 lite 版本总结
kubectl logs <final-summary-pod> -n tekton-pipelines | grep "🎉 ENTIRE 8-STEP"

# 确认所有步骤完成
kubectl logs <final-summary-pod> -n tekton-pipelines | grep "✅"
```

## 🎊 部署完成

恭喜！您已成功部署经过实战验证的 GPU 科学计算工作流：

### ✅ 已完成的部署
1. **🔐 GitHub 访问配置** - 私有仓库访问和认证
2. **🧠 RMM 内存管理** - GPU 内存优化和错误处理
3. **🔄 双版本支持** - Lite (测试) 和 Original (生产) 版本
4. **📋 完整工作流** - 8 步 GitHub Actions 风格流程
5. **🛡️ 错误恢复** - 智能错误处理和优雅降级
6. **📊 完整制品** - 所有分析结果和测试报告

### 🚀 下一步建议
1. **测试 Lite 版本** - 验证完整流程
2. **生产环境部署** - 使用 Original 版本进行实际分析
3. **性能优化** - 根据需要调整资源配置
4. **CI/CD 集成** - 配置自动触发机制

### 📚 更多资源
- **生产文件**: `examples/production/README.md`
- **故障排除**: `examples/troubleshooting/README.md`  
- **开发历史**: `examples/troubleshooting/` 中的迭代文件

现在您拥有了一个功能完整、经过实战验证的 GPU 科学计算 Pipeline！🎉 