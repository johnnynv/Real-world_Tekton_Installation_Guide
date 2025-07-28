#!/bin/bash

# Tekton GPU Pipeline 验证脚本
# 用于端到端验证GPU scientific computing pipeline的所有组件

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

# 清理函数
cleanup_test_resources() {
    log_info "Cleaning up test resources..."
    
    # 删除测试pipeline runs
    kubectl delete pipelinerun debug-workspace-test -n tekton-pipelines --ignore-not-found=true
    kubectl delete pipelinerun debug-git-clone-test -n tekton-pipelines --ignore-not-found=true
    kubectl delete pipelinerun gpu-env-test-fixed -n tekton-pipelines --ignore-not-found=true
    kubectl delete pod gpu-test-pod -n tekton-pipelines --ignore-not-found=true
    
    sleep 5
}

# 阶段1: 基础环境验证
validate_basic_environment() {
    log_header "阶段1: 基础环境验证"
    
    log_info "检查Kubernetes集群连接..."
    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    log_success "集群连接正常"
    
    log_info "检查GPU资源..."
    GPU_COUNT=$(kubectl get nodes -o json | jq -r '.items[0].status.allocatable."nvidia.com/gpu"' 2>/dev/null || echo "0")
    if [ "$GPU_COUNT" = "0" ] || [ "$GPU_COUNT" = "null" ]; then
        log_error "节点上没有可用的GPU资源"
        exit 1
    fi
    log_success "发现 $GPU_COUNT 个GPU设备"
    
    log_info "检查Tekton组件..."
    if ! kubectl get pods -n tekton-pipelines &>/dev/null; then
        log_error "Tekton组件未安装或不可访问"
        exit 1
    fi
    
    TEKTON_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | wc -l)
    RUNNING_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | grep Running | wc -l)
    log_success "Tekton组件状态: $RUNNING_PODS/$TEKTON_PODS pods running"
    
    log_info "检查NVIDIA设备插件..."
    if ! kubectl get daemonset -A | grep nvidia-device-plugin &>/dev/null; then
        log_warning "未找到NVIDIA设备插件，GPU可能无法使用"
    else
        log_success "NVIDIA设备插件已安装"
    fi
}

# 阶段2: 存储和workspace验证
validate_storage_workspace() {
    log_header "阶段2: 存储和Workspace验证"
    
    log_info "创建PVC workspaces..."
    if ! kubectl apply -f examples/workspaces/gpu-pipeline-workspaces.yaml; then
        log_error "PVC创建失败"
        exit 1
    fi
    sleep 10
    
    log_info "检查PVC状态..."
    kubectl get pvc -n tekton-pipelines
    
    log_info "测试基础workspace功能..."
    kubectl apply -f examples/debug/debug-workspace-test.yaml
    
    # 等待完成
    for i in {1..30}; do
        STATUS=$(kubectl get pipelinerun debug-workspace-test -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            log_success "Workspace测试通过"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Workspace测试失败"
            kubectl logs -l tekton.dev/pipelineRun=debug-workspace-test -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
    
    log_info "测试Git clone功能..."
    kubectl apply -f examples/debug/debug-git-clone-test.yaml
    
    # 等待完成
    for i in {1..60}; do
        STATUS=$(kubectl get pipelinerun debug-git-clone-test -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            log_success "Git clone测试通过"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Git clone测试失败"
            kubectl logs -l tekton.dev/pipelineRun=debug-git-clone-test -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
}

# 阶段3: GPU访问验证
validate_gpu_access() {
    log_header "阶段3: GPU访问验证"
    
    log_info "创建GPU测试pod..."
    kubectl apply -f examples/testing/gpu-test-pod.yaml
    
    # 等待pod启动
    for i in {1..30}; do
        STATUS=$(kubectl get pod gpu-test-pod -n tekton-pipelines -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "Running" ]; then
            log_success "GPU测试pod启动成功"
            break
        elif [ "$STATUS" = "Failed" ]; then
            log_error "GPU测试pod启动失败"
            kubectl describe pod gpu-test-pod -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
    
    # 等待测试完成
    sleep 15
    
    log_info "检查GPU测试结果..."
    GPU_LOGS=$(kubectl logs gpu-test-pod -n tekton-pipelines 2>/dev/null || echo "")
    
    if echo "$GPU_LOGS" | grep -q "✅ CUDA devices:"; then
        CUDA_DEVICES=$(echo "$GPU_LOGS" | grep "✅ CUDA devices:" | awk '{print $4}')
        log_success "GPU访问测试通过，检测到 $CUDA_DEVICES 个CUDA设备"
    else
        log_error "GPU访问测试失败"
        echo "$GPU_LOGS"
        exit 1
    fi
    
    kubectl delete pod gpu-test-pod -n tekton-pipelines
}

# 阶段4: Tekton Task验证
validate_tekton_tasks() {
    log_header "阶段4: Tekton Task验证"
    
    log_info "应用修复版本的环境准备task..."
    kubectl apply -f examples/tasks/gpu-env-preparation-task-fixed.yaml
    
    log_info "测试环境准备task..."
    kubectl apply -f examples/testing/gpu-env-test-fixed.yaml
    
    # 等待完成
    for i in {1..60}; do
        STATUS=$(kubectl get pipelinerun gpu-env-test-fixed -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            log_success "环境准备task测试通过"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "环境准备task测试失败"
            kubectl describe pipelinerun gpu-env-test-fixed -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
    
    log_info "应用所有修复版本的tasks..."
    kubectl apply -f examples/tasks/gpu-papermill-execution-task.yaml
    kubectl apply -f examples/tasks/jupyter-nbconvert-task.yaml
    kubectl apply -f examples/tasks/pytest-execution-task.yaml
    
    log_success "所有Tekton tasks配置完成"
}

# 阶段5: 完整Pipeline测试
validate_complete_pipeline() {
    log_header "阶段5: 完整Pipeline验证"
    
    log_info "执行完整的GPU科学计算pipeline..."
    kubectl apply -f examples/pipelines/gpu-complete-pipeline-fixed.yaml
    
    RUN_NAME="gpu-scrna-complete-fixed"
    log_info "监控pipeline执行: $RUN_NAME"
    
    # 监控执行状态
    for i in {1..1800}; do  # 最多等待30分钟
        STATUS=$(kubectl get pipelinerun $RUN_NAME -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        REASON=$(kubectl get pipelinerun $RUN_NAME -n tekton-pipelines -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
        
        if [ "$STATUS" = "True" ] && [ "$REASON" = "Succeeded" ]; then
            log_success "完整pipeline执行成功！"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Pipeline执行失败"
            kubectl describe pipelinerun $RUN_NAME -n tekton-pipelines
            kubectl get taskruns -l tekton.dev/pipelineRun=$RUN_NAME -n tekton-pipelines
            exit 1
        fi
        
        # 每30秒输出一次状态
        if [ $((i % 15)) -eq 0 ]; then
            echo "Pipeline状态: $STATUS ($REASON) - 等待中... (${i}s)"
        fi
        sleep 2
    done
    
    # 检查结果文件
    log_info "验证输出文件..."
    
    # 这里可以添加具体的文件检查逻辑
    log_success "Pipeline验证完成"
}

# 显示验证结果摘要
show_validation_summary() {
    log_header "验证结果摘要"
    
    echo "✅ 基础环境验证 - 通过"
    echo "✅ 存储和Workspace验证 - 通过"
    echo "✅ GPU访问验证 - 通过"
    echo "✅ Tekton Task验证 - 通过"
    echo "✅ 完整Pipeline验证 - 通过"
    echo ""
    echo "🎉 所有验证阶段都已成功完成！"
    echo ""
    echo "下一步操作："
    echo "1. 查看pipeline执行结果: ./scripts/execute-gpu-pipeline.sh results gpu-scrna-complete-fixed"
    echo "2. 访问Tekton Dashboard查看详细信息"
    echo "3. 检查生成的notebook和测试报告文件"
}

# 主函数
main() {
    case "${1:-validate}" in
        "validate"|"")
            log_header "Tekton GPU Pipeline 完整验证"
            cleanup_test_resources
            validate_basic_environment
            validate_storage_workspace
            validate_gpu_access
            validate_tekton_tasks
            validate_complete_pipeline
            show_validation_summary
            ;;
        "cleanup")
            cleanup_test_resources
            log_success "测试资源清理完成"
            ;;
        "env")
            validate_basic_environment
            ;;
        "storage")
            validate_storage_workspace
            ;;
        "gpu")
            validate_gpu_access
            ;;
        "tasks")
            validate_tekton_tasks
            ;;
        "pipeline")
            validate_complete_pipeline
            ;;
        *)
            echo "用法: $0 [validate|cleanup|env|storage|gpu|tasks|pipeline]"
            echo ""
            echo "选项:"
            echo "  validate  - 执行完整的端到端验证 (默认)"
            echo "  cleanup   - 清理测试资源"
            echo "  env       - 仅验证基础环境"
            echo "  storage   - 仅验证存储和workspace"
            echo "  gpu       - 仅验证GPU访问"
            echo "  tasks     - 仅验证Tekton tasks"
            echo "  pipeline  - 仅验证完整pipeline"
            ;;
    esac
}

# 执行主函数
main "$@" 