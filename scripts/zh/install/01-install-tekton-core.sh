#!/bin/bash

# Tekton 核心基础设施自动化安装脚本 - 阶段一
# 安装 Ingress Controller + Tekton Pipelines + Dashboard
# 以生产环境最佳实践为目标

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
TIMEOUT="600s"

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
        log_error "helm 未安装或不在 PATH 中"
        log_info "请安装 Helm v3.0+: https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    # 检查权限
    if ! kubectl auth can-i create namespace &> /dev/null; then
        log_error "没有足够的权限（需要集群管理员权限）"
        exit 1
    fi
    
    # 显示环境信息
    echo
    log_info "环境信息:"
    log_info "  Kubernetes 版本: $(kubectl version --short --client | cut -d' ' -f3)"
    log_info "  Helm 版本: $(helm version --short)"
    log_info "  目标节点 IP: ${NODE_IP}"
    log_info "  Tekton 域名: ${TEKTON_DOMAIN}"
    log_info "  命名空间: ${TEKTON_NAMESPACE}"
    echo
    
    log_success "先决条件检查通过"
}

# 设置环境变量
setup_environment() {
    log_step "设置环境变量..."
    
    export TEKTON_NAMESPACE
    export INGRESS_NAMESPACE
    export NODE_IP
    export TEKTON_DOMAIN
    
    log_info "环境变量已设置:"
    log_info "  TEKTON_NAMESPACE=${TEKTON_NAMESPACE}"
    log_info "  INGRESS_NAMESPACE=${INGRESS_NAMESPACE}"
    log_info "  NODE_IP=${NODE_IP}"
    log_info "  TEKTON_DOMAIN=${TEKTON_DOMAIN}"
    
    log_success "环境变量设置完成"
}

# 检查现有安装
check_existing_installation() {
    log_step "检查现有安装..."
    
    local has_tekton=false
    local has_ingress=false
    
    # 检查 Tekton 命名空间
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        log_warning "发现现有 Tekton 安装 (命名空间: ${TEKTON_NAMESPACE})"
        has_tekton=true
    fi
    
    # 检查 Ingress 命名空间
    if kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; then
        log_warning "发现现有 Ingress Controller 安装 (命名空间: ${INGRESS_NAMESPACE})"
        has_ingress=true
    fi
    
    if $has_tekton || $has_ingress; then
        echo
        log_warning "检测到现有安装。建议先运行清理脚本："
        log_warning "  ./01-cleanup-tekton-core.sh"
        echo
        read -p "是否继续安装？这可能导致配置冲突 (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
    fi
    
    log_success "现有安装检查完成"
}

# 安装 Nginx Ingress Controller
install_ingress_controller() {
    print_header "安装 Nginx Ingress Controller"
    
    log_step "添加 Helm 仓库..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    log_success "Helm 仓库添加完成"
    
    log_step "安装 Nginx Ingress Controller (生产级配置)..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ${INGRESS_NAMESPACE} \
        --create-namespace \
        --set controller.hostNetwork=true \
        --set controller.service.type=ClusterIP \
        --set "controller.service.externalIPs[0]=${NODE_IP}" \
        --set controller.config.use-forwarded-headers="true" \
        --set controller.config.compute-full-forwarded-for="true" \
        --set controller.config.use-proxy-protocol="false" \
        --set controller.metrics.enabled=true \
        --set controller.podSecurityContext.runAsUser=101 \
        --set controller.podSecurityContext.runAsGroup=101 \
        --set controller.podSecurityContext.fsGroup=101 \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=128Mi \
        --set controller.resources.limits.cpu=500m \
        --set controller.resources.limits.memory=512Mi \
        --timeout=${TIMEOUT} \
        --wait
    
    log_success "Nginx Ingress Controller 安装完成"
    
    log_step "创建 IngressClass..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
EOF
    
    log_success "IngressClass 创建完成"
    
    log_step "验证 Ingress Controller 安装..."
    kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=ingress-nginx -n ${INGRESS_NAMESPACE} --timeout=300s
    
    # 验证外部访问
    log_info "测试 Ingress Controller 响应..."
    sleep 10
    for i in {1..5}; do
        if curl -s -o /dev/null -w "%{http_code}" http://${NODE_IP}/ | grep -q "404"; then
            log_success "Ingress Controller 正常响应 (HTTP 404 - 预期结果)"
            break
        else
            log_warning "尝试 ${i}/5: Ingress Controller 未响应，等待..."
            sleep 10
        fi
    done
    
    log_success "Nginx Ingress Controller 验证完成"
}

# 安装 Tekton Pipelines
install_tekton_pipelines() {
    print_header "安装 Tekton Pipelines"
    
    log_step "安装 Tekton Pipelines..."
    kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
    
    log_step "等待 Tekton Pipelines 组件启动..."
    kubectl wait --for=condition=ready pods --all -n ${TEKTON_NAMESPACE} --timeout=300s
    
    log_step "验证 Tekton Pipelines 安装..."
    local pipeline_pods=$(kubectl get pods -n ${TEKTON_NAMESPACE} --no-headers | wc -l)
    if [[ $pipeline_pods -eq 0 ]]; then
        log_error "Tekton Pipelines Pod 未找到"
        exit 1
    fi
    
    log_info "Tekton Pipelines 组件状态:"
    kubectl get pods -n ${TEKTON_NAMESPACE}
    
    log_success "Tekton Pipelines 安装完成"
}

# 安装 Tekton Dashboard
install_tekton_dashboard() {
    print_header "安装 Tekton Dashboard"
    
    log_step "安装 Tekton Dashboard..."
    kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
    
    log_step "等待 Tekton Dashboard 启动..."
    kubectl wait --for=condition=ready pods -l app=tekton-dashboard -n ${TEKTON_NAMESPACE} --timeout=300s
    
    log_step "配置 Dashboard 资源限制..."
    kubectl patch deployment tekton-dashboard -n ${TEKTON_NAMESPACE} -p '{
        "spec": {
            "template": {
                "spec": {
                    "containers": [{
                        "name": "tekton-dashboard",
                        "resources": {
                            "requests": {"cpu": "100m", "memory": "128Mi"},
                            "limits": {"cpu": "500m", "memory": "512Mi"}
                        }
                    }]
                }
            }
        }
    }'
    
    log_step "验证 Dashboard 服务..."
    kubectl get svc tekton-dashboard -n ${TEKTON_NAMESPACE}
    
    log_success "Tekton Dashboard 安装完成"
}

# 配置外部访问
configure_external_access() {
    print_header "配置外部访问"
    
    log_step "创建 Tekton Dashboard Ingress..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: ${TEKTON_NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
  - host: ${TEKTON_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
EOF
    
    log_step "等待 Ingress 配置生效..."
    sleep 15
    
    log_step "验证 Ingress 配置..."
    kubectl get ingress -n ${TEKTON_NAMESPACE}
    
    log_step "测试外部访问..."
    for i in {1..10}; do
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" http://${TEKTON_DOMAIN}/ || echo "000")
        if [[ "$http_code" == "200" ]]; then
            log_success "外部访问测试成功 (HTTP ${http_code})"
            break
        else
            log_warning "尝试 ${i}/10: HTTP ${http_code}，等待 Ingress 生效..."
            sleep 10
        fi
    done
    
    log_success "外部访问配置完成"
}

# 应用生产环境配置
apply_production_config() {
    print_header "应用生产环境配置"
    
    log_step "配置 Pod Security Standards..."
    # 注意：某些 Tekton 组件需要 privileged 权限
    kubectl label namespace ${TEKTON_NAMESPACE} pod-security.kubernetes.io/enforce=privileged --overwrite
    kubectl label namespace ${TEKTON_NAMESPACE} pod-security.kubernetes.io/audit=restricted --overwrite
    kubectl label namespace ${TEKTON_NAMESPACE} pod-security.kubernetes.io/warn=restricted --overwrite
    
    log_step "配置网络策略..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-dashboard-access
  namespace: ${TEKTON_NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: tekton-dashboard
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ${INGRESS_NAMESPACE}
    ports:
    - protocol: TCP
      port: 9097
  - from: []
    ports:
    - protocol: TCP
      port: 9097
EOF
    
    log_success "生产环境配置应用完成"
}

# 创建测试资源
create_test_resources() {
    print_header "创建测试资源"
    
    log_step "创建测试 Task..."
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: ${TEKTON_NAMESPACE}
spec:
  steps:
  - name: echo
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "Hello from Tekton!"
      echo "阶段一安装验证成功 ✅"
      echo "时间: \$(date)"
      echo "节点信息:"
      cat /etc/hostname
EOF
    
    log_step "创建测试 Pipeline..."
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: hello-pipeline
  namespace: ${TEKTON_NAMESPACE}
spec:
  tasks:
  - name: say-hello
    taskRef:
      name: hello-world
EOF
    
    log_success "测试资源创建完成"
}

# 运行验证测试
run_verification_tests() {
    print_header "运行验证测试"
    
    log_step "创建测试 PipelineRun..."
    local test_run_name="hello-run-$(date +%s)"
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: ${test_run_name}
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: hello-pipeline
EOF
    
    log_step "等待 PipelineRun 完成..."
    kubectl wait --for=condition=Succeeded pipelinerun/${test_run_name} -n ${TEKTON_NAMESPACE} --timeout=300s
    
    log_step "检查 PipelineRun 结果..."
    local status=$(kubectl get pipelinerun ${test_run_name} -n ${TEKTON_NAMESPACE} -o jsonpath='{.status.conditions[0].status}')
    if [[ "$status" == "True" ]]; then
        log_success "测试 PipelineRun 执行成功"
    else
        log_error "测试 PipelineRun 执行失败"
        kubectl describe pipelinerun ${test_run_name} -n ${TEKTON_NAMESPACE}
        exit 1
    fi
    
    log_success "验证测试完成"
}

# 显示安装总结
show_installation_summary() {
    print_header "安装总结"
    
    echo
    log_success "🎉 Tekton 核心基础设施安装完成！"
    echo
    
    log_info "📊 安装组件:"
    log_info "  ✅ Nginx Ingress Controller (生产级配置)"
    log_info "  ✅ Tekton Pipelines (最新稳定版)"
    log_info "  ✅ Tekton Dashboard (Web UI)"
    log_info "  ✅ 外部访问配置 (Ingress + IngressClass)"
    log_info "  ✅ 生产环境安全配置"
    echo
    
    log_info "🌐 访问信息:"
    log_info "  Dashboard URL: http://${TEKTON_DOMAIN}/"
    log_info "  Dashboard API: http://${TEKTON_DOMAIN}/api/v1/namespaces"
    echo
    
    log_info "🔧 管理命令:"
    log_info "  查看组件状态: kubectl get all -n ${TEKTON_NAMESPACE}"
    log_info "  查看 Ingress: kubectl get ingress -n ${TEKTON_NAMESPACE}"
    log_info "  查看日志: kubectl logs -l app=tekton-dashboard -n ${TEKTON_NAMESPACE} -f"
    echo
    
    log_info "📖 下一步:"
    log_info "  1. 访问 Dashboard: http://${TEKTON_DOMAIN}/"
    log_info "  2. 查看测试 Pipeline 执行结果"
    log_info "  3. 继续阶段二: ./02-install-tekton-triggers.sh"
    echo
    
    log_warning "⚠️  重要提示:"
    log_warning "  - 如果访问遇到问题，检查 DNS 解析或添加 hosts 记录"
    log_warning "  - 生产环境建议配置 HTTPS 和认证"
    log_warning "  - 定期备份 Tekton 配置和数据"
    echo
    
    print_separator
    log_success "阶段一部署完成！准备进入阶段二..."
    print_separator
}

# 主函数
main() {
    print_header "Tekton 核心基础设施安装 - 阶段一"
    
    log_info "开始安装 Tekton 核心基础设施组件..."
    log_info "包括: Ingress Controller + Tekton Pipelines + Dashboard"
    echo
    
    # 执行安装步骤
    check_prerequisites
    setup_environment
    check_existing_installation
    
    install_ingress_controller
    install_tekton_pipelines
    install_tekton_dashboard
    configure_external_access
    apply_production_config
    create_test_resources
    run_verification_tests
    
    show_installation_summary
}

# 错误处理
trap 'log_error "安装过程中发生错误，请检查上述日志"; exit 1' ERR

# 运行主函数
main "$@" 