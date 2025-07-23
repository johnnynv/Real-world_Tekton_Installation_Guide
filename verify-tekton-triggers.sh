#!/bin/bash

# Tekton Triggers 验证脚本
# 验证安装和配置是否正确

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 配置变量
NAMESPACE="tekton-pipelines"
WEBHOOK_DOMAIN="tekton.10.117.8.154.nip.io"

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

check_triggers_installation() {
    print_header "检查 Tekton Triggers 安装"
    
    log_info "检查 Triggers CRDs..."
    local triggers_crds=(
        "eventlisteners.triggers.tekton.dev"
        "triggerbindings.triggers.tekton.dev"
        "triggertemplates.triggers.tekton.dev"
        "clustertriggerbindings.triggers.tekton.dev"
    )
    
    for crd in "${triggers_crds[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            log_success "CRD $crd 存在"
        else
            log_error "CRD $crd 不存在"
            return 1
        fi
    done
    
    log_info "检查 Triggers 组件 Pods..."
    local triggers_pods=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=tekton-triggers --no-headers 2>/dev/null | wc -l)
    if [ "$triggers_pods" -gt 0 ]; then
        kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=tekton-triggers
        log_success "Tekton Triggers 组件运行正常"
    else
        log_error "未找到 Tekton Triggers 组件"
        return 1
    fi
}

check_rbac_resources() {
    print_header "检查 RBAC 资源"
    
    log_info "检查 ServiceAccount..."
    if kubectl get serviceaccount tekton-triggers-sa -n $NAMESPACE &> /dev/null; then
        log_success "ServiceAccount tekton-triggers-sa 存在"
    else
        log_error "ServiceAccount tekton-triggers-sa 不存在"
        return 1
    fi
    
    log_info "检查 ClusterRole..."
    if kubectl get clusterrole tekton-triggers-role &> /dev/null; then
        log_success "ClusterRole tekton-triggers-role 存在"
    else
        log_error "ClusterRole tekton-triggers-role 不存在"
        return 1
    fi
    
    log_info "检查 ClusterRoleBinding..."
    if kubectl get clusterrolebinding tekton-triggers-binding &> /dev/null; then
        log_success "ClusterRoleBinding tekton-triggers-binding 存在"
    else
        log_error "ClusterRoleBinding tekton-triggers-binding 不存在"
        return 1
    fi
}

check_github_secret() {
    print_header "检查 GitHub Secret"
    
    log_info "检查 GitHub webhook secret..."
    if kubectl get secret github-webhook-secret -n $NAMESPACE &> /dev/null; then
        log_success "Secret github-webhook-secret 存在"
        
        # 验证 secret 内容
        local secret_value=$(kubectl get secret github-webhook-secret -n $NAMESPACE -o jsonpath='{.data.secretToken}' | base64 -d)
        if [ "$secret_value" = "110120119" ]; then
            log_success "Secret 值正确"
        else
            log_warning "Secret 值可能不正确"
        fi
    else
        log_error "Secret github-webhook-secret 不存在"
        return 1
    fi
}

check_tekton_resources() {
    print_header "检查 Tekton 资源"
    
    log_info "检查 Task..."
    if kubectl get task simple-hello-task -n $NAMESPACE &> /dev/null; then
        log_success "Task simple-hello-task 存在"
    else
        log_error "Task simple-hello-task 不存在"
        return 1
    fi
    
    log_info "检查 Pipeline..."
    if kubectl get pipeline github-webhook-pipeline -n $NAMESPACE &> /dev/null; then
        log_success "Pipeline github-webhook-pipeline 存在"
    else
        log_error "Pipeline github-webhook-pipeline 不存在"
        return 1
    fi
    
    log_info "检查 TriggerTemplate..."
    if kubectl get triggertemplate github-trigger-template -n $NAMESPACE &> /dev/null; then
        log_success "TriggerTemplate github-trigger-template 存在"
    else
        log_error "TriggerTemplate github-trigger-template 不存在"
        return 1
    fi
    
    log_info "检查 TriggerBinding..."
    if kubectl get triggerbinding github-trigger-binding -n $NAMESPACE &> /dev/null; then
        log_success "TriggerBinding github-trigger-binding 存在"
    else
        log_error "TriggerBinding github-trigger-binding 不存在"
        return 1
    fi
    
    log_info "检查 EventListener..."
    if kubectl get eventlistener github-webhook-listener -n $NAMESPACE &> /dev/null; then
        log_success "EventListener github-webhook-listener 存在"
    else
        log_error "EventListener github-webhook-listener 不存在"
        return 1
    fi
}

check_service_and_ingress() {
    print_header "检查 Service 和 Ingress"
    
    log_info "检查 EventListener Service..."
    if kubectl get svc github-webhook-listener-service -n $NAMESPACE &> /dev/null; then
        log_success "Service github-webhook-listener-service 存在"
        kubectl get svc github-webhook-listener-service -n $NAMESPACE
    else
        log_error "Service github-webhook-listener-service 不存在"
        return 1
    fi
    
    log_info "检查 Ingress..."
    if kubectl get ingress github-webhook-ingress -n $NAMESPACE &> /dev/null; then
        log_success "Ingress github-webhook-ingress 存在"
        kubectl get ingress github-webhook-ingress -n $NAMESPACE
    else
        log_error "Ingress github-webhook-ingress 不存在"
        return 1
    fi
}

check_pods_status() {
    print_header "检查 Pod 状态"
    
    log_info "检查 EventListener Pod..."
    local el_pods=$(kubectl get pods -l eventlistener=github-webhook-listener -n $NAMESPACE --no-headers 2>/dev/null)
    if [ -n "$el_pods" ]; then
        echo "$el_pods"
        local ready_pods=$(echo "$el_pods" | grep -c "1/1.*Running" || true)
        local total_pods=$(echo "$el_pods" | wc -l)
        if [ "$ready_pods" -eq "$total_pods" ]; then
            log_success "所有 EventListener Pod 运行正常"
        else
            log_warning "部分 EventListener Pod 未就绪"
        fi
    else
        log_error "未找到 EventListener Pod"
        return 1
    fi
    
    log_info "所有 Tekton Pipelines Pod 状态:"
    kubectl get pods -n $NAMESPACE
}

test_webhook_endpoint() {
    print_header "测试 Webhook 端点"
    
    log_info "测试 webhook 端点连通性..."
    local webhook_url="http://$WEBHOOK_DOMAIN/webhook"
    
    # 使用 curl 测试端点
    if command -v curl &> /dev/null; then
        local response=$(curl -s -o /dev/null -w "%{http_code}" "$webhook_url" --max-time 10 || echo "000")
        if [ "$response" = "405" ] || [ "$response" = "200" ] || [ "$response" = "400" ]; then
            log_success "Webhook 端点可访问 (HTTP $response)"
            echo "  URL: $webhook_url"
        else
            log_warning "Webhook 端点响应异常 (HTTP $response)"
            echo "  URL: $webhook_url"
            echo "  这可能是正常的，EventListener 只接受 POST 请求"
        fi
    else
        log_warning "curl 命令不可用，跳过端点测试"
    fi
}

test_manual_trigger() {
    print_header "手动触发测试"
    
    read -p "是否要创建一个测试 PipelineRun? (y/N): " create_test
    if [[ $create_test =~ ^[Yy]$ ]]; then
        log_info "创建测试 PipelineRun..."
        
        cat <<EOF | kubectl create -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-test-run-
  namespace: $NAMESPACE
spec:
  pipelineRef:
    name: github-webhook-pipeline
  params:
  - name: repo-url
    value: "https://github.com/johnnynv/tekton-poc"
  - name: revision
    value: "main"
EOF
        
        log_success "测试 PipelineRun 已创建"
        echo ""
        echo "查看 PipelineRun 状态:"
        echo "  kubectl get pipelinerun -n $NAMESPACE"
        echo "  kubectl logs -l tekton.dev/pipelineRun=<pipeline-run-name> -n $NAMESPACE -f"
    fi
}

show_summary() {
    print_header "验证总结"
    
    echo -e "${GREEN}✅ Tekton Triggers GitHub Webhook 配置验证完成${NC}"
    echo ""
    echo -e "${PURPLE}重要信息:${NC}"
    echo "  • Webhook URL: http://$WEBHOOK_DOMAIN/webhook"
    echo "  • Secret: 110120119"
    echo "  • 支持事件: push"
    echo "  • GitHub Repo: https://github.com/johnnynv/tekton-poc"
    echo ""
    echo -e "${PURPLE}监控命令:${NC}"
    echo "  • 查看 PipelineRuns: kubectl get pipelinerun -n $NAMESPACE"
    echo "  • 查看 Pod 日志: kubectl logs -l eventlistener=github-webhook-listener -n $NAMESPACE -f"
    echo "  • 查看 TaskRun 日志: kubectl logs -l tekton.dev/taskRun=<task-run-name> -n $NAMESPACE -f"
    echo ""
    echo -e "${PURPLE}Tekton Dashboard:${NC}"
    echo "  • 访问地址: http://tekton.10.117.8.154.nip.io/"
    echo ""
    echo -e "${YELLOW}GitHub Webhook 配置:${NC}"
    echo "  1. 访问: https://github.com/johnnynv/tekton-poc/settings/hooks"
    echo "  2. 添加 webhook，URL: http://$WEBHOOK_DOMAIN/webhook"
    echo "  3. Secret: 110120119"
    echo "  4. 选择 'Just the push event'"
}

# 主验证流程
main() {
    print_header "Tekton Triggers 验证脚本"
    
    local exit_code=0
    
    check_triggers_installation || exit_code=1
    check_rbac_resources || exit_code=1
    check_github_secret || exit_code=1
    check_tekton_resources || exit_code=1
    check_service_and_ingress || exit_code=1
    check_pods_status || exit_code=1
    test_webhook_endpoint
    test_manual_trigger
    
    if [ $exit_code -eq 0 ]; then
        show_summary
    else
        log_error "验证过程中发现问题，请检查上述错误信息"
    fi
    
    exit $exit_code
}

# 执行主函数
main "$@" 