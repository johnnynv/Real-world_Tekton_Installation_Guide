#!/bin/bash

# Tekton 安装验证脚本
# 支持阶段一（核心）和阶段二（Triggers）的验证

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
WEBHOOK_URL="http://${TEKTON_DOMAIN}/webhook"

# 验证阶段参数
STAGE="${1:-all}"  # 默认验证所有阶段

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

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stage=*)
                STAGE="${1#*=}"
                shift
                ;;
            --stage)
                STAGE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --stage=STAGE    指定验证阶段 (core|triggers|all)"
    echo "  -h, --help       显示此帮助信息"
    echo ""
    echo "阶段说明:"
    echo "  core      验证阶段一 (Ingress + Pipelines + Dashboard)"
    echo "  triggers  验证阶段二 (Triggers + GitHub Webhook)"
    echo "  all       验证所有阶段 (默认)"
    echo ""
    echo "示例:"
    echo "  $0                    # 验证所有阶段"
    echo "  $0 --stage=core       # 只验证阶段一"
    echo "  $0 --stage=triggers   # 只验证阶段二"
}

# 检查先决条件
check_prerequisites() {
    log_step "检查先决条件..."
    
    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在 PATH 中"
        exit 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    log_success "先决条件检查通过"
}

# 验证阶段一：核心基础设施
verify_stage_one() {
    print_header "验证阶段一：核心基础设施"
    
    local errors=0
    
    # 1. 检查 Ingress Controller
    log_step "检查 Nginx Ingress Controller..."
    if kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; then
        local ingress_pods=$(kubectl get pods -n ${INGRESS_NAMESPACE} | grep -c Running || echo "0")
        if [[ $ingress_pods -gt 0 ]]; then
            log_success "Nginx Ingress Controller 运行正常 (${ingress_pods} 个 Pod)"
        else
            log_error "Nginx Ingress Controller Pod 未运行"
            ((errors++))
        fi
    else
        log_error "Nginx Ingress Controller 命名空间不存在"
        ((errors++))
    fi
    
    # 2. 检查 IngressClass
    log_step "检查 IngressClass..."
    if kubectl get ingressclass nginx &> /dev/null; then
        log_success "IngressClass 'nginx' 存在"
    else
        log_error "IngressClass 'nginx' 不存在"
        ((errors++))
    fi
    
    # 3. 检查 Tekton Pipelines
    log_step "检查 Tekton Pipelines..."
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        local pipeline_pods=$(kubectl get pods -n ${TEKTON_NAMESPACE} | grep -E "tekton-pipelines-(controller|webhook)" | grep -c Running || echo "0")
        if [[ $pipeline_pods -ge 2 ]]; then
            log_success "Tekton Pipelines 运行正常 (${pipeline_pods} 个核心组件)"
        else
            log_error "Tekton Pipelines 组件未完全运行"
            ((errors++))
        fi
    else
        log_error "Tekton 命名空间不存在"
        ((errors++))
    fi
    
    # 4. 检查 Tekton Dashboard
    log_step "检查 Tekton Dashboard..."
    local dashboard_pods=$(kubectl get pods -l app=tekton-dashboard -n ${TEKTON_NAMESPACE} 2>/dev/null | grep -c Running || echo "0")
    if [[ $dashboard_pods -gt 0 ]]; then
        log_success "Tekton Dashboard 运行正常"
    else
        log_error "Tekton Dashboard 未运行"
        ((errors++))
    fi
    
    # 5. 检查 Dashboard Ingress
    log_step "检查 Dashboard Ingress..."
    if kubectl get ingress tekton-dashboard -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "Dashboard Ingress 配置存在"
    else
        log_error "Dashboard Ingress 配置不存在"
        ((errors++))
    fi
    
    # 6. 测试外部访问
    log_step "测试 Dashboard 外部访问..."
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" http://${TEKTON_DOMAIN}/ 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" ]]; then
        log_success "Dashboard 外部访问正常 (HTTP ${http_code})"
    else
        log_warning "Dashboard 外部访问异常 (HTTP ${http_code})"
        log_info "请检查 DNS 解析和 Ingress 配置"
    fi
    
    # 7. 检查基础 CRDs
    log_step "检查 Tekton CRDs..."
    local required_crds=("tasks.tekton.dev" "pipelines.tekton.dev" "pipelineruns.tekton.dev" "taskruns.tekton.dev")
    local missing_crds=0
    for crd in "${required_crds[@]}"; do
        if ! kubectl get crd $crd &> /dev/null; then
            log_error "CRD $crd 不存在"
            ((missing_crds++))
        fi
    done
    if [[ $missing_crds -eq 0 ]]; then
        log_success "所有必需的 Tekton CRDs 存在"
    else
        log_error "缺少 ${missing_crds} 个必需的 CRDs"
        ((errors++))
    fi
    
    # 8. 功能测试：创建简单 Pipeline
    log_step "功能测试：运行简单 Pipeline..."
    if create_and_run_test_pipeline; then
        log_success "Pipeline 功能测试通过"
    else
        log_error "Pipeline 功能测试失败"
        ((errors++))
    fi
    
    return $errors
}

# 验证阶段二：Triggers 和 Webhook
verify_stage_two() {
    print_header "验证阶段二：Triggers 和 Webhook"
    
    local errors=0
    
    # 1. 检查 Tekton Triggers
    log_step "检查 Tekton Triggers..."
    local triggers_pods=$(kubectl get pods -l app.kubernetes.io/part-of=tekton-triggers -n ${TEKTON_NAMESPACE} 2>/dev/null | grep -c Running || echo "0")
    if [[ $triggers_pods -gt 0 ]]; then
        log_success "Tekton Triggers 运行正常 (${triggers_pods} 个组件)"
    else
        log_error "Tekton Triggers 组件未运行"
        ((errors++))
    fi
    
    # 2. 检查 Triggers CRDs
    log_step "检查 Triggers CRDs..."
    local triggers_crds=("eventlisteners.triggers.tekton.dev" "triggerbindings.triggers.tekton.dev" "triggertemplates.triggers.tekton.dev")
    local missing_triggers_crds=0
    for crd in "${triggers_crds[@]}"; do
        if ! kubectl get crd $crd &> /dev/null; then
            log_error "CRD $crd 不存在"
            ((missing_triggers_crds++))
        fi
    done
    if [[ $missing_triggers_crds -eq 0 ]]; then
        log_success "所有 Triggers CRDs 存在"
    else
        log_error "缺少 ${missing_triggers_crds} 个 Triggers CRDs"
        ((errors++))
    fi
    
    # 3. 检查 RBAC 配置
    log_step "检查 RBAC 配置..."
    if kubectl get serviceaccount tekton-triggers-sa -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "Triggers ServiceAccount 存在"
    else
        log_error "Triggers ServiceAccount 不存在"
        ((errors++))
    fi
    
    if kubectl get clusterrole tekton-triggers-role &> /dev/null; then
        log_success "Triggers ClusterRole 存在"
    else
        log_error "Triggers ClusterRole 不存在"
        ((errors++))
    fi
    
    # 4. 检查 GitHub Secret
    log_step "检查 GitHub Webhook Secret..."
    if kubectl get secret github-webhook-secret -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "GitHub Webhook Secret 存在"
    else
        log_error "GitHub Webhook Secret 不存在"
        ((errors++))
    fi
    
    # 5. 检查 EventListener
    log_step "检查 EventListener..."
    if kubectl get eventlistener github-webhook-listener -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "EventListener 配置存在"
        
        # 检查 EventListener Pod
        local el_pods=$(kubectl get pods -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE} 2>/dev/null | grep -c Running || echo "0")
        if [[ $el_pods -gt 0 ]]; then
            log_success "EventListener Pod 运行正常"
        else
            log_error "EventListener Pod 未运行"
            ((errors++))
        fi
    else
        log_error "EventListener 配置不存在"
        ((errors++))
    fi
    
    # 6. 检查 TriggerBinding 和 TriggerTemplate
    log_step "检查 TriggerBinding 和 TriggerTemplate..."
    if kubectl get triggerbinding github-trigger-binding -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "TriggerBinding 配置存在"
    else
        log_error "TriggerBinding 配置不存在"
        ((errors++))
    fi
    
    if kubectl get triggertemplate github-trigger-template -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "TriggerTemplate 配置存在"
    else
        log_error "TriggerTemplate 配置不存在"
        ((errors++))
    fi
    
    # 7. 检查 Webhook Ingress
    log_step "检查 Webhook Ingress..."
    if kubectl get ingress github-webhook-ingress -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "Webhook Ingress 配置存在"
    else
        log_error "Webhook Ingress 配置不存在"
        ((errors++))
    fi
    
    # 8. 测试 Webhook 端点
    log_step "测试 Webhook 端点..."
    local webhook_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST ${WEBHOOK_URL} -H "Content-Type: application/json" -d '{"test":"data"}' 2>/dev/null || echo "000")
    if [[ "$webhook_code" =~ ^(200|202|500)$ ]]; then
        log_success "Webhook 端点响应正常 (HTTP ${webhook_code})"
    else
        log_error "Webhook 端点响应异常 (HTTP ${webhook_code})"
        ((errors++))
    fi
    
    # 9. 检查 Pipeline 和 Task
    log_step "检查 Webhook Pipeline 和 Task..."
    if kubectl get pipeline github-webhook-pipeline -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "GitHub Webhook Pipeline 存在"
    else
        log_error "GitHub Webhook Pipeline 不存在"
        ((errors++))
    fi
    
    if kubectl get task simple-hello-task -n ${TEKTON_NAMESPACE} &> /dev/null; then
        log_success "Webhook Task 存在"
    else
        log_error "Webhook Task 不存在"
        ((errors++))
    fi
    
    return $errors
}

# 创建和运行测试 Pipeline
create_and_run_test_pipeline() {
    local test_pipeline_name="verify-test-pipeline"
    local test_task_name="verify-test-task"
    local test_run_name="verify-test-run-$(date +%s)"
    
    # 创建测试 Task
    cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: ${test_task_name}
  namespace: ${TEKTON_NAMESPACE}
spec:
  steps:
  - name: test
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "验证测试成功"
      exit 0
EOF

    # 创建测试 Pipeline
    cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: ${test_pipeline_name}
  namespace: ${TEKTON_NAMESPACE}
spec:
  tasks:
  - name: test
    taskRef:
      name: ${test_task_name}
EOF

    # 运行测试 PipelineRun
    cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: ${test_run_name}
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: ${test_pipeline_name}
EOF

    # 等待完成并检查结果
    sleep 30
    local status=$(kubectl get pipelinerun ${test_run_name} -n ${TEKTON_NAMESPACE} -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    
    # 清理测试资源
    kubectl delete pipelinerun ${test_run_name} -n ${TEKTON_NAMESPACE} --ignore-not-found=true > /dev/null 2>&1
    kubectl delete pipeline ${test_pipeline_name} -n ${TEKTON_NAMESPACE} --ignore-not-found=true > /dev/null 2>&1
    kubectl delete task ${test_task_name} -n ${TEKTON_NAMESPACE} --ignore-not-found=true > /dev/null 2>&1
    
    [[ "$status" == "True" ]]
}

# 显示资源摘要
show_resource_summary() {
    print_header "资源摘要"
    
    echo
    log_info "📊 集群资源状态:"
    
    # Ingress Controller
    if kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; then
        local ingress_status=$(kubectl get pods -n ${INGRESS_NAMESPACE} 2>/dev/null | grep -c Running || echo "0")
        log_info "  Nginx Ingress Controller: ${ingress_status} 个 Pod 运行中"
    else
        log_info "  Nginx Ingress Controller: 未安装"
    fi
    
    # Tekton Pipelines
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        local pipeline_status=$(kubectl get pods -n ${TEKTON_NAMESPACE} | grep -E "tekton-pipelines-(controller|webhook)" | grep -c Running || echo "0")
        log_info "  Tekton Pipelines: ${pipeline_status} 个核心组件运行中"
        
        local dashboard_status=$(kubectl get pods -l app=tekton-dashboard -n ${TEKTON_NAMESPACE} 2>/dev/null | grep -c Running || echo "0")
        log_info "  Tekton Dashboard: ${dashboard_status} 个 Pod 运行中"
        
        local triggers_status=$(kubectl get pods -l app.kubernetes.io/part-of=tekton-triggers -n ${TEKTON_NAMESPACE} 2>/dev/null | grep -c Running || echo "0")
        log_info "  Tekton Triggers: ${triggers_status} 个组件运行中"
    else
        log_info "  Tekton 组件: 未安装"
    fi
    
    echo
    log_info "🌐 访问信息:"
    log_info "  Dashboard URL: http://${TEKTON_DOMAIN}/"
    log_info "  Webhook URL: ${WEBHOOK_URL}"
    
    echo
    log_info "🔧 有用的命令:"
    log_info "  查看所有组件: kubectl get all -n ${TEKTON_NAMESPACE}"
    log_info "  查看 PipelineRuns: kubectl get pipelinerun -n ${TEKTON_NAMESPACE}"
    log_info "  查看日志: kubectl logs -l app=tekton-dashboard -n ${TEKTON_NAMESPACE} -f"
}

# 显示验证总结
show_verification_summary() {
    local stage1_errors=$1
    local stage2_errors=$2
    local total_errors=$((stage1_errors + stage2_errors))
    
    print_header "验证总结"
    
    echo
    if [[ $total_errors -eq 0 ]]; then
        log_success "🎉 所有验证项目都通过了！"
        echo
        case "$STAGE" in
            "core")
                log_success "✅ 阶段一（核心基础设施）验证完成"
                log_info "📖 下一步: 运行阶段二安装 ./02-install-tekton-triggers.sh"
                ;;
            "triggers")
                log_success "✅ 阶段二（Triggers 和 Webhook）验证完成"
                log_info "🎯 您的 CI/CD 自动化系统已就绪！"
                ;;
            "all")
                log_success "✅ 阶段一和阶段二验证完成"
                log_info "🎯 完整的 Tekton 生产级部署已就绪！"
                ;;
        esac
    else
        log_error "❌ 发现 ${total_errors} 个问题需要解决"
        echo
        if [[ $stage1_errors -gt 0 ]]; then
            log_error "阶段一问题: ${stage1_errors} 个"
            log_info "建议: 重新运行 ./01-install-tekton-core.sh"
        fi
        if [[ $stage2_errors -gt 0 ]]; then
            log_error "阶段二问题: ${stage2_errors} 个"
            log_info "建议: 重新运行 ./02-install-tekton-triggers.sh"
        fi
    fi
    
    echo
    log_info "📚 更多信息:"
    log_info "  故障排查: cat TROUBLESHOOTING.md"
    log_info "  阶段一文档: cat 01-tekton-core-installation.md"
    log_info "  阶段二文档: cat 02-tekton-triggers-setup.md"
}

# 主函数
main() {
    # 解析参数
    parse_arguments "$@"
    
    print_header "Tekton 安装验证 - ${STAGE} 阶段"
    
    log_info "开始验证 Tekton 安装状态..."
    log_info "验证阶段: ${STAGE}"
    echo
    
    # 检查先决条件
    check_prerequisites
    
    local stage1_errors=0
    local stage2_errors=0
    
    # 根据参数决定验证哪些阶段
    case "$STAGE" in
        "core")
            verify_stage_one
            stage1_errors=$?
            ;;
        "triggers")
            # 检查阶段一是否已安装
            if ! kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
                log_error "阶段一尚未安装，请先运行: ./01-install-tekton-core.sh"
                exit 1
            fi
            verify_stage_two
            stage2_errors=$?
            ;;
        "all")
            verify_stage_one
            stage1_errors=$?
            if [[ $stage1_errors -eq 0 ]]; then
                verify_stage_two
                stage2_errors=$?
            else
                log_warning "跳过阶段二验证，因为阶段一存在问题"
            fi
            ;;
        *)
            log_error "未知的验证阶段: ${STAGE}"
            show_usage
            exit 1
            ;;
    esac
    
    # 显示资源摘要
    show_resource_summary
    
    # 显示验证总结
    show_verification_summary $stage1_errors $stage2_errors
    
    # 返回错误代码
    local total_errors=$((stage1_errors + stage2_errors))
    exit $total_errors
}

# 错误处理
trap 'log_error "验证过程中发生错误，请检查上述日志"; exit 1' ERR

# 运行主函数
main "$@" 