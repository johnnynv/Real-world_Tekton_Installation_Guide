#!/bin/bash

# 大数据集GPU Pipeline部署脚本
# 支持下载和处理大型单细胞RNA测序数据集

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo ""
    echo "=================================================================="
    echo "   $1"
    echo "=================================================================="
    echo ""
}

# 检查前置条件
check_prerequisites() {
    log_header "检查部署前置条件"
    
    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在PATH中"
        exit 1
    fi
    log_success "kubectl 可用"
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    log_success "Kubernetes集群连接正常"
    
    # 检查Tekton命名空间
    if ! kubectl get namespace tekton-pipelines &> /dev/null; then
        log_error "tekton-pipelines命名空间不存在"
        exit 1
    fi
    log_success "Tekton命名空间存在"
    
    # 检查GPU节点
    GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers | wc -l)
    if [ "$GPU_NODES" -eq 0 ]; then
        log_warning "未找到GPU节点 (标签: accelerator=nvidia-tesla-gpu)"
        log_warning "Pipeline可能无法正确调度到GPU节点"
    else
        log_success "找到 $GPU_NODES 个GPU节点"
    fi
}

# 检查存储需求
check_storage_requirements() {
    log_header "检查存储需求"
    
    # 获取节点存储信息
    log_info "检查节点存储容量..."
    kubectl top nodes 2>/dev/null || log_warning "无法获取节点资源使用情况"
    
    # 检查StorageClass
    if kubectl get storageclass local-path &> /dev/null; then
        log_success "local-path StorageClass 可用"
    else
        log_warning "local-path StorageClass 不存在，PVC可能无法创建"
    fi
    
    log_info "大数据集pipeline需要以下存储:"
    echo "  - 大数据集存储: 200Gi (用于存储下载的数据集)"
    echo "  - 数据集缓存: 100Gi (用于缓存，提高重复使用效率)"  
    echo "  - 处理工作区: 150Gi (用于notebook执行和结果)"
    echo "  - 总计需求: ~450Gi"
    echo ""
}

# 部署大数据集存储资源
deploy_large_dataset_storage() {
    log_header "部署大数据集存储资源"
    
    log_info "创建大数据集存储PVC..."
    if kubectl apply -f examples/workspaces/large-dataset-workspaces.yaml; then
        log_success "大数据集存储PVC创建成功"
    else
        log_error "大数据集存储PVC创建失败"
        exit 1
    fi
    
    # 等待PVC绑定
    log_info "等待PVC绑定..."
    sleep 5
    
    # 检查PVC状态
    log_info "检查PVC状态:"
    kubectl get pvc -n tekton-pipelines | grep -E "(large-dataset|dataset-cache|processing-workspace)" || true
    
    # 验证PVC绑定状态
    PENDING_PVCS=$(kubectl get pvc -n tekton-pipelines | grep -E "(large-dataset|dataset-cache|processing-workspace)" | grep Pending | wc -l)
    if [ "$PENDING_PVCS" -gt 0 ]; then
        log_warning "$PENDING_PVCS 个PVC仍处于Pending状态"
        log_warning "这可能会影响pipeline执行"
    else
        log_success "所有大数据集存储PVC已成功绑定"
    fi
}

# 部署任务定义
deploy_tasks() {
    log_header "部署任务定义"
    
    # 部署大数据集下载任务
    log_info "部署大数据集下载任务..."
    if kubectl apply -f examples/tasks/large-dataset-download-task.yaml; then
        log_success "大数据集下载任务部署成功"
    else
        log_error "大数据集下载任务部署失败"
        exit 1
    fi
    
    # 检查现有任务
    log_info "检查必需的任务是否存在:"
    REQUIRED_TASKS=("gpu-env-preparation-fixed" "gpu-papermill-execution" "jupyter-nbconvert" "pytest-execution")
    
    for task in "${REQUIRED_TASKS[@]}"; do
        if kubectl get task "$task" -n tekton-pipelines &> /dev/null; then
            log_success "任务 $task 存在"
        else
            log_error "必需的任务 $task 不存在"
            exit 1
        fi
    done
}

# 验证部署
verify_deployment() {
    log_header "验证部署"
    
    log_info "检查部署的资源:"
    
    # 检查任务
    echo "📋 任务列表:"
    kubectl get tasks -n tekton-pipelines | grep -E "(large-dataset|gpu-)" || true
    
    echo ""
    echo "💾 存储资源:"
    kubectl get pvc -n tekton-pipelines | grep -E "(large-dataset|dataset-cache|processing-workspace)" || true
    
    echo ""
    echo "🏷️  GPU节点信息:"
    kubectl get nodes -l accelerator=nvidia-tesla-gpu -o wide || log_warning "未找到标记的GPU节点"
}

# 显示使用说明
show_usage_instructions() {
    log_header "使用说明"
    
    cat << 'EOF'
大数据集GPU Pipeline已部署完成！

🚀 执行大数据集pipeline:
```bash
# 应用pipeline配置
kubectl apply -f examples/pipelines/gpu-original-notebook-with-download.yaml

# 监控执行状态
kubectl get pipelinerun gpu-original-notebook-with-download -n tekton-pipelines -w

# 查看详细状态
kubectl describe pipelinerun gpu-original-notebook-with-download -n tekton-pipelines
```

📊 自定义数据集下载:
```bash
# 修改pipeline参数以使用不同的数据集
# 编辑 examples/pipelines/gpu-original-notebook-with-download.yaml 中的参数:
#   - dataset-url: 数据集下载URL
#   - dataset-filename: 保存的文件名
#   - expected-dataset-size-mb: 预期文件大小(MB)
#   - download-timeout-minutes: 下载超时时间
#   - max-download-retries: 最大重试次数
```

🔍 监控和调试:
```bash
# 查看下载任务日志
kubectl logs -f -l tekton.dev/task=large-dataset-download -n tekton-pipelines

# 查看GPU执行任务日志  
kubectl logs -f -l tekton.dev/task=gpu-papermill-execution -n tekton-pipelines

# 检查存储使用情况
kubectl exec -it <pod-name> -n tekton-pipelines -- df -h
```

💾 存储管理:
```bash
# 清理缓存数据
kubectl exec -it <pod-name> -n tekton-pipelines -- rm -rf /workspace/datasets/cache/*

# 查看存储使用情况
kubectl get pvc -n tekton-pipelines
kubectl describe pvc large-dataset-storage -n tekton-pipelines
```

⚙️ 性能优化建议:
- 对于超大数据集(>10GB)，考虑增加存储配置
- 根据网络环境调整下载超时时间
- 启用缓存机制避免重复下载
- 监控GPU内存使用，必要时调整batch size

EOF
}

# 主函数
main() {
    case "${1:-deploy}" in
        "deploy"|"")
            log_header "开始部署大数据集GPU Pipeline"
            check_prerequisites
            check_storage_requirements
            deploy_large_dataset_storage
            deploy_tasks
            verify_deployment
            show_usage_instructions
            log_success "大数据集GPU Pipeline部署完成！"
            ;;
        "storage-only")
            check_prerequisites
            deploy_large_dataset_storage
            ;;
        "verify")
            verify_deployment
            ;;
        "clean")
            log_warning "清理大数据集相关资源..."
            kubectl delete -f examples/workspaces/large-dataset-workspaces.yaml --ignore-not-found=true
            kubectl delete task large-dataset-download -n tekton-pipelines --ignore-not-found=true
            log_success "清理完成"
            ;;
        *)
            echo "用法: $0 [deploy|storage-only|verify|clean]"
            echo ""
            echo "选项:"
            echo "  deploy       - 完整部署 (默认)"
            echo "  storage-only - 仅部署存储资源"
            echo "  verify       - 验证部署状态"
            echo "  clean        - 清理相关资源"
            ;;
    esac
}

# 执行主函数
main "$@" 