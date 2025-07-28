# GPU 科学计算 Pipeline 部署指南

本指南详细介绍如何在 Tekton 上部署 GPU 加速的科学计算 Pipeline，实现从 GitHub Actions 到 Tekton 的完整迁移。

## 📋 部署目标

- ✅ 部署 GPU 执行环境
- ✅ 配置科学计算 Tasks
- ✅ 创建完整的 GPU Pipeline
- ✅ 集成 GitHub Webhook 触发
- ✅ 验证端到端流程

## 🔧 前提条件

### 系统要求
- ✅ 已完成 [Tekton Webhook 配置](03-tekton-webhook-configuration.md)
- ✅ Kubernetes 集群支持 GPU
- ✅ NVIDIA GPU Operator 已安装
- ✅ 包含 Jupyter Notebook 的 GitHub 仓库

### GPU 环境验证
```bash
# 检查 GPU 节点
kubectl get nodes -l accelerator=nvidia-tesla-gpu

# 检查 GPU 资源
kubectl describe node <gpu-node-name> | grep nvidia.com/gpu

# 如果没有 GPU 标签，请添加：
kubectl label nodes <node-name> accelerator=nvidia-tesla-gpu
```

## 🚀 步骤1：部署 GPU 科学计算 Tasks

### 创建环境准备 Task
```bash
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: gpu-env-preparation
  namespace: tekton-pipelines
spec:
  description: Environment preparation for GPU scientific computing workflow
  params:
  - name: git-repo-url
    description: Git repository URL to clone
    type: string
  - name: git-revision
    description: Git revision to checkout
    type: string
    default: "main"
  workspaces:
  - name: source-code
    description: Workspace for source code checkout
    mountPath: /workspace/source
  - name: shared-storage
    description: Shared storage for artifacts
    mountPath: /workspace/shared
  results:
  - name: commit-sha
    description: SHA of the checked out commit
  - name: repo-status
    description: Repository checkout status
  steps:
  - name: git-clone
    image: alpine/git:latest
    env:
    - name: WORKSPACE_SOURCE_PATH
      value: \$(workspaces.source-code.path)
    - name: WORKSPACE_SHARED_PATH
      value: \$(workspaces.shared-storage.path)
    script: |
      #!/bin/sh
      set -eu
      
      echo "Starting GPU environment preparation..."
      echo "Repository URL: \$(params.git-repo-url)"
      echo "Revision: \$(params.git-revision)"
      
      # Create necessary directories
      mkdir -p "\${WORKSPACE_SOURCE_PATH}/source"
      mkdir -p "\${WORKSPACE_SHARED_PATH}/artifacts"
      mkdir -p "\${WORKSPACE_SHARED_PATH}/notebooks"
      
      # Clone repository
      cd "\${WORKSPACE_SOURCE_PATH}"
      git clone "\$(params.git-repo-url)" source
      cd source
      
      # Checkout specific revision
      if [ "\$(params.git-revision)" != "main" ]; then
        git checkout "\$(params.git-revision)"
      fi
      
      # Get commit information
      COMMIT_SHA=\$(git rev-parse HEAD)
      echo -n "\${COMMIT_SHA}" > "\$(results.commit-sha.path)"
      
      # Validate repository structure
      if [ -d "notebooks" ]; then
        echo "Found notebooks/ directory"
        ls -la notebooks/
      else
        echo "Warning: notebooks/ directory not found"
      fi
      
      # Copy files to shared workspace
      cp -r . "\${WORKSPACE_SHARED_PATH}/"
      echo -n "success" > "\$(results.repo-status.path)"
      echo "Environment preparation completed"
EOF
```

### 创建 GPU Papermill 执行 Task
```bash
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: gpu-papermill-execution
  namespace: tekton-pipelines
  labels:
    tekton.dev/gpu-required: "true"
spec:
  description: GPU-accelerated Papermill execution for scientific computing
  params:
  - name: notebook-path
    description: Path to the input notebook file
    type: string
    default: "notebooks/01_scRNA_analysis_preprocessing.ipynb"
  - name: output-notebook-name
    description: Name for the output executed notebook
    type: string
    default: "executed_notebook.ipynb"
  - name: container-image
    description: GPU-enabled container image
    type: string
    default: "nvcr.io/nvidia/rapidsai/notebooks:25.04-cuda12.8-py3.12"
  workspaces:
  - name: shared-storage
    description: Shared storage for source code and artifacts
    mountPath: /workspace/shared
  - name: gpu-cache
    description: GPU computation cache workspace
    mountPath: /workspace/gpu-cache
  results:
  - name: execution-status
    description: Status of notebook execution
  - name: execution-time
    description: Total execution time in seconds
  steps:
  - name: gpu-papermill-execute
    image: \$(params.container-image)
    computeResources:
      requests:
        nvidia.com/gpu: "1"
        memory: "16Gi"
        cpu: "4"
      limits:
        nvidia.com/gpu: "1"
        memory: "32Gi"
        cpu: "8"
    env:
    - name: NVIDIA_VISIBLE_DEVICES
      value: "all"
    - name: NVIDIA_DRIVER_CAPABILITIES
      value: "compute,utility"
    - name: WORKSPACE_SHARED_PATH
      value: \$(workspaces.shared-storage.path)
    - name: GPU_CACHE_PATH
      value: \$(workspaces.gpu-cache.path)
    script: |
      #!/bin/bash
      set -eu
      
      echo "Starting GPU-accelerated Papermill execution..."
      cd "\${WORKSPACE_SHARED_PATH}"
      
      # Record start time
      START_TIME=\$(date +%s)
      
      # Verify GPU availability
      if command -v nvidia-smi &> /dev/null; then
        echo "GPU available:"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
      fi
      
      # Verify notebook exists
      if [ ! -f "\$(params.notebook-path)" ]; then
        echo "Error: Notebook not found: \$(params.notebook-path)"
        exit 1
      fi
      
      # Create output directory
      mkdir -p "artifacts"
      mkdir -p "\${GPU_CACHE_PATH}/papermill"
      
      # Install papermill if needed
      pip install --quiet papermill ipykernel jupyter
      
      # Set up GPU environment
      export CUDA_VISIBLE_DEVICES=\${NVIDIA_VISIBLE_DEVICES}
      export CUPY_CACHE_DIR="\${GPU_CACHE_PATH}/cupy"
      export NUMBA_CACHE_DIR="\${GPU_CACHE_PATH}/numba"
      mkdir -p "\${CUPY_CACHE_DIR}" "\${NUMBA_CACHE_DIR}"
      
      # Execute notebook with papermill
      echo "Executing notebook with Papermill..."
      papermill "\$(params.notebook-path)" "artifacts/\$(params.output-notebook-name)" \\
        --log-output \\
        --log-level DEBUG \\
        --progress-bar \\
        --report-mode \\
        --kernel python3 \\
        2>&1 | tee "artifacts/papermill.log"
      
      PAPERMILL_EXIT_CODE=\${PIPESTATUS[0]}
      
      # Calculate execution time
      END_TIME=\$(date +%s)
      EXECUTION_TIME=\$((END_TIME - START_TIME))
      echo -n "\${EXECUTION_TIME}" > "\$(results.execution-time.path)"
      
      # Check results
      if [ \$PAPERMILL_EXIT_CODE -eq 0 ] && [ -f "artifacts/\$(params.output-notebook-name)" ]; then
        echo "Papermill execution completed successfully"
        echo -n "success" > "\$(results.execution-status.path)"
      else
        echo "Papermill execution failed"
        echo -n "failed" > "\$(results.execution-status.path)"
        exit 1
      fi
EOF
```

### 创建 Jupyter nbconvert Task
```bash
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: jupyter-nbconvert
  namespace: tekton-pipelines
spec:
  description: Convert executed notebooks to HTML format
  params:
  - name: input-notebook-name
    description: Name of the input notebook file
    type: string
    default: "executed_notebook.ipynb"
  - name: output-html-name
    description: Name for the output HTML file
    type: string
    default: "executed_notebook.html"
  workspaces:
  - name: shared-storage
    description: Shared storage for notebooks and HTML output
    mountPath: /workspace/shared
  results:
  - name: conversion-status
    description: Status of HTML conversion
  steps:
  - name: convert-to-html
    image: jupyter/minimal-notebook:latest
    env:
    - name: WORKSPACE_SHARED_PATH
      value: \$(workspaces.shared-storage.path)
    script: |
      #!/bin/bash
      set -eu
      
      echo "Starting Jupyter nbconvert HTML conversion..."
      cd "\${WORKSPACE_SHARED_PATH}"
      
      if [ ! -f "artifacts/\$(params.input-notebook-name)" ]; then
        echo "Error: Input notebook not found"
        exit 1
      fi
      
      # Install nbconvert
      pip install --quiet nbconvert
      
      # Convert to HTML
      jupyter nbconvert --to html \\
        "artifacts/\$(params.input-notebook-name)" \\
        --output "\$(params.output-html-name)" \\
        --output-dir "artifacts" \\
        --embed-images \\
        > "artifacts/jupyter_nbconvert.log" 2>&1
      
      if [ -f "artifacts/\$(params.output-html-name)" ]; then
        echo "HTML conversion completed successfully"
        echo -n "success" > "\$(results.conversion-status.path)"
      else
        echo "HTML conversion failed"
        echo -n "failed" > "\$(results.conversion-status.path)"
        exit 1
      fi
  
  - name: prepare-for-testing
    image: alpine:latest
    env:
    - name: WORKSPACE_SHARED_PATH
      value: \$(workspaces.shared-storage.path)
    script: |
      #!/bin/sh
      set -eu
      
      echo "Preparing HTML file for testing..."
      cd "\${WORKSPACE_SHARED_PATH}"
      
      mkdir -p "artifacts/staging"
      
      if [ -f "artifacts/\$(params.output-html-name)" ]; then
        cp "artifacts/\$(params.output-html-name)" "artifacts/staging/"
        echo "HTML file prepared for testing"
      else
        echo "Error: HTML file not found"
        exit 1
      fi
EOF
```

### 创建 PyTest 执行 Task
```bash
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: pytest-execution
  namespace: tekton-pipelines
spec:
  description: Execute PyTest against generated HTML reports
  params:
  - name: test-repo-url
    description: URL of the test framework repository
    type: string
    default: "https://github.com/NVIDIA-AI-Blueprints/blueprint-github-test.git"
  - name: html-input-file
    description: Name of the HTML file to test
    type: string
    default: "executed_notebook.html"
  - name: pytest-markers
    description: PyTest markers to run
    type: string
    default: "single_cell"
  workspaces:
  - name: shared-storage
    description: Shared storage for HTML files and test results
    mountPath: /workspace/shared
  - name: test-workspace
    description: Workspace for test repository
    mountPath: /workspace/test
  results:
  - name: test-status
    description: Overall test execution status
  - name: coverage-xml-path
    description: Path to coverage XML report
  - name: pytest-xml-path
    description: Path to pytest XML report
  - name: report-html-path
    description: Path to pytest HTML report
  steps:
  - name: download-test-repo
    image: alpine/git:latest
    env:
    - name: WORKSPACE_TEST_PATH
      value: \$(workspaces.test-workspace.path)
    script: |
      #!/bin/sh
      set -eu
      
      echo "Downloading test framework repository..."
      mkdir -p "\${WORKSPACE_TEST_PATH}"
      cd "\${WORKSPACE_TEST_PATH}"
      
      git clone --depth 1 \$(params.test-repo-url) test-framework
      cd test-framework
      
      if [ -d "input" ]; then
        echo "Found input directory"
      else
        mkdir -p input
      fi
  
  - name: prepare-test-inputs
    image: alpine:latest
    env:
    - name: WORKSPACE_SHARED_PATH
      value: \$(workspaces.shared-storage.path)
    - name: WORKSPACE_TEST_PATH
      value: \$(workspaces.test-workspace.path)
    script: |
      #!/bin/sh
      set -eu
      
      echo "Preparing test inputs..."
      cd "\${WORKSPACE_TEST_PATH}/test-framework"
      
      # Clear input directory
      rm -rf input/*
      
      # Copy HTML file to input directory
      if [ -f "\${WORKSPACE_SHARED_PATH}/artifacts/staging/\$(params.html-input-file)" ]; then
        cp "\${WORKSPACE_SHARED_PATH}/artifacts/staging/\$(params.html-input-file)" input/
        echo "HTML file copied to input directory"
      else
        echo "Error: HTML file not found"
        exit 1
      fi
  
  - name: execute-tests
    image: python:3.12-slim
    env:
    - name: WORKSPACE_TEST_PATH
      value: \$(workspaces.test-workspace.path)
    - name: WORKSPACE_SHARED_PATH
      value: \$(workspaces.shared-storage.path)
    workingDir: \$(workspaces.test-workspace.path)/test-framework
    script: |
      #!/bin/bash
      set -eu
      
      echo "Setting up test environment..."
      apt-get update && apt-get install -y curl git
      
      # Install Poetry
      curl -sSL https://install.python-poetry.org | python3 -
      export PATH="/root/.local/bin:\$PATH"
      
      # Install dependencies
      poetry install --no-dev
      
      # Execute tests
      echo "Running PyTest..."
      poetry run pytest -m \$(params.pytest-markers) \\
        --cov=./ \\
        --cov-report=xml:"\${WORKSPACE_SHARED_PATH}/artifacts/coverage.xml" \\
        --junitxml="\${WORKSPACE_SHARED_PATH}/artifacts/pytest_results.xml" \\
        --html="\${WORKSPACE_SHARED_PATH}/artifacts/pytest_report.html" \\
        --self-contained-html \\
        -v \\
        2>&1 | tee "\${WORKSPACE_SHARED_PATH}/artifacts/pytest_execution.log" || true
      
      # Save result paths
      echo -n "\${WORKSPACE_SHARED_PATH}/artifacts/coverage.xml" > "\$(results.coverage-xml-path.path)"
      echo -n "\${WORKSPACE_SHARED_PATH}/artifacts/pytest_results.xml" > "\$(results.pytest-xml-path.path)"
      echo -n "\${WORKSPACE_SHARED_PATH}/artifacts/pytest_report.html" > "\$(results.report-html-path.path)"
      echo -n "completed" > "\$(results.test-status.path)"
      
      echo "Test execution completed"
EOF
```

## 🔗 步骤2：创建完整的 GPU Pipeline

```bash
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: gpu-scientific-computing-pipeline
  namespace: tekton-pipelines
spec:
  description: GPU-accelerated scientific computing pipeline
  params:
  - name: git-repo-url
    description: Git repository URL
    type: string
  - name: git-revision
    description: Git revision
    type: string
    default: "main"
  - name: notebook-path
    description: Path to the notebook file
    type: string
    default: "notebooks/01_scRNA_analysis_preprocessing.ipynb"
  - name: test-repo-url
    description: URL of the test framework repository
    type: string
    default: "https://github.com/NVIDIA-AI-Blueprints/blueprint-github-test.git"
  
  workspaces:
  - name: source-code-workspace
    description: Workspace for source code
  - name: shared-artifacts-workspace
    description: Shared workspace for artifacts
  - name: gpu-cache-workspace
    description: GPU computation cache
  - name: test-execution-workspace
    description: Workspace for test execution
  
  results:
  - name: notebook-execution-time
    description: Time taken for notebook execution
    value: "\$(tasks.execute-notebook-gpu.results.execution-time)"
  - name: test-results-summary
    description: Summary of test execution results
    value: "\$(tasks.run-tests.results.test-status)"
  
  tasks:
  # Environment preparation
  - name: prepare-environment
    taskRef:
      name: gpu-env-preparation
    params:
    - name: git-repo-url
      value: \$(params.git-repo-url)
    - name: git-revision
      value: \$(params.git-revision)
    workspaces:
    - name: source-code
      workspace: source-code-workspace
    - name: shared-storage
      workspace: shared-artifacts-workspace
  
  # GPU notebook execution
  - name: execute-notebook-gpu
    taskRef:
      name: gpu-papermill-execution
    runAfter: ["prepare-environment"]
    params:
    - name: notebook-path
      value: \$(params.notebook-path)
    workspaces:
    - name: shared-storage
      workspace: shared-artifacts-workspace
    - name: gpu-cache
      workspace: gpu-cache-workspace
  
  # Convert to HTML
  - name: convert-to-html
    taskRef:
      name: jupyter-nbconvert
    runAfter: ["execute-notebook-gpu"]
    workspaces:
    - name: shared-storage
      workspace: shared-artifacts-workspace
  
  # Run tests
  - name: run-tests
    taskRef:
      name: pytest-execution
    runAfter: ["convert-to-html"]
    params:
    - name: test-repo-url
      value: \$(params.test-repo-url)
    workspaces:
    - name: shared-storage
      workspace: shared-artifacts-workspace
    - name: test-workspace
      workspace: test-execution-workspace
EOF
```

## 🎯 步骤3：集成 GitHub Webhook 触发

### 创建 GPU Pipeline TriggerTemplate
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
    description: Git repository URL
  - name: git-revision
    description: Git revision
  - name: git-repo-name
    description: Git repository name
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: gpu-pipeline-run-
      labels:
        tekton.dev/pipeline: gpu-scientific-computing-pipeline
        git.repository: \$(tt.params.git-repo-name)
    spec:
      pipelineRef:
        name: gpu-scientific-computing-pipeline
      params:
      - name: git-repo-url
        value: \$(tt.params.git-repo-url)
      - name: git-revision
        value: \$(tt.params.git-revision)
      workspaces:
      - name: source-code-workspace
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
      - name: shared-artifacts-workspace
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
      - name: gpu-cache-workspace
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
      - name: test-execution-workspace
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
EOF
```

### 创建 GPU EventListener
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: gpu-scientific-computing-eventlistener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: gpu-pipeline-trigger
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
        value: ["push"]
    
    # 条件过滤
    - ref:
        name: "cel"
      params:
      - name: "filter"
        value: >
          (body.ref == 'refs/heads/main' || 
           body.ref == 'refs/heads/develop') &&
          (body.head_commit.message.contains('[gpu]') ||
           body.head_commit.message.contains('[notebook]') ||
           body.head_commit.modified.exists(f, f.contains('notebooks/')) ||
           body.head_commit.added.exists(f, f.contains('notebooks/')))
    
    bindings:
    - ref: github-trigger-binding
    
    template:
      ref: gpu-pipeline-trigger-template
EOF
```

## ✅ 验证完整部署

### 1. 检查所有组件状态
```bash
# 检查 Tasks
kubectl get tasks -n tekton-pipelines | grep gpu

# 检查 Pipeline
kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines

# 检查 EventListener
kubectl get eventlistener gpu-scientific-computing-eventlistener -n tekton-pipelines

# 获取 EventListener 访问地址
kubectl get svc -n tekton-pipelines | grep gpu-scientific-computing-eventlistener
```

### 2. 手动测试 Pipeline
```bash
# 创建测试 PipelineRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: gpu-manual-test-
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: gpu-scientific-computing-pipeline
  params:
  - name: git-repo-url
    value: "https://github.com/your-username/your-repo.git"  # 替换为您的仓库
  - name: git-revision
    value: "main"
  workspaces:
  - name: source-code-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
  - name: shared-artifacts-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
  - name: gpu-cache-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
  - name: test-execution-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
EOF
```

### 3. 监控执行进度
```bash
# 查看 PipelineRun 状态
kubectl get pipelineruns -n tekton-pipelines -w

# 查看具体任务状态
kubectl get taskruns -n tekton-pipelines

# 查看实时日志
kubectl logs -f <pod-name> -n tekton-pipelines
```

### 4. Dashboard 验证
在 Tekton Dashboard 中验证：
- ✅ Pipelines 页面显示 GPU Pipeline
- ✅ PipelineRuns 页面显示执行历史
- ✅ TaskRuns 页面显示各个任务状态
- ✅ 可以查看 GPU 任务的实时日志

## 🎉 端到端验证

### 触发完整流程
```bash
# 在您的项目仓库中提交代码
echo "Test GPU pipeline integration" >> README.md
git add README.md
git commit -m "Test GPU scientific computing pipeline [gpu]"
git push origin main
```

### 验证生成的文件
Pipeline 执行完成后，应生成以下文件：
- ✅ `executed_notebook.ipynb` - 执行后的 Notebook
- ✅ `executed_notebook.html` - HTML 格式报告
- ✅ `coverage.xml` - 代码覆盖率报告
- ✅ `pytest_results.xml` - JUnit 格式测试结果
- ✅ `pytest_report.html` - HTML 格式测试报告

## 🔧 故障排除

### GPU 调度问题
```bash
# 检查 GPU 节点
kubectl get nodes -l accelerator=nvidia-tesla-gpu

# 检查 GPU 资源
kubectl describe node <gpu-node-name> | grep nvidia.com/gpu

# 查看 GPU Pod 调度
kubectl get pods -n tekton-pipelines -o wide | grep gpu
```

### Pipeline 执行失败
```bash
# 查看 Pipeline 状态
kubectl describe pipelinerun <pipeline-run-name> -n tekton-pipelines

# 查看失败的 Task 日志
kubectl logs <failed-pod-name> -n tekton-pipelines

# 检查工作空间配置
kubectl get pvc -n tekton-pipelines
```

## 📊 性能监控

### GPU 使用率监控
```bash
# 在 GPU 执行期间查看使用率
kubectl exec -it <gpu-pod-name> -n tekton-pipelines -- nvidia-smi

# 查看 GPU 内存使用
kubectl top pod <gpu-pod-name> -n tekton-pipelines --containers
```

## 🎊 部署完成

恭喜！您已成功完成从 GitHub Actions 到 Tekton GPU 科学计算工作流的完整迁移：

1. ✅ **Tekton 核心组件** - 安装和配置完成
2. ✅ **Tekton Triggers** - 事件驱动机制就绪
3. ✅ **GitHub Webhooks** - 自动触发配置完成
4. ✅ **GPU Pipeline** - 科学计算工作流部署成功

现在每次推送代码到 GitHub，都会自动触发 GPU 加速的科学计算流程，生成与原 GitHub Actions 相同的输出文件！ 