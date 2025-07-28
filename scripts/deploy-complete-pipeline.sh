#!/bin/bash

set -euo pipefail

# GPU Scientific Computing Pipeline Complete Deployment Script
# One-click deployment for migrating GitHub Actions workflow to Tekton

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
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

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "   Tekton GPU Scientific Computing Pipeline Complete Deployment"
    echo "   One-click migration from GitHub Actions to Tekton"
    echo "=================================================================="
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check kubeconfig."
        exit 1
    fi
    
    # Check or create namespace
    if ! kubectl get namespace tekton-pipelines &> /dev/null; then
        log_info "Creating tekton-pipelines namespace..."
        kubectl create namespace tekton-pipelines
    fi
    
    log_success "Prerequisites check completed"
}

# Install Tekton Pipelines
install_tekton_pipelines() {
    log_info "Installing Tekton Pipelines..."
    
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
    kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
    
    log_success "Tekton Pipelines installation completed"
}

# Install Tekton Dashboard
install_tekton_dashboard() {
    log_info "Installing Tekton Dashboard..."
    
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
    kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
    
    # Configure NodePort access
    kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'
    
    log_success "Tekton Dashboard installation completed"
}

# Install Tekton Triggers
install_tekton_triggers() {
    log_info "Installing Tekton Triggers..."
    
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
    kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
    
    log_success "Tekton Triggers installation completed"
}

# Deploy RBAC configuration
deploy_rbac() {
    log_info "Deploying RBAC configuration..."
    
    kubectl apply -f examples/triggers/gpu-pipeline-rbac.yaml
    
    # Generate webhook secret
    WEBHOOK_SECRET=$(openssl rand -base64 32)
    kubectl create secret generic github-webhook-secret \
      --from-literal=webhook-secret="${WEBHOOK_SECRET}" \
      -n tekton-pipelines \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo "${WEBHOOK_SECRET}" > webhook-secret.txt
    log_success "RBAC configuration deployment completed"
    log_info "GitHub Webhook Secret: ${WEBHOOK_SECRET}"
    log_info "Secret saved to webhook-secret.txt"
}

# Deploy Workspaces
deploy_workspaces() {
    log_info "Deploying PVC Workspaces..."
    
    kubectl apply -f examples/workspaces/gpu-pipeline-workspaces.yaml
    
    # Wait for PVCs to be bound (for some storage classes)
    log_info "Waiting for PVCs to be ready..."
    sleep 10
    
    log_success "PVC Workspaces deployment completed"
}

# Deploy GPU Tasks
deploy_gpu_tasks() {
    log_info "Deploying GPU Tasks..."
    
    kubectl apply -f examples/tasks/gpu-env-preparation-task.yaml
    kubectl apply -f examples/tasks/gpu-papermill-execution-task.yaml
    kubectl apply -f examples/tasks/jupyter-nbconvert-task.yaml
    kubectl apply -f examples/tasks/pytest-execution-task.yaml
    
    log_success "GPU Tasks deployment completed"
}

# Deploy GPU Pipeline
deploy_gpu_pipeline() {
    log_info "Deploying GPU Pipeline..."
    
    kubectl apply -f examples/pipelines/gpu-scientific-computing-pipeline.yaml
    
    log_success "GPU Pipeline deployment completed"
}

# Deploy Triggers
deploy_triggers() {
    log_info "Deploying Triggers..."
    
    kubectl apply -f examples/triggers/gpu-pipeline-trigger-template.yaml
    
    log_success "Triggers deployment completed"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment status..."
    
    # Check Tasks
    log_info "Checking Tasks..."
    kubectl get tasks -n tekton-pipelines | grep -E "gpu-|jupyter-|pytest-"
    
    # Check Pipeline
    log_info "Checking Pipeline..."
    kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines
    
    # Check EventListener
    log_info "Checking EventListener..."
    kubectl get eventlistener -n tekton-pipelines
    
    # Get access URLs
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    DASHBOARD_PORT=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')
    
    log_success "Deployment verification completed"
    echo ""
    echo "🎉 Deployment completed! Access information:"
    echo "📊 Tekton Dashboard: http://${NODE_IP}:${DASHBOARD_PORT}"
    echo "🔑 GitHub Webhook Secret: $(cat webhook-secret.txt)"
}

# Print GitHub webhook configuration guide
print_webhook_guide() {
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    EVENTLISTENER_PORT=$(kubectl get svc -n tekton-pipelines | grep gpu-scientific-computing-eventlistener | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
    
    if [ -n "${EVENTLISTENER_PORT}" ]; then
        WEBHOOK_URL="http://${NODE_IP}:${EVENTLISTENER_PORT}"
    else
        WEBHOOK_URL="Pending EventListener service port"
    fi
    
    echo ""
    echo "📋 GitHub Webhook Configuration Guide:"
    echo "================================"
    echo "1. Go to your GitHub repository settings"
    echo "2. Select Webhooks > Add webhook"
    echo "3. Configure the following parameters:"
    echo "   Payload URL: ${WEBHOOK_URL}"
    echo "   Content type: application/json"
    echo "   Secret: $(cat webhook-secret.txt)"
    echo "   Events: Just the push event"
    echo "   Active: ✅ Checked"
    echo "================================"
    echo ""
    echo "🚀 Trigger conditions:"
    echo "- Push to main or develop branch"
    echo "- Commit message contains [gpu] or [notebook] tags"
    echo "- Modified files in notebooks/ directory"
}

# Main execution
main() {
    print_banner
    
    check_prerequisites
    install_tekton_pipelines
    install_tekton_dashboard
    install_tekton_triggers
    deploy_rbac
    deploy_workspaces
    deploy_gpu_tasks
    deploy_gpu_pipeline
    deploy_triggers
    verify_deployment
    print_webhook_guide
    
    log_success "🎊 Complete deployment successfully finished!"
}

# Execute main function
main "$@" 