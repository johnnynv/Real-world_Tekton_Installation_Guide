#!/bin/bash

set -euo pipefail

# GPU科学计算Pipeline部署脚本
# 用于将GitHub Actions工作流迁移到Tekton的一键部署脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_banner() {
    echo -e "${BLUE}"
    echo "========================================================"
    echo "   GPU 科学计算 Tekton Pipeline 部署脚本"
    echo "   从 GitHub Actions 迁移到 Tekton"
    echo "========================================================"
    echo -e "${NC}"
}

# 检查先决条件
check_prerequisites() {
    log_info "检查部署先决条件..."
    
    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未找到。请安装 kubectl。"
        exit 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群。请检查 kubeconfig 配置。"
        exit 1
    fi
    
    # 检查命名空间
    if ! kubectl get namespace tekton-pipelines &> /dev/null; then
        log_warning "tekton-pipelines 命名空间不存在，将创建..."
        kubectl create namespace tekton-pipelines
    fi
    
    # 检查Tekton安装
    if ! kubectl get crd pipelines.tekton.dev &> /dev/null; then
        log_error "Tekton Pipelines 未安装。请先安装 Tekton。"
        log_info "安装命令: kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml"
        exit 1
    fi
    
    # 检查Tekton Triggers
    if ! kubectl get crd eventlisteners.triggers.tekton.dev &> /dev/null; then
        log_warning "Tekton Triggers 未安装，将自动安装..."
        kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
        kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
    fi
    
    # 检查GPU支持
    GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$GPU_NODES" -eq 0 ]; then
        log_warning "未检测到 GPU 节点标签。请确保 GPU 节点已正确标记。"
        log_info "标记示例: kubectl label nodes <node-name> accelerator=nvidia-tesla-gpu"
    else
        log_success "检测到 $GPU_NODES 个 GPU 节点"
    fi
    
    log_success "先决条件检查完成"
}

# 部署RBAC配置
deploy_rbac() {
    log_info "部署 RBAC 配置..."
    
    local rbac_file="examples/triggers/gpu-pipeline-rbac.yaml"
    if [ ! -f "$rbac_file" ]; then
        log_error "RBAC 配置文件未找到: $rbac_file"
        exit 1
    fi
    
    # 生成随机的webhook密钥
    WEBHOOK_SECRET=$(openssl rand -base64 32)
    log_info "生成 GitHub webhook 密钥..."
    
    # 替换占位符
    sed "s|<BASE64_ENCODED_WEBHOOK_SECRET>|$(echo -n "$WEBHOOK_SECRET" | base64 -w 0)|g" "$rbac_file" | kubectl apply -f -
    
    log_success "RBAC 配置部署完成"
    log_info "请将以下 webhook 密钥配置到 GitHub 仓库设置中:"
    echo -e "${YELLOW}$WEBHOOK_SECRET${NC}"
}

# 部署Tasks
deploy_tasks() {
    log_info "部署 Tekton Tasks..."
    
    local tasks=(
        "examples/tasks/gpu-env-preparation-task.yaml"
        "examples/tasks/gpu-papermill-execution-task.yaml"
        "examples/tasks/jupyter-nbconvert-task.yaml"
        "examples/tasks/pytest-execution-task.yaml"
    )
    
    for task_file in "${tasks[@]}"; do
        if [ -f "$task_file" ]; then
            log_info "部署 Task: $(basename "$task_file")"
            kubectl apply -f "$task_file"
        else
            log_error "Task 文件未找到: $task_file"
            exit 1
        fi
    done
    
    log_success "所有 Tasks 部署完成"
}

# 部署Pipeline
deploy_pipeline() {
    log_info "部署 GPU 科学计算 Pipeline..."
    
    local pipeline_file="examples/pipelines/gpu-scientific-computing-pipeline.yaml"
    if [ ! -f "$pipeline_file" ]; then
        log_error "Pipeline 文件未找到: $pipeline_file"
        exit 1
    fi
    
    kubectl apply -f "$pipeline_file"
    log_success "Pipeline 部署完成"
}

# 部署Triggers
deploy_triggers() {
    log_info "部署 Tekton Triggers..."
    
    local trigger_file="examples/triggers/gpu-pipeline-trigger-template.yaml"
    if [ ! -f "$trigger_file" ]; then
        log_error "Trigger 文件未找到: $trigger_file"
        exit 1
    fi
    
    kubectl apply -f "$trigger_file"
    log_success "Triggers 部署完成"
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."
    
    # 检查Tasks
    log_info "检查 Tasks..."
    kubectl get tasks -n tekton-pipelines | grep -E "(gpu-env-preparation|gpu-papermill-execution|jupyter-nbconvert|pytest-execution)"
    
    # 检查Pipeline
    log_info "检查 Pipeline..."
    kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines
    
    # 检查EventListener
    log_info "检查 EventListener..."
    kubectl get eventlistener gpu-scientific-computing-eventlistener -n tekton-pipelines
    
    # 获取EventListener服务信息
    EVENTLISTENER_SERVICE=$(kubectl get svc -n tekton-pipelines -l eventlistener=gpu-scientific-computing-eventlistener -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "未找到")
    
    if [ "$EVENTLISTENER_SERVICE" != "未找到" ]; then
        EXTERNAL_IP=$(kubectl get svc "$EVENTLISTENER_SERVICE" -n tekton-pipelines -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
        EXTERNAL_PORT=$(kubectl get svc "$EVENTLISTENER_SERVICE" -n tekton-pipelines -o jsonpath='{.spec.ports[0].port}')
        
        log_success "EventListener 服务已创建"
        log_info "服务名称: $EVENTLISTENER_SERVICE"
        log_info "外部 IP: $EXTERNAL_IP"
        log_info "端口: $EXTERNAL_PORT"
        
        if [ "$EXTERNAL_IP" != "pending" ] && [ "$EXTERNAL_IP" != "" ]; then
            log_info "Webhook URL: http://$EXTERNAL_IP:$EXTERNAL_PORT"
        else
            log_warning "外部 IP 还在分配中，请稍后使用 'kubectl get svc -n tekton-pipelines' 查看"
        fi
    else
        log_warning "EventListener 服务未找到"
    fi
    
    log_success "部署验证完成"
}

# 创建测试PipelineRun
create_test_run() {
    log_info "创建测试 PipelineRun..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: gpu-test-run-
  namespace: tekton-pipelines
  labels:
    app: gpu-scientific-computing
    test: manual
spec:
  pipelineRef:
    name: gpu-scientific-computing-pipeline
  params:
  - name: git-repo-url
    value: "https://github.com/your-org/your-repo.git"  # 请替换为实际仓库
  - name: git-revision
    value: "main"
  - name: notebook-path
    value: "notebooks/01_scRNA_analysis_preprocessing.ipynb"
  - name: gpu-count
    value: "1"
  workspaces:
  - name: source-code-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
        storageClassName: fast-ssd
  - name: shared-artifacts-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 50Gi
        storageClassName: fast-ssd
  - name: gpu-cache-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: fast-nvme
  - name: test-execution-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
        storageClassName: fast-ssd
  timeout: "2h"
EOF
    
    log_success "测试 PipelineRun 已创建"
    log_info "使用以下命令查看运行状态:"
    echo "  kubectl get pipelineruns -n tekton-pipelines"
    echo "  kubectl logs -f -n tekton-pipelines <pipelinerun-name>"
}

# 显示后续配置步骤
show_next_steps() {
    echo -e "\n${GREEN}🎉 GPU 科学计算 Pipeline 部署完成！${NC}\n"
    
    echo -e "${BLUE}后续配置步骤:${NC}"
    echo "1. 在 GitHub 仓库中配置 Webhook:"
    echo "   - 进入仓库设置 > Webhooks"
    echo "   - 添加新的 Webhook"
    echo "   - Payload URL: http://YOUR_EXTERNAL_IP:8080"
    echo "   - Content type: application/json"
    echo "   - Secret: (使用上面生成的密钥)"
    echo "   - 选择 'Just the push event' 或 'Send me everything'"
    
    echo -e "\n2. 验证 GPU 节点配置:"
    echo "   kubectl get nodes -l accelerator=nvidia-tesla-gpu"
    echo "   kubectl describe node <gpu-node-name>"
    
    echo -e "\n3. 检查存储类配置:"
    echo "   kubectl get storageclass"
    echo "   kubectl get pv"
    
    echo -e "\n4. 监控 Pipeline 执行:"
    echo "   kubectl get pipelineruns -n tekton-pipelines"
    echo "   kubectl get pods -n tekton-pipelines"
    
    echo -e "\n5. 查看日志:"
    echo "   kubectl logs -f -n tekton-pipelines <pod-name>"
    
    echo -e "\n${YELLOW}注意事项:${NC}"
    echo "- 确保 GPU 节点有足够的资源"
    echo "- 根据实际环境调整存储类配置"
    echo "- 根据需要调整 GPU 内存和 CPU 限制"
    echo "- 定期监控 Pipeline 性能和资源使用"
}

# 主函数
main() {
    print_banner
    
    log_info "开始部署 GPU 科学计算 Tekton Pipeline..."
    
    check_prerequisites
    deploy_rbac
    deploy_tasks
    deploy_pipeline
    deploy_triggers
    verify_deployment
    
    # 询问是否创建测试运行
    echo -e "\n${YELLOW}是否创建测试 PipelineRun？(y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        create_test_run
    fi
    
    show_next_steps
    
    log_success "部署完成！"
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查日志并重试。"' ERR

# 执行主函数
main "$@" 