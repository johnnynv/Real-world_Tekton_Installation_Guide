#!/bin/bash

# Tekton 核心基础设施清理脚本 - 阶段一
# 清理 Ingress Controller + Tekton Pipelines + Dashboard

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
TEKTON_NAMESPACE="tekton-pipelines"
INGRESS_NAMESPACE="ingress-nginx"
NODE_IP="10.117.8.154"
TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_separator() {
    echo -e "${CYAN}----------------------------------------${NC}"
}

# 检查先决条件
check_prerequisites() {
    log_step "检查先决条件..."
    
    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在 PATH 中"
        exit 1
    fi
    
    # 检查 helm
    if ! command -v helm &> /dev/null; then
        log_warning "helm 未安装，将跳过 Helm 相关清理"
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    log_success "先决条件检查通过"
}

# 显示清理计划
show_cleanup_plan() {
    print_header "清理计划"
    
    log_info "即将清理以下组件:"
    log_info "  🗑️  测试资源 (PipelineRun, Pipeline, Task)"
    log_info "  🗑️  Tekton Dashboard Ingress"
    log_info "  🗑️  Tekton Dashboard"
    log_info "  🗑️  Tekton Pipelines"
    log_info "  🗑️  Nginx Ingress Controller"
    log_info "  🗑️  IngressClass"
    log_info "  🗑️  命名空间和配置"
    echo
    
    log_warning "⚠️  这将完全删除所有 Tekton 核心组件和配置！"
    echo
    
    read -p "确认继续清理？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "清理已取消"
        exit 0
    fi
}

# 清理测试资源
cleanup_test_resources() {
    print_header "清理测试资源"
    
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        log_step "删除测试 PipelineRuns..."
        kubectl delete pipelinerun --all -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        
        log_step "删除测试 Pipeline..."
        kubectl delete pipeline hello-pipeline -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        
        log_step "删除测试 Task..."
        kubectl delete task hello-world -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        
        log_success "测试资源清理完成"
    else
        log_info "Tekton 命名空间不存在，跳过测试资源清理"
    fi
}

# 清理 Tekton Dashboard Ingress
cleanup_dashboard_ingress() {
    print_header "清理 Dashboard Ingress"
    
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        log_step "删除 Tekton Dashboard Ingress..."
        kubectl delete ingress tekton-dashboard -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        
        log_step "删除网络策略..."
        kubectl delete networkpolicy tekton-dashboard-access -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        
        log_success "Dashboard Ingress 清理完成"
    else
        log_info "Tekton 命名空间不存在，跳过 Ingress 清理"
    fi
}

# 清理 Tekton Dashboard
cleanup_tekton_dashboard() {
    print_header "清理 Tekton Dashboard"
    
    log_step "删除 Tekton Dashboard..."
    if curl -s https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml > /tmp/tekton-dashboard.yaml; then
        kubectl delete -f /tmp/tekton-dashboard.yaml --ignore-not-found=true
        rm -f /tmp/tekton-dashboard.yaml
        log_success "Tekton Dashboard 删除完成"
    else
        log_warning "无法下载 Dashboard 清单，尝试手动清理..."
        kubectl delete deployment tekton-dashboard -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        kubectl delete service tekton-dashboard -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        kubectl delete configmap tekton-dashboard-config -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        kubectl delete serviceaccount tekton-dashboard -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        log_success "Tekton Dashboard 手动清理完成"
    fi
}

# 清理 Tekton Pipelines
cleanup_tekton_pipelines() {
    print_header "清理 Tekton Pipelines"
    
    log_step "删除 Tekton Pipelines..."
    if curl -s https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml > /tmp/tekton-pipelines.yaml; then
        kubectl delete -f /tmp/tekton-pipelines.yaml --ignore-not-found=true
        rm -f /tmp/tekton-pipelines.yaml
        log_success "Tekton Pipelines 删除完成"
    else
        log_warning "无法下载 Pipelines 清单，尝试手动清理..."
        kubectl delete deployment tekton-pipelines-controller -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        kubectl delete deployment tekton-pipelines-webhook -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        kubectl delete service tekton-pipelines-controller -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        kubectl delete service tekton-pipelines-webhook -n ${TEKTON_NAMESPACE} --ignore-not-found=true
        log_success "Tekton Pipelines 手动清理完成"
    fi
}

# 清理 Nginx Ingress Controller
cleanup_ingress_controller() {
    print_header "清理 Nginx Ingress Controller"
    
    if command -v helm &> /dev/null; then
        log_step "使用 Helm 卸载 Nginx Ingress Controller..."
        if helm list -n ${INGRESS_NAMESPACE} | grep -q ingress-nginx; then
            helm uninstall ingress-nginx -n ${INGRESS_NAMESPACE}
            log_success "Nginx Ingress Controller 卸载完成"
        else
            log_info "未找到 Helm 安装的 Ingress Controller"
        fi
    else
        log_warning "Helm 不可用，跳过 Helm 卸载"
    fi
    
    log_step "清理 Ingress Controller 残留资源..."
    # 删除可能的手动安装资源
    kubectl delete deployment ingress-nginx-controller -n ${INGRESS_NAMESPACE} --ignore-not-found=true
    kubectl delete service ingress-nginx-controller -n ${INGRESS_NAMESPACE} --ignore-not-found=true
    kubectl delete configmap ingress-nginx-controller -n ${INGRESS_NAMESPACE} --ignore-not-found=true
    kubectl delete serviceaccount ingress-nginx -n ${INGRESS_NAMESPACE} --ignore-not-found=true
    
    log_success "Ingress Controller 清理完成"
}

# 清理 IngressClass
cleanup_ingress_class() {
    print_header "清理 IngressClass"
    
    log_step "删除 IngressClass..."
    kubectl delete ingressclass nginx --ignore-not-found=true
    
    log_success "IngressClass 清理完成"
}

# 清理 RBAC 资源
cleanup_rbac_resources() {
    print_header "清理 RBAC 资源"
    
    log_step "删除 ClusterRole 和 ClusterRoleBinding..."
    # Tekton Pipelines RBAC
    kubectl delete clusterrole tekton-pipelines-controller-cluster-access --ignore-not-found=true
    kubectl delete clusterrole tekton-pipelines-controller-tenant-access --ignore-not-found=true
    kubectl delete clusterrole tekton-pipelines-webhook-cluster-access --ignore-not-found=true
    kubectl delete clusterrolebinding tekton-pipelines-controller-cluster-access --ignore-not-found=true
    kubectl delete clusterrolebinding tekton-pipelines-controller-tenant-access --ignore-not-found=true
    kubectl delete clusterrolebinding tekton-pipelines-webhook-cluster-access --ignore-not-found=true
    
    # Tekton Dashboard RBAC
    kubectl delete clusterrole tekton-dashboard-minimal --ignore-not-found=true
    kubectl delete clusterrolebinding tekton-dashboard-minimal --ignore-not-found=true
    
    # Ingress Controller RBAC
    kubectl delete clusterrole ingress-nginx --ignore-not-found=true
    kubectl delete clusterrolebinding ingress-nginx --ignore-not-found=true
    
    log_success "RBAC 资源清理完成"
}

# 清理命名空间
cleanup_namespaces() {
    print_header "清理命名空间"
    
    log_step "删除 Tekton 命名空间..."
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${TEKTON_NAMESPACE}
        log_info "等待 ${TEKTON_NAMESPACE} 命名空间完全删除..."
        while kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; do
            log_info "等待 ${TEKTON_NAMESPACE} 命名空间删除..."
            sleep 5
        done
        log_success "Tekton 命名空间删除完成"
    else
        log_info "Tekton 命名空间不存在"
    fi
    
    log_step "删除 Ingress 命名空间..."
    if kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${INGRESS_NAMESPACE}
        log_info "等待 ${INGRESS_NAMESPACE} 命名空间完全删除..."
        while kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; do
            log_info "等待 ${INGRESS_NAMESPACE} 命名空间删除..."
            sleep 5
        done
        log_success "Ingress 命名空间删除完成"
    else
        log_info "Ingress 命名空间不存在"
    fi
}

# 清理 CRD (Custom Resource Definitions)
cleanup_crds() {
    print_header "清理 CRD 资源"
    
    log_step "删除 Tekton CRDs..."
    kubectl delete crd clustertasks.tekton.dev --ignore-not-found=true
    kubectl delete crd conditions.tekton.dev --ignore-not-found=true
    kubectl delete crd pipelines.tekton.dev --ignore-not-found=true
    kubectl delete crd pipelineruns.tekton.dev --ignore-not-found=true
    kubectl delete crd pipelineresources.tekton.dev --ignore-not-found=true
    kubectl delete crd runs.tekton.dev --ignore-not-found=true
    kubectl delete crd tasks.tekton.dev --ignore-not-found=true
    kubectl delete crd taskruns.tekton.dev --ignore-not-found=true
    kubectl delete crd resolutionrequests.resolution.tekton.dev --ignore-not-found=true
    kubectl delete crd customruns.tekton.dev --ignore-not-found=true
    kubectl delete crd verificationpolicies.tekton.dev --ignore-not-found=true
    
    log_success "Tekton CRDs 清理完成"
}

# 清理残留资源
cleanup_remaining_resources() {
    print_header "清理残留资源"
    
    log_step "删除可能的残留 PVC..."
    kubectl delete pvc --all --all-namespaces --selector=app.kubernetes.io/part-of=tekton-pipelines --ignore-not-found=true
    
    log_step "删除可能的残留 Secret..."
    kubectl delete secret --all --all-namespaces --selector=app.kubernetes.io/part-of=tekton-pipelines --ignore-not-found=true
    
    log_step "删除可能的残留 ConfigMap..."
    kubectl delete configmap --all --all-namespaces --selector=app.kubernetes.io/part-of=tekton-pipelines --ignore-not-found=true
    
    log_success "残留资源清理完成"
}

# 验证清理结果
verify_cleanup() {
    print_header "验证清理结果"
    
    log_step "检查命名空间..."
    local remaining_namespaces=""
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        remaining_namespaces="${remaining_namespaces} ${TEKTON_NAMESPACE}"
    fi
    if kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; then
        remaining_namespaces="${remaining_namespaces} ${INGRESS_NAMESPACE}"
    fi
    
    if [[ -n "$remaining_namespaces" ]]; then
        log_warning "以下命名空间仍然存在:${remaining_namespaces}"
        log_warning "它们可能正在终止中，请稍等片刻"
    else
        log_success "所有命名空间已删除"
    fi
    
    log_step "检查 CRDs..."
    local remaining_crds=$(kubectl get crd | grep tekton | wc -l)
    if [[ $remaining_crds -gt 0 ]]; then
        log_warning "仍有 ${remaining_crds} 个 Tekton CRDs 存在"
        kubectl get crd | grep tekton
    else
        log_success "所有 Tekton CRDs 已删除"
    fi
    
    log_step "检查 IngressClass..."
    if kubectl get ingressclass nginx &> /dev/null; then
        log_warning "IngressClass 'nginx' 仍然存在"
    else
        log_success "IngressClass 已删除"
    fi
    
    log_success "清理结果验证完成"
}

# 显示清理总结
show_cleanup_summary() {
    print_header "清理总结"
    
    echo
    log_success "🧹 Tekton 核心基础设施清理完成！"
    echo
    
    log_info "📊 已清理组件:"
    log_info "  ✅ 测试资源 (PipelineRun, Pipeline, Task)"
    log_info "  ✅ Tekton Dashboard Ingress 和网络策略"
    log_info "  ✅ Tekton Dashboard"
    log_info "  ✅ Tekton Pipelines"
    log_info "  ✅ Nginx Ingress Controller"
    log_info "  ✅ IngressClass"
    log_info "  ✅ RBAC 资源 (ClusterRole, ClusterRoleBinding)"
    log_info "  ✅ CRD 资源"
    log_info "  ✅ 命名空间 (${TEKTON_NAMESPACE}, ${INGRESS_NAMESPACE})"
    echo
    
    log_info "🔧 验证清理:"
    log_info "  检查命名空间: kubectl get namespace | grep -E '(tekton|ingress)'"
    log_info "  检查 CRDs: kubectl get crd | grep tekton"
    log_info "  检查 Pod: kubectl get pods --all-namespaces | grep -E '(tekton|ingress)'"
    echo
    
    log_info "📖 下一步:"
    log_info "  1. 验证所有资源已清理完成"
    log_info "  2. 如需重新安装，运行: ./01-install-tekton-core.sh"
    log_info "  3. 如需安装阶段二，确保先完成阶段一安装"
    echo
    
    log_warning "⚠️  注意事项:"
    log_warning "  - 某些资源可能需要几分钟才能完全删除"
    log_warning "  - 如果有残留资源，可能需要手动清理"
    log_warning "  - 重新安装前建议重启相关节点（可选）"
    echo
    
    print_separator
    log_success "核心基础设施清理完成！"
    print_separator
}

# 主函数
main() {
    print_header "Tekton 核心基础设施清理 - 阶段一"
    
    log_info "开始清理 Tekton 核心基础设施组件..."
    log_info "包括: Ingress Controller + Tekton Pipelines + Dashboard"
    echo
    
    # 执行清理步骤
    check_prerequisites
    show_cleanup_plan
    
    cleanup_test_resources
    cleanup_dashboard_ingress
    cleanup_tekton_dashboard
    cleanup_tekton_pipelines
    cleanup_ingress_controller
    cleanup_ingress_class
    cleanup_rbac_resources
    cleanup_namespaces
    cleanup_crds
    cleanup_remaining_resources
    
    verify_cleanup
    show_cleanup_summary
}

# 错误处理
trap 'log_error "清理过程中发生错误，请检查上述日志"; exit 1' ERR

# 运行主函数
main "$@" 