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
- ✅ 已完成 [Tekton Webhook 配置](06-tekton-webhook-configuration.md)
- ✅ Kubernetes 集群支持 GPU (推荐: 8GB+ GPU 内存)
- ✅ NVIDIA GPU Operator 已安装
- ✅ 持久存储支持 (至少 50GB)
- ✅ GitHub 个人访问令牌 (用于私有仓库)

### GPU 环境验证
```bash
# 检查 GPU 节点和资源
kubectl get nodes -o wide
kubectl get nodes --show-labels | grep nvidia

# 检查 GPU 资源详情
kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') | grep nvidia.com/gpu

# 验证 GPU 可用性（注意：使用overrides语法）
kubectl run gpu-test --rm -i --tty --restart=Never \
  --image=nvidia/cuda:12.8-runtime-ubuntu22.04 \
  --overrides='{"spec":{"containers":[{"name":"gpu-test","image":"nvidia/cuda:12.8-runtime-ubuntu22.04","resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}' \
  -- nvidia-smi
```

## 🚀 步骤1：配置存储和服务账户

### 1.1 创建 Service Account 和 RBAC
```bash
# 创建 Pipeline 需要的 Service Account
cat > /tmp/tekton-pipeline-service-account.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-pipeline-service
  namespace: tekton-pipelines
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-pipeline-service-role
rules:
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "pipelineruns", "tasks", "taskruns"]
  verbs: ["get", "list", "create", "update", "patch", "watch"]
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "watch", "delete"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-pipeline-service-binding
subjects:
- kind: ServiceAccount
  name: tekton-pipeline-service
  namespace: tekton-pipelines
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-pipeline-service-role
EOF

kubectl apply -f /tmp/tekton-pipeline-service-account.yaml
```

### 1.2 配置存储 (⚠️ 关键步骤)
```bash
# 创建立即绑定的存储方案
cat > /tmp/immediate-storage.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: immediate-local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: tekton-workspace-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: immediate-local
  hostPath:
    path: /tmp/tekton-workspace
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: source-code-workspace
  namespace: tekton-pipelines
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: immediate-local
EOF

kubectl apply -f /tmp/immediate-storage.yaml

# 验证存储绑定
kubectl get pvc -n tekton-pipelines
kubectl get pv
```

### 1.3 配置 GitHub 访问令牌 (可选)
```bash
# 仅在需要私有仓库访问时创建
kubectl create secret generic github-token \
  --from-literal=token=your-github-token-here \
  -n tekton-pipelines
```

## 📦 步骤2：部署生产级 Tasks 和 Pipeline

### 2.1 部署核心 Tasks
```bash
# 部署所有生产级 tasks
kubectl apply -f examples/production/tasks/gpu-papermill-production-init-rmm-fixed.yaml
kubectl apply -f examples/production/tasks/safe-git-clone-task.yaml
kubectl apply -f examples/production/tasks/jupyter-nbconvert-complete.yaml
kubectl apply -f examples/production/tasks/large-dataset-download-task.yaml
kubectl apply -f examples/production/tasks/pytest-execution-task.yaml
kubectl apply -f examples/production/tasks/results-validation-cleanup-task.yaml

# 验证 tasks 部署
kubectl get tasks -n tekton-pipelines | grep -E "(gpu-papermill|safe-git|jupyter|large-dataset|pytest|results)"
```

### 2.2 部署默认版本Pipeline (完整数据集 + PCA修复)
```bash
# 部署默认版本 (完整数据集，已包含所有修复)
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow.yaml

# 监控执行状态
kubectl get pipelinerun gpu-real-8-step-workflow -n tekton-pipelines
kubectl get pods -n tekton-pipelines | grep gpu-real-8-step-workflow

# 查看实时日志
kubectl logs -f -n tekton-pipelines $(kubectl get pods -n tekton-pipelines | grep step3-papermill | awk '{print $1}') -c step-execute-notebook-original
```

## 🌐 Web访问配置

### 创建Artifact Web服务器
```bash
# 创建Web服务器用于浏览分析结果
cat > /tmp/artifact-web-server.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: artifact-web-server
  namespace: tekton-pipelines
  labels:
    app: artifact-server
spec:
  containers:
  - name: web-server
    image: python:3.9-slim
    command: ["python", "-m", "http.server", "8000", "--bind", "0.0.0.0"]
    workingDir: "/data"
    ports:
    - containerPort: 8000
    volumeMounts:
    - mountPath: "/data"
      name: shared-storage
  volumes:
  - name: shared-storage
    persistentVolumeClaim:
      claimName: source-code-workspace
---
apiVersion: v1
kind: Service
metadata:
  name: artifact-web-service
  namespace: tekton-pipelines
spec:
  selector:
    app: artifact-server
  ports:
  - port: 8000
    targetPort: 8000
    nodePort: 30800
  type: NodePort
EOF

kubectl apply -f /tmp/artifact-web-server.yaml
```

### 访问分析结果
```bash
# Web界面访问地址
🔗 主页面: http://10.34.2.129.nip.io:30800
🔗 分析报告: http://10.34.2.129.nip.io:30800/artifacts/output_analysis.html
🔗 Artifacts目录: http://10.34.2.129.nip.io:30800/artifacts/
🔗 总结报告: http://10.34.2.129.nip.io:30800/artifacts/STEP_SUMMARY.md
```

## 📊 监控和故障排除

### 查看执行状态
```bash
# 查看 Pipeline 状态
kubectl get pipelinerun -n tekton-pipelines

# 查看具体 TaskRun 状态
kubectl get taskrun -n tekton-pipelines | grep gpu-real-8-step-workflow

# 查看 Pod 执行状态
kubectl get pods -n tekton-pipelines | grep gpu-real-8-step-workflow

# 查看实时日志
kubectl logs -f -n tekton-pipelines <pod-name> -c <container-name>
```

### Pipeline架构选择

#### 方案1：多Task设计（当前默认）
- **优点**：模块化清晰，便于调试单个步骤
- **缺点**：每个Task需重新安装依赖，执行时间longer
- **适用**：开发调试阶段

#### 方案2：单Task设计（高效版本）
- **优点**：环境连续，一次安装全程可用，执行最快
- **缺点**：调试相对复杂，单点故障影响整个流程
- **适用**：生产环境

```bash
# 部署单Task高效版本
kubectl apply -f examples/production/pipelines/gpu-single-task-workflow.yaml
```

### 常见问题处理
如遇到问题，请参考 [troubleshooting.md](troubleshooting.md) 文档：
- 存储绑定问题
- 权限问题
- GPU 资源分配问题
- Task间环境隔离问题

## 🔧 8 步工作流概览

默认版本实现完整的 8 步 GitHub Actions 风格工作流：

```
🔄 完整的 8 步 GPU 工作流:

1. 📋 Container Environment Setup + 权限设置
2. 📂 Git Clone Blueprint Repository  
3. 🧬 Papermill Notebook Execution (with RMM + 完整数据集)
4. 🌐 Jupyter NBConvert to HTML
5. 📥 Download Test Repository (需要 GitHub token)

6. 🧪 Pytest Execution + Testing
7. 📦 Results Collection and Artifacts
8. 📊 Final Summary and Validation
```

### 预期执行时间
- **总时间**: 30-60 分钟 (取决于数据集大小和GPU性能)
- **关键步骤**: Step3 Papermill执行 (占用大部分时间)
- **监控命令**: `kubectl get pods -n tekton-pipelines | grep gpu-real-8-step-workflow`

## ✅ 验证成功

当看到以下状态时，表示部署成功：
```
✅ Step1: Container Environment Setup - Completed
✅ Step2: Git Clone Blueprint - Completed  
🏃‍♂️ Step3: Papermill Execution - Running (X/90 cells)
⏳ Step4-8: 等待队列中
```
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

### 生成的制品文件

成功执行后的主要输出：
- **`output_analysis.ipynb`** - 执行后的分析 notebook
- **`output_analysis.html`** - HTML 格式分析报告  
- **`coverage.xml`** - pytest 代码覆盖率报告
- **`pytest_results.xml`** - JUnit 格式测试结果
- **`STEP_SUMMARY.md`** - 完整工作流总结

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

### 1. 运行验证脚本（推荐）
```bash
# 运行完整验证脚本
chmod +x scripts/utils/verify-step4-gpu-pipeline-deployment.sh
./scripts/utils/verify-step4-gpu-pipeline-deployment.sh
```

验证脚本会自动检查：
- ✅ GPU 环境配置
- ✅ GitHub Token 配置
- ✅ GPU Pipeline 资源部署
- ✅ GPU Task 资源验证
- ✅ 持久存储配置
- ✅ Pipeline 执行历史
- ✅ GPU 可用性测试
- ✅ RBAC 权限配置

### 2. 手动检查组件状态（可选）
```bash
# 检查主要 pipeline
kubectl get pipeline -n tekton-pipelines | grep gpu-real-8-step-workflow

# 检查最近的执行
kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp
```

### 3. 查看执行总结
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