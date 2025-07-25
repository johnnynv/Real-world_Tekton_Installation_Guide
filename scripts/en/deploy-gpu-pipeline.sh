#!/bin/bash

set -euo pipefail

# GPU Scientific Computing Pipeline Deployment Script
# One-click deployment script for migrating GitHub Actions workflow to Tekton

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_banner() {
    echo -e "${BLUE}"
    echo "========================================================"
    echo "   GPU Scientific Computing Tekton Pipeline Deployment"
    echo "   Migration from GitHub Actions to Tekton"
    echo "========================================================"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking deployment prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check kubeconfig."
        exit 1
    fi
    
    # Check namespace
    if ! kubectl get namespace tekton-pipelines &> /dev/null; then
        log_warning "tekton-pipelines namespace does not exist, creating..."
        kubectl create namespace tekton-pipelines
    fi
    
    # Check Tekton installation
    if ! kubectl get crd pipelines.tekton.dev &> /dev/null; then
        log_error "Tekton Pipelines not installed. Please install Tekton first."
        log_info "Installation command: kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml"
        exit 1
    fi
    
    # Check Tekton Triggers
    if ! kubectl get crd eventlisteners.triggers.tekton.dev &> /dev/null; then
        log_warning "Tekton Triggers not installed, installing automatically..."
        kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
        kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
    fi
    
    # Check GPU support
    GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$GPU_NODES" -eq 0 ]; then
        log_warning "No GPU nodes detected with labels. Please ensure GPU nodes are properly labeled."
        log_info "Label example: kubectl label nodes <node-name> accelerator=nvidia-tesla-gpu"
    else
        log_success "Detected $GPU_NODES GPU nodes"
    fi
    
    log_success "Prerequisites check completed"
}

# Deploy RBAC configuration
deploy_rbac() {
    log_info "Deploying RBAC configuration..."
    
    local rbac_file="examples/triggers/gpu-pipeline-rbac.yaml"
    if [ ! -f "$rbac_file" ]; then
        log_error "RBAC configuration file not found: $rbac_file"
        exit 1
    fi
    
    # Generate random webhook secret
    WEBHOOK_SECRET=$(openssl rand -base64 32)
    log_info "Generating GitHub webhook secret..."
    
    # Replace placeholder
    sed "s|<BASE64_ENCODED_WEBHOOK_SECRET>|$(echo -n "$WEBHOOK_SECRET" | base64 -w 0)|g" "$rbac_file" | kubectl apply -f -
    
    log_success "RBAC configuration deployed"
    log_info "Please configure the following webhook secret in GitHub repository settings:"
    echo -e "${YELLOW}$WEBHOOK_SECRET${NC}"
}

# Deploy Tasks
deploy_tasks() {
    log_info "Deploying Tekton Tasks..."
    
    local tasks=(
        "examples/tasks/gpu-env-preparation-task.yaml"
        "examples/tasks/gpu-papermill-execution-task.yaml"
        "examples/tasks/jupyter-nbconvert-task.yaml"
        "examples/tasks/pytest-execution-task.yaml"
    )
    
    for task_file in "${tasks[@]}"; do
        if [ -f "$task_file" ]; then
            log_info "Deploying Task: $(basename "$task_file")"
            kubectl apply -f "$task_file"
        else
            log_error "Task file not found: $task_file"
            exit 1
        fi
    done
    
    log_success "All Tasks deployed successfully"
}

# Deploy Pipeline
deploy_pipeline() {
    log_info "Deploying GPU Scientific Computing Pipeline..."
    
    local pipeline_file="examples/pipelines/gpu-scientific-computing-pipeline.yaml"
    if [ ! -f "$pipeline_file" ]; then
        log_error "Pipeline file not found: $pipeline_file"
        exit 1
    fi
    
    kubectl apply -f "$pipeline_file"
    log_success "Pipeline deployed successfully"
}

# Deploy Triggers
deploy_triggers() {
    log_info "Deploying Tekton Triggers..."
    
    local trigger_file="examples/triggers/gpu-pipeline-trigger-template.yaml"
    if [ ! -f "$trigger_file" ]; then
        log_error "Trigger file not found: $trigger_file"
        exit 1
    fi
    
    kubectl apply -f "$trigger_file"
    log_success "Triggers deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment status..."
    
    # Check Tasks
    log_info "Checking Tasks..."
    kubectl get tasks -n tekton-pipelines | grep -E "(gpu-env-preparation|gpu-papermill-execution|jupyter-nbconvert|pytest-execution)"
    
    # Check Pipeline
    log_info "Checking Pipeline..."
    kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines
    
    # Check EventListener
    log_info "Checking EventListener..."
    kubectl get eventlistener gpu-scientific-computing-eventlistener -n tekton-pipelines
    
    # Get EventListener service information
    EVENTLISTENER_SERVICE=$(kubectl get svc -n tekton-pipelines -l eventlistener=gpu-scientific-computing-eventlistener -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    
    if [ "$EVENTLISTENER_SERVICE" != "not-found" ]; then
        EXTERNAL_IP=$(kubectl get svc "$EVENTLISTENER_SERVICE" -n tekton-pipelines -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
        EXTERNAL_PORT=$(kubectl get svc "$EVENTLISTENER_SERVICE" -n tekton-pipelines -o jsonpath='{.spec.ports[0].port}')
        
        log_success "EventListener service created"
        log_info "Service name: $EVENTLISTENER_SERVICE"
        log_info "External IP: $EXTERNAL_IP"
        log_info "Port: $EXTERNAL_PORT"
        
        if [ "$EXTERNAL_IP" != "pending" ] && [ "$EXTERNAL_IP" != "" ]; then
            log_info "Webhook URL: http://$EXTERNAL_IP:$EXTERNAL_PORT"
        else
            log_warning "External IP is still pending, check later with 'kubectl get svc -n tekton-pipelines'"
        fi
    else
        log_warning "EventListener service not found"
    fi
    
    log_success "Deployment verification completed"
}

# Create test PipelineRun
create_test_run() {
    log_info "Creating test PipelineRun..."
    
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
    value: "https://github.com/your-org/your-repo.git"  # Replace with actual repository
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
    
    log_success "Test PipelineRun created"
    log_info "Use the following commands to monitor execution:"
    echo "  kubectl get pipelineruns -n tekton-pipelines"
    echo "  kubectl logs -f -n tekton-pipelines <pipelinerun-name>"
}

# Show next configuration steps
show_next_steps() {
    echo -e "\n${GREEN}🎉 GPU Scientific Computing Pipeline deployment completed!${NC}\n"
    
    echo -e "${BLUE}Next Configuration Steps:${NC}"
    echo "1. Configure GitHub Repository Webhook:"
    echo "   - Go to repository Settings > Webhooks"
    echo "   - Add new Webhook"
    echo "   - Payload URL: http://YOUR_EXTERNAL_IP:8080"
    echo "   - Content type: application/json"
    echo "   - Secret: (use the generated secret above)"
    echo "   - Select 'Just the push event' or 'Send me everything'"
    
    echo -e "\n2. Verify GPU Node Configuration:"
    echo "   kubectl get nodes -l accelerator=nvidia-tesla-gpu"
    echo "   kubectl describe node <gpu-node-name>"
    
    echo -e "\n3. Check Storage Class Configuration:"
    echo "   kubectl get storageclass"
    echo "   kubectl get pv"
    
    echo -e "\n4. Monitor Pipeline Execution:"
    echo "   kubectl get pipelineruns -n tekton-pipelines"
    echo "   kubectl get pods -n tekton-pipelines"
    
    echo -e "\n5. View Logs:"
    echo "   kubectl logs -f -n tekton-pipelines <pod-name>"
    
    echo -e "\n${YELLOW}Important Notes:${NC}"
    echo "- Ensure GPU nodes have sufficient resources"
    echo "- Adjust storage class configuration based on your environment"
    echo "- Modify GPU memory and CPU limits as needed"
    echo "- Monitor Pipeline performance and resource usage regularly"
}

# Main function
main() {
    print_banner
    
    log_info "Starting GPU Scientific Computing Tekton Pipeline deployment..."
    
    check_prerequisites
    deploy_rbac
    deploy_tasks
    deploy_pipeline
    deploy_triggers
    verify_deployment
    
    # Ask if user wants to create test run
    echo -e "\n${YELLOW}Create a test PipelineRun? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        create_test_run
    fi
    
    show_next_steps
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'log_error "An error occurred during deployment. Please check logs and retry."' ERR

# Execute main function
main "$@" 