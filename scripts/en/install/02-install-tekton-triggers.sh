#!/bin/bash

# Tekton Triggers 自动化安装和配置脚本 - 阶段二
# 安装 Triggers + GitHub Webhook 集成
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
NODE_IP="10.117.8.154"
TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"
WEBHOOK_URL="http://${TEKTON_DOMAIN}/webhook"
GITHUB_REPO_URL="https://github.com/johnnynv/tekton-poc"
GITHUB_SECRET="110120119"
TIMEOUT="600s"

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

check_prerequisites() {
    log_info "检查先决条件..."
    
    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    # 检查 tekton-pipelines namespace
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "Tekton Pipelines 未安装，请先安装 Tekton Pipelines"
        exit 1
    fi
    
    log_success "先决条件检查通过"
}

install_tekton_triggers() {
    log_info "安装 Tekton Triggers..."
    
    # 检查是否已安装
    if kubectl get crd | grep -q "triggers.tekton.dev"; then
        log_warning "Tekton Triggers 已安装，跳过安装步骤"
        return
    fi
    
    # 安装 Tekton Triggers
    kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
    kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
    
    # 等待 Triggers 组件启动
    log_info "等待 Tekton Triggers 组件启动..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=tekton-triggers -n $NAMESPACE --timeout=300s
    
    log_success "Tekton Triggers 安装完成"
}

create_rbac() {
    log_info "创建 RBAC 资源..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
# Core resources
- apiGroups: [""]
  resources: ["configmaps", "secrets", "serviceaccounts", "events", "pods", "services"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
# Tekton Pipeline resources
- apiGroups: ["tekton.dev"]
  resources: ["tasks", "clustertasks", "pipelines", "pipelineruns", "taskruns", "runs", "customruns"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
# Tekton Triggers resources
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates", "clustertriggerbindings", "triggers", "interceptors", "clusterinterceptors"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
# For creating pods and other resources
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: $NAMESPACE
roleRef:
  kind: ClusterRole
  name: tekton-triggers-role
  apiGroup: rbac.authorization.k8s.io
EOF
    
    log_success "RBAC 资源创建完成"
}

create_github_secret() {
    log_info "创建 GitHub webhook secret..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-secret
  namespace: $NAMESPACE
type: Opaque
data:
  secretToken: $(echo -n "$GITHUB_SECRET" | base64)
EOF
    
    log_success "GitHub webhook secret 创建完成"
}

fix_pod_security() {
    log_info "修复 Pod Security 配置..."
    
    # 检查当前Pod Security配置
    local current_enforce=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
    
    if [ "$current_enforce" = "restricted" ]; then
        log_warning "检测到 Pod Security 为 'restricted' 模式，更改为 'privileged' 以支持 Tekton"
        kubectl label namespace $NAMESPACE pod-security.kubernetes.io/enforce=privileged --overwrite
        log_success "Pod Security 配置已更新"
    else
        log_info "Pod Security 配置正常"
    fi
}

create_task() {
    log_info "创建 Task 资源..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: simple-hello-task
  namespace: $NAMESPACE
spec:
  params:
  - name: repo-url
    type: string
    description: The git repository URL
  - name: revision
    type: string
    description: The git revision
    default: "main"
  steps:
  - name: hello
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "=== Tekton Triggers GitHub Webhook 测试成功! ==="
      echo "Repository: \$(params.repo-url)"
      echo "Revision: \$(params.revision)"
      echo "Time: \$(date)"
      echo "GitHub webhook 正常工作!"
      echo "=========================================="
EOF
    
    log_success "Task 资源创建完成"
}

create_pipeline() {
    log_info "创建 Pipeline 资源..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: github-webhook-pipeline
  namespace: $NAMESPACE
spec:
  params:
  - name: repo-url
    type: string
    description: The git repository URL to clone
  - name: revision
    type: string
    description: The git revision to checkout
    default: "main"
  tasks:
  - name: hello-task
    taskRef:
      name: simple-hello-task
    params:
    - name: repo-url
      value: \$(params.repo-url)
    - name: revision
      value: \$(params.revision)
EOF
    
    log_success "Pipeline 资源创建完成"
}

create_trigger_template() {
    log_info "创建 TriggerTemplate..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: $NAMESPACE
spec:
  params:
  - name: git-repo-url
    description: The git repository url
  - name: git-revision
    description: The git revision
    default: main
  - name: git-repo-name
    description: The name of the repository
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: github-webhook-run-
      namespace: $NAMESPACE
    spec:
      pipelineRef:
        name: github-webhook-pipeline
      params:
      - name: repo-url
        value: \$(tt.params.git-repo-url)
      - name: revision
        value: \$(tt.params.git-revision)
EOF
    
    log_success "TriggerTemplate 创建完成"
}

create_trigger_binding() {
    log_info "创建 TriggerBinding..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: $NAMESPACE
spec:
  params:
  - name: git-repo-url
    value: \$(body.repository.clone_url)
  - name: git-repo-name
    value: \$(body.repository.name)
  - name: git-revision
    value: \$(body.head_commit.id)
EOF
    
    log_success "TriggerBinding 创建完成"
}

create_event_listener() {
    log_info "创建 EventListener..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
  namespace: $NAMESPACE
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: github-push-trigger
    interceptors:
    - ref:
        name: "github"
      params:
      - name: "secretRef"
        value:
          secretName: github-webhook-secret
          secretKey: secretToken
      - name: "eventTypes"
        value: ["push"]
    bindings:
    - ref: github-trigger-binding
    template:
      ref: github-trigger-template
EOF
    
    log_success "EventListener 创建完成"
}

create_service_and_ingress() {
    log_info "创建 Service 和 Ingress..."
    
    # 等待 EventListener Pod 启动
    sleep 30
    
    # 创建 Service
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: github-webhook-listener-service
  namespace: $NAMESPACE
spec:
  selector:
    app.kubernetes.io/managed-by: EventListener
    app.kubernetes.io/part-of: Triggers
    eventlistener: github-webhook-listener
  ports:
  - name: http-listener
    port: 8080
    protocol: TCP
    targetPort: 8080
  type: ClusterIP
EOF
    
    # 创建 Ingress
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: github-webhook-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
spec:
  rules:
  - host: $WEBHOOK_DOMAIN
    http:
      paths:
      - path: /webhook
        pathType: Prefix
        backend:
          service:
            name: github-webhook-listener-service
            port:
              number: 8080
EOF
    
    log_success "Service 和 Ingress 创建完成"
}

wait_for_deployment() {
    log_info "等待所有组件启动完成..."
    
    # 等待 EventListener Pod 就绪
    kubectl wait --for=condition=ready pod -l eventlistener=github-webhook-listener -n $NAMESPACE --timeout=300s
    
    log_success "所有组件启动完成"
}

print_completion_info() {
    print_header "安装完成"
    
    echo -e "${GREEN}Tekton Triggers GitHub Webhook 配置已完成!${NC}"
    echo ""
    echo -e "${PURPLE}GitHub Webhook 配置信息:${NC}"
    echo "  Repository: $GITHUB_REPO_URL"
    echo "  Webhook URL: http://$WEBHOOK_DOMAIN/webhook"
    echo "  Secret: $GITHUB_SECRET"
    echo "  Events: push"
    echo ""
    echo -e "${PURPLE}访问地址:${NC}"
    echo "  Tekton Dashboard: http://tekton.10.117.8.154.nip.io/"
    echo "  Webhook Endpoint: http://$WEBHOOK_DOMAIN/webhook"
    echo ""
    echo -e "${PURPLE}验证命令:${NC}"
    echo "  kubectl get eventlistener,triggertemplate,triggerbinding -n $NAMESPACE"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl get svc,ingress -n $NAMESPACE"
    echo ""
    echo -e "${YELLOW}GitHub Webhook 配置步骤:${NC}"
    echo "  1. 访问: $GITHUB_REPO_URL/settings/hooks"
    echo "  2. 点击 'Add webhook'"
    echo "  3. Payload URL: http://$WEBHOOK_DOMAIN/webhook"
    echo "  4. Content type: application/json"
    echo "  5. Secret: $GITHUB_SECRET"
    echo "  6. 选择 'Just the push event'"
    echo "  7. 确保 'Active' 被选中"
    echo "  8. 点击 'Add webhook'"
}

# 主安装流程
main() {
    print_header "Tekton Triggers 安装和配置"
    
    check_prerequisites
    install_tekton_triggers
    fix_pod_security
    create_rbac
    create_github_secret
    create_task
    create_pipeline
    create_trigger_template
    create_trigger_binding
    create_event_listener
    create_service_and_ingress
    wait_for_deployment
    print_completion_info
}

# 执行主函数
main "$@" 