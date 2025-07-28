#!/bin/bash

# Tekton Triggers 清理脚本
# 清理所有相关的Tekton Triggers资源

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_header "Tekton Triggers 清理脚本"

# 1. 删除 GitHub webhook 相关资源
log_info "清理 GitHub webhook 相关资源..."

# 删除 EventListener
kubectl delete eventlistener github-webhook-listener -n tekton-pipelines --ignore-not-found=true
log_success "删除 EventListener: github-webhook-listener"

# 删除 TriggerTemplate
kubectl delete triggertemplate github-trigger-template -n tekton-pipelines --ignore-not-found=true
kubectl delete triggertemplate simple-trigger-template -n tekton-pipelines --ignore-not-found=true
log_success "删除 TriggerTemplate"

# 删除 TriggerBinding
kubectl delete triggerbinding github-trigger-binding -n tekton-pipelines --ignore-not-found=true
log_success "删除 TriggerBinding: github-trigger-binding"

# 删除 ClusterTriggerBinding
kubectl delete clustertriggerbinding github-push -n tekton-pipelines --ignore-not-found=true
log_success "删除 ClusterTriggerBinding: github-push"

# 2. 删除 Service 和 Ingress
log_info "清理 Service 和 Ingress 资源..."

kubectl delete svc github-webhook-listener-external -n tekton-pipelines --ignore-not-found=true
log_success "删除 Service: github-webhook-listener-external"

kubectl delete ingress github-webhook-ingress -n tekton-pipelines --ignore-not-found=true
log_success "删除 Ingress: github-webhook-ingress"

# 3. 删除 Secret
log_info "清理 Secret 资源..."

kubectl delete secret github-webhook-secret -n tekton-pipelines --ignore-not-found=true
log_success "删除 Secret: github-webhook-secret"

# 4. 删除 ServiceAccount 和 RBAC
log_info "清理 ServiceAccount 和 RBAC 资源..."

kubectl delete serviceaccount tekton-triggers-sa -n tekton-pipelines --ignore-not-found=true
kubectl delete clusterrole tekton-triggers-role --ignore-not-found=true
kubectl delete clusterrolebinding tekton-triggers-binding --ignore-not-found=true
log_success "删除 ServiceAccount 和 RBAC 资源"

# 5. 删除 Pipeline 和 Task
log_info "清理 Pipeline 和 Task 资源..."

kubectl delete pipeline github-webhook-pipeline -n tekton-pipelines --ignore-not-found=true
kubectl delete pipeline simple-hello-pipeline -n tekton-pipelines --ignore-not-found=true
kubectl delete task simple-hello-task -n tekton-pipelines --ignore-not-found=true
kubectl delete task git-clone-and-run -n tekton-pipelines --ignore-not-found=true
kubectl delete task run-python-script -n tekton-pipelines --ignore-not-found=true
log_success "删除 Pipeline 和 Task 资源"

# 6. 删除所有 PipelineRuns 和 TaskRuns
log_info "清理所有 PipelineRuns 和 TaskRuns..."

kubectl delete pipelinerun --all -n tekton-pipelines --ignore-not-found=true
kubectl delete taskrun --all -n tekton-pipelines --ignore-not-found=true
log_success "删除所有 PipelineRuns 和 TaskRuns"

# 7. 卸载 Tekton Triggers (可选)
read -p "是否要完全卸载 Tekton Triggers? (y/N): " uninstall_triggers
if [[ $uninstall_triggers =~ ^[Yy]$ ]]; then
    log_info "卸载 Tekton Triggers..."
    kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml --ignore-not-found=true
    kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml --ignore-not-found=true
    log_success "Tekton Triggers 已卸载"
else
    log_info "保留 Tekton Triggers 安装"
fi

print_header "清理完成"
log_success "所有 Tekton Triggers 相关资源已清理完毕"

echo ""
echo "您可以运行以下命令验证清理结果:"
echo "kubectl get eventlistener,triggertemplate,triggerbinding -n tekton-pipelines"
echo "kubectl get pods -n tekton-pipelines"
echo "kubectl get svc -n tekton-pipelines" 