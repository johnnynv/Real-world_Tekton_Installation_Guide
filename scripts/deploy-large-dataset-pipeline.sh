#!/bin/bash

# Large Dataset GPU Pipeline Deployment Script
# Support for downloading and processing large single-cell RNA sequencing datasets

set -e

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

log_header() {
    echo ""
    echo "=================================================================="
    echo "   $1"
    echo "=================================================================="
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking deployment prerequisites"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not installed or not in PATH"
        exit 1
    fi
    log_success "kubectl available"
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Kubernetes cluster connection normal"
    
    # Check Tekton namespace
    if ! kubectl get namespace tekton-pipelines &> /dev/null; then
        log_error "tekton-pipelines namespace does not exist"
        exit 1
    fi
    log_success "Tekton namespace exists"
    
    # Check GPU nodes
    GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers | wc -l)
    if [ "$GPU_NODES" -eq 0 ]; then
        log_warning "GPU nodes not found (label: accelerator=nvidia-tesla-gpu)"
        log_warning "Pipeline may not be able to schedule properly to GPU nodes"
    else
        log_success "Found $GPU_NODES GPU nodes"
    fi
}

# Check storage requirements
check_storage_requirements() {
    log_header "Checking storage requirements"
    
    # Get node storage information
    log_info "Checking node storage capacity..."
    kubectl top nodes 2>/dev/null || log_warning "Unable to get node resource usage"
    
    # Check StorageClass
    if kubectl get storageclass local-path &> /dev/null; then
        log_success "local-path StorageClass available"
    else
        log_warning "local-path StorageClass does not exist, PVC may not be created"
    fi
    
    log_info "Large dataset pipeline requires the following storage:"
    echo "  - Large dataset storage: 200Gi (for storing downloaded datasets)"
    echo "  - Dataset cache: 100Gi (for caching, improving reuse efficiency)"  
    echo "  - Processing workspace: 150Gi (for notebook execution and results)"
    echo "  - Total requirement: ~450Gi"
    echo ""
}

# Deploy large dataset storage resources
deploy_large_dataset_storage() {
    log_header "Deploying large dataset storage resources"
    
    log_info "Creating large dataset storage PVC..."
    if kubectl apply -f examples/workspaces/large-dataset-workspaces.yaml; then
        log_success "Large dataset storage PVC created successfully"
    else
        log_error "Large dataset storage PVC creation failed"
        exit 1
    fi
    
    # Wait for PVC binding
    log_info "Waiting for PVC binding..."
    sleep 5
    
    # Check PVC status
    log_info "Checking PVC status:"
    kubectl get pvc -n tekton-pipelines | grep -E "(large-dataset|dataset-cache|processing-workspace)" || true
    
    # Verify PVC binding status
    PENDING_PVCS=$(kubectl get pvc -n tekton-pipelines | grep -E "(large-dataset|dataset-cache|processing-workspace)" | grep Pending | wc -l)
    if [ "$PENDING_PVCS" -gt 0 ]; then
        log_warning "$PENDING_PVCS PVCs still in Pending status"
        log_warning "This may affect pipeline execution"
    else
        log_success "All large dataset storage PVCs successfully bound"
    fi
}

# Deploy task definitions
deploy_tasks() {
    log_header "Deploying task definitions"
    
    # Deploy large dataset download task
    log_info "Deploying large dataset download task..."
    if kubectl apply -f examples/tasks/large-dataset-download-task.yaml; then
        log_success "Large dataset download task deployed successfully"
    else
        log_error "Large dataset download task deployment failed"
        exit 1
    fi
    
    # Check existing tasks
    log_info "Checking if required tasks exist:"
    REQUIRED_TASKS=("gpu-env-preparation-fixed" "gpu-papermill-execution" "jupyter-nbconvert" "pytest-execution")
    
    for task in "${REQUIRED_TASKS[@]}"; do
        if kubectl get task "$task" -n tekton-pipelines &> /dev/null; then
            log_success "Task $task exists"
        else
            log_error "Required task $task does not exist"
            exit 1
        fi
    done
}

# Verify deployment
verify_deployment() {
    log_header "Verifying deployment"
    
    log_info "Checking deployed resources:"
    
    # Check tasks
    echo "📋 Task list:"
    kubectl get tasks -n tekton-pipelines | grep -E "(large-dataset|gpu-)" || true
    
    echo ""
    echo "💾 Storage resources:"
    kubectl get pvc -n tekton-pipelines | grep -E "(large-dataset|dataset-cache|processing-workspace)" || true
    
    echo ""
    echo "🏷️  GPU node information:"
    kubectl get nodes -l accelerator=nvidia-tesla-gpu -o wide || log_warning "No marked GPU nodes found"
}

# Show usage instructions
show_usage_instructions() {
    log_header "Usage Instructions"
    
    cat << 'EOF'
Large Dataset GPU Pipeline deployment completed!

🚀 Execute large dataset pipeline:
```bash
# Apply pipeline configuration
kubectl apply -f examples/pipelines/gpu-original-notebook-with-download.yaml

# Monitor execution status
kubectl get pipelinerun gpu-original-notebook-with-download -n tekton-pipelines -w

# View detailed status
kubectl describe pipelinerun gpu-original-notebook-with-download -n tekton-pipelines
```

📊 Custom dataset download:
```bash
# Modify pipeline parameters to use different datasets
# Edit parameters in examples/pipelines/gpu-original-notebook-with-download.yaml:
#   - dataset-url: Dataset download URL
#   - dataset-filename: Saved filename
#   - expected-dataset-size-mb: Expected file size (MB)
#   - download-timeout-minutes: Download timeout
#   - max-download-retries: Maximum retry attempts
```

🔍 Monitoring and debugging:
```bash
# View download task logs
kubectl logs -f -l tekton.dev/task=large-dataset-download -n tekton-pipelines

# View GPU execution task logs  
kubectl logs -f -l tekton.dev/task=gpu-papermill-execution -n tekton-pipelines

# Check storage usage
kubectl exec -it <pod-name> -n tekton-pipelines -- df -h
```

💾 Storage management:
```bash
# Clean cache data
kubectl exec -it <pod-name> -n tekton-pipelines -- rm -rf /workspace/datasets/cache/*

# View storage usage
kubectl get pvc -n tekton-pipelines
kubectl describe pvc large-dataset-storage -n tekton-pipelines
```

⚙️ Performance optimization recommendations:
- For very large datasets (>10GB), consider increasing storage configuration
- Adjust download timeout based on network environment
- Enable caching mechanism to avoid duplicate downloads
- Monitor GPU memory usage, adjust batch size if necessary

EOF
}

# Main function
main() {
    case "${1:-deploy}" in
        "deploy"|"")
            log_header "Starting Large Dataset GPU Pipeline deployment"
            check_prerequisites
            check_storage_requirements
            deploy_large_dataset_storage
            deploy_tasks
            verify_deployment
            show_usage_instructions
            log_success "Large Dataset GPU Pipeline deployment completed!"
            ;;
        "storage-only")
            check_prerequisites
            deploy_large_dataset_storage
            ;;
        "verify")
            verify_deployment
            ;;
        "clean")
            log_warning "Cleaning large dataset related resources..."
            kubectl delete -f examples/workspaces/large-dataset-workspaces.yaml --ignore-not-found=true
            kubectl delete task large-dataset-download -n tekton-pipelines --ignore-not-found=true
            log_success "Cleanup completed"
            ;;
        *)
            echo "Usage: $0 [deploy|storage-only|verify|clean]"
            echo ""
            echo "Options:"
            echo "  deploy       - Complete deployment (default)"
            echo "  storage-only - Deploy storage resources only"
            echo "  verify       - Verify deployment status"
            echo "  clean        - Clean related resources"
            ;;
    esac
}

# Execute main function
main "$@" 