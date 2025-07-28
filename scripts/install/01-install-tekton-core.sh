#!/bin/bash

# Tekton Core Infrastructure Automated Installation Script - Stage 1
# Install Ingress Controller + Tekton Pipelines + Dashboard
# Production environment best practices oriented

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
TEKTON_NAMESPACE="tekton-pipelines"
INGRESS_NAMESPACE="ingress-nginx"
NODE_IP="${NODE_IP:-10.117.8.154}"
TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"
TIMEOUT="600s"

# Auto-detect NODE_IP if not set
if [[ -z "${NODE_IP}" || "${NODE_IP}" == "10.117.8.154" ]]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"
fi

# Logging functions
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

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        log_info "Please install Helm v3.0+: https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check permissions
    if ! kubectl auth can-i create namespace &> /dev/null; then
        log_error "Insufficient permissions (cluster admin privileges required)"
        exit 1
    fi
    
    # Display environment info
    echo
    log_info "Environment information:"
    log_info "  Kubernetes version: $(kubectl version --short --client 2>/dev/null | cut -d' ' -f3 || echo 'unknown')"
    log_info "  Helm version: $(helm version --short)"
    log_info "  Target node IP: ${NODE_IP}"
    log_info "  Tekton domain: ${TEKTON_DOMAIN}"
    log_info "  Namespace: ${TEKTON_NAMESPACE}"
    echo
    
    log_success "Prerequisites check passed"
}

# Setup environment variables
setup_environment() {
    log_step "Setting up environment variables..."
    
    export TEKTON_NAMESPACE
    export INGRESS_NAMESPACE
    export NODE_IP
    export TEKTON_DOMAIN
    
    log_info "Environment variables configured:"
    log_info "  TEKTON_NAMESPACE=${TEKTON_NAMESPACE}"
    log_info "  INGRESS_NAMESPACE=${INGRESS_NAMESPACE}"
    log_info "  NODE_IP=${NODE_IP}"
    log_info "  TEKTON_DOMAIN=${TEKTON_DOMAIN}"
    
    log_success "Environment variables setup completed"
}

# Check existing installation
check_existing_installation() {
    log_step "Checking existing installation..."
    
    # Check if Tekton namespace exists
    if kubectl get namespace ${TEKTON_NAMESPACE} &> /dev/null; then
        log_warning "Tekton namespace already exists"
        log_info "If you want to reinstall, run cleanup script first:"
        log_info "  ./scripts/en/cleanup/01-cleanup-tekton-core.sh"
    fi
    
    # Check if Ingress Controller is already installed
    if kubectl get namespace ${INGRESS_NAMESPACE} &> /dev/null; then
        log_warning "Ingress Controller namespace already exists"
    fi
    
    log_success "Existing installation check completed"
}

# Install Nginx Ingress Controller
install_ingress_controller() {
    print_header "Installing Nginx Ingress Controller"
    
    log_step "Adding Helm repository..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    log_success "Helm repository added successfully"
    
    log_step "Installing Nginx Ingress Controller (production configuration)..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ${INGRESS_NAMESPACE} \
        --create-namespace \
        --set controller.hostNetwork=true \
        --set controller.kind=DaemonSet \
        --set controller.service.type=ClusterIP \
        --set controller.nodeSelector."kubernetes\.io/os"=linux \
        --set controller.admissionWebhooks.enabled=false \
        --set controller.service.externalIPs="{${NODE_IP}}" \
        --set controller.resources.limits.cpu=200m \
        --set controller.resources.limits.memory=256Mi \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=128Mi \
        --wait --timeout=${TIMEOUT}
    
    log_success "Nginx Ingress Controller installation completed"
    
    log_step "Creating IngressClass..."
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  controller: k8s.io/ingress-nginx
EOF
    
    log_success "IngressClass creation completed"
    
    log_step "Verifying Ingress Controller installation..."
    kubectl wait --for=condition=ready pod \
        --selector=app.kubernetes.io/name=ingress-nginx \
        --namespace=${INGRESS_NAMESPACE} \
        --timeout=300s
    
    log_info "Testing Ingress Controller response..."
    sleep 10
    if curl -s -o /dev/null -w "%{http_code}" http://${NODE_IP} | grep -q "404"; then
        log_success "Ingress Controller responding normally (HTTP 404 - expected result)"
    else
        log_warning "Ingress Controller response test failed, but may still be functional"
    fi
    
    log_success "Nginx Ingress Controller verification completed"
}

# Install Tekton Pipelines
install_tekton_pipelines() {
    print_header "Installing Tekton Pipelines"
    
    log_step "Installing Tekton Pipelines..."
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
    
    log_step "Waiting for Tekton Pipelines components to start..."
    kubectl wait --for=condition=ready pod \
        --selector=app.kubernetes.io/name=tekton-events-controller \
        --namespace=${TEKTON_NAMESPACE} \
        --timeout=300s
    
    kubectl wait --for=condition=ready pod \
        --selector=app.kubernetes.io/name=tekton-pipelines-controller \
        --namespace=${TEKTON_NAMESPACE} \
        --timeout=300s
    
    kubectl wait --for=condition=ready pod \
        --selector=app.kubernetes.io/name=tekton-pipelines-webhook \
        --namespace=${TEKTON_NAMESPACE} \
        --timeout=300s
    
    log_step "Verifying Tekton Pipelines installation..."
    log_info "Tekton Pipelines component status:"
    kubectl get pods -n ${TEKTON_NAMESPACE} | grep -E "(tekton-events-controller|tekton-pipelines-controller|tekton-pipelines-webhook)"
    
    log_success "Tekton Pipelines installation completed"
}

# Install Tekton Dashboard
install_tekton_dashboard() {
    print_header "Installing Tekton Dashboard"
    
    log_step "Installing Tekton Dashboard..."
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
    
    log_step "Waiting for Tekton Dashboard to start..."
    kubectl wait --for=condition=ready pod \
        --selector=app.kubernetes.io/name=tekton-dashboard \
        --namespace=${TEKTON_NAMESPACE} \
        --timeout=300s
    
    log_step "Configuring Dashboard resource limits..."
    kubectl patch deployment tekton-dashboard -n ${TEKTON_NAMESPACE} --patch '{
        "spec": {
            "template": {
                "spec": {
                    "containers": [{
                        "name": "tekton-dashboard",
                        "resources": {
                            "limits": {
                                "cpu": "200m",
                                "memory": "256Mi"
                            },
                            "requests": {
                                "cpu": "100m",
                                "memory": "128Mi"
                            }
                        }
                    }]
                }
            }
        }
    }'
    
    log_step "Verifying Dashboard service..."
    kubectl get service tekton-dashboard -n ${TEKTON_NAMESPACE}
    
    log_success "Tekton Dashboard installation completed"
}

# Configure external access
configure_external_access() {
    print_header "Configuring External Access"
    
    log_step "Creating Tekton Dashboard Ingress..."
    kubectl apply -f - <<EOF
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
    
    log_step "Waiting for Ingress configuration to take effect..."
    sleep 15
    
    log_step "Verifying Ingress configuration..."
    kubectl get ingress -n ${TEKTON_NAMESPACE}
    
    log_step "Testing external access..."
    sleep 10
    if curl -s -o /dev/null -w "%{http_code}" http://${TEKTON_DOMAIN}/ | grep -q "200"; then
        log_success "External access test successful (HTTP 200)"
    else
        log_warning "External access test failed, but may need more time to propagate"
    fi
    
    log_success "External access configuration completed"
}

# Apply production environment configurations
apply_production_config() {
    print_header "Applying Production Environment Configuration"
    
    log_step "Configuring Pod Security Standards..."
    kubectl label namespace ${TEKTON_NAMESPACE} \
        pod-security.kubernetes.io/enforce=restricted \
        pod-security.kubernetes.io/audit=restricted \
        pod-security.kubernetes.io/warn=restricted
    
    log_step "Configuring network policies..."
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-dashboard-access
  namespace: ${TEKTON_NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: tekton-dashboard
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 9097
  - from: []
    ports:
    - protocol: TCP
      port: 9097
EOF
    
    log_success "Production environment configuration applied successfully"
}

# Create test resources
create_test_resources() {
    print_header "Creating Test Resources"
    
    log_step "Creating test Task..."
    kubectl apply -f - <<EOF
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: ${TEKTON_NAMESPACE}
spec:
  steps:
  - name: hello
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "🎉 Welcome to Tekton!"
      echo "✅ Core infrastructure is working!"
      echo "🌐 Dashboard URL: http://${TEKTON_DOMAIN}/"
      echo "📊 Cluster: \$(hostname)"
      echo "⏰ Time: \$(date)"
EOF
    
    log_step "Creating test Pipeline..."
    kubectl apply -f - <<EOF
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
    
    log_success "Test resources creation completed"
}

# Run verification tests
run_verification_tests() {
    print_header "Running Verification Tests"
    
    log_step "Creating test PipelineRun..."
    kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: hello-run-
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: hello-pipeline
EOF
    
    log_step "Waiting for PipelineRun completion..."
    sleep 30
    
    # Get the latest PipelineRun
    PIPELINERUN_NAME=$(kubectl get pipelinerun -n ${TEKTON_NAMESPACE} \
        --sort-by=.metadata.creationTimestamp \
        --output=jsonpath='{.items[-1].metadata.name}')
    
    kubectl wait --for=condition=succeeded pipelinerun/${PIPELINERUN_NAME} \
        --namespace=${TEKTON_NAMESPACE} \
        --timeout=300s
    
    log_step "Checking PipelineRun result..."
    if kubectl get pipelinerun/${PIPELINERUN_NAME} -n ${TEKTON_NAMESPACE} \
        -o jsonpath='{.status.conditions[0].status}' | grep -q "True"; then
        log_success "Test PipelineRun executed successfully"
    else
        log_error "Test PipelineRun failed"
        exit 1
    fi
    
    log_success "Verification tests completed"
}

# Installation summary
print_installation_summary() {
    print_header "Installation Summary"
    
    echo
    log_success "🎉 Tekton Core Infrastructure installation completed!"
    echo
    log_info "📊 Installed components:"
    log_info "  ✅ Nginx Ingress Controller (production configuration)"
    log_info "  ✅ Tekton Pipelines (latest stable version)"
    log_info "  ✅ Tekton Dashboard (Web UI)"
    log_info "  ✅ External access configuration (Ingress + IngressClass)"
    log_info "  ✅ Production environment security configuration"
    echo
    log_info "🌐 Access information:"
    log_info "  Dashboard URL: http://${TEKTON_DOMAIN}/"
    log_info "  Dashboard API: http://${TEKTON_DOMAIN}/api/v1/namespaces"
    echo
    log_info "🔧 Management commands:"
    log_info "  View component status: kubectl get all -n ${TEKTON_NAMESPACE}"
    log_info "  View Ingress: kubectl get ingress -n ${TEKTON_NAMESPACE}"
    log_info "  View logs: kubectl logs -l app=tekton-dashboard -n ${TEKTON_NAMESPACE} -f"
    echo
    log_info "📖 Next steps:"
    log_info "  1. Access Dashboard: http://${TEKTON_DOMAIN}/"
    log_info "  2. View test Pipeline execution results"
    log_info "  3. Continue to Stage 2: ./scripts/en/install/02-install-tekton-triggers.sh"
    echo
    log_warning "⚠️  Important notes:"
    log_warning "  - If access issues occur, check DNS resolution or add hosts entry"
    log_warning "  - Production environments should configure HTTPS and authentication"
    log_warning "  - Regularly backup Tekton configurations and data"
    echo
    print_separator
    log_success "Stage 1 deployment completed! Ready for Stage 2..."
    print_separator
}

# Main execution
main() {
    print_header "Tekton Core Infrastructure Installation - Stage 1"
    log_info "Starting Tekton core infrastructure components installation..."
    log_info "Includes: Ingress Controller + Tekton Pipelines + Dashboard"
    echo
    
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
    print_installation_summary
}

# Execute main function
main "$@" 