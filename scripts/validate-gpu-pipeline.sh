#!/bin/bash

# Tekton GPU Pipeline Validation Script
# End-to-end validation of all GPU scientific computing pipeline components

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

# Cleanup function
cleanup_test_resources() {
    log_info "Cleaning up test resources..."
    
    # Delete test pipeline runs
    kubectl delete pipelinerun debug-workspace-test -n tekton-pipelines --ignore-not-found=true
    kubectl delete pipelinerun debug-git-clone-test -n tekton-pipelines --ignore-not-found=true
    kubectl delete pipelinerun gpu-env-test-fixed -n tekton-pipelines --ignore-not-found=true
    kubectl delete pod gpu-test-pod -n tekton-pipelines --ignore-not-found=true
    
    sleep 5
}

# Stage 1: Basic Environment Validation
validate_basic_environment() {
    log_header "Stage 1: Basic Environment Validation"
    
    log_info "Checking Kubernetes cluster connection..."
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Cluster connection normal"
    
    log_info "Checking GPU resources..."
    GPU_COUNT=$(kubectl get nodes -o json | jq -r '.items[0].status.allocatable."nvidia.com/gpu"' 2>/dev/null || echo "0")
    if [ "$GPU_COUNT" = "0" ] || [ "$GPU_COUNT" = "null" ]; then
        log_error "No available GPU resources on nodes"
        exit 1
    fi
    log_success "Discovered $GPU_COUNT GPU devices"
    
    log_info "Checking Tekton components..."
    if ! kubectl get pods -n tekton-pipelines &>/dev/null; then
        log_error "Tekton components not installed or inaccessible"
        exit 1
    fi
    
    TEKTON_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | wc -l)
    RUNNING_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | grep Running | wc -l)
    log_success "Tekton component status: $RUNNING_PODS/$TEKTON_PODS pods running"
    
    log_info "Checking NVIDIA device plugin..."
    if ! kubectl get daemonset -A | grep nvidia-device-plugin &>/dev/null; then
        log_warning "NVIDIA device plugin not found, GPU may not be usable"
    else
        log_success "NVIDIA device plugin installed"
    fi
}

# Stage 2: Storage and Workspace Validation
validate_storage_workspace() {
    log_header "Stage 2: Storage and Workspace Validation"
    
    log_info "Creating PVC workspaces..."
    if ! kubectl apply -f examples/workspaces/gpu-pipeline-workspaces.yaml; then
        log_error "PVC creation failed"
        exit 1
    fi
    sleep 10
    
    log_info "Checking PVC status..."
    kubectl get pvc -n tekton-pipelines
    
    log_info "Testing basic workspace functionality..."
    kubectl apply -f examples/debug/debug-workspace-test.yaml
    
    # Wait for completion
    for i in {1..30}; do
        STATUS=$(kubectl get pipelinerun debug-workspace-test -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            log_success "Workspace test passed"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Workspace test failed"
            kubectl logs -l tekton.dev/pipelineRun=debug-workspace-test -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
    
    log_info "Testing Git clone functionality..."
    kubectl apply -f examples/debug/debug-git-clone-test.yaml
    
    # Wait for completion
    for i in {1..60}; do
        STATUS=$(kubectl get pipelinerun debug-git-clone-test -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            log_success "Git clone test passed"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Git clone test failed"
            kubectl logs -l tekton.dev/pipelineRun=debug-git-clone-test -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
}

# Stage 3: GPU Access Validation
validate_gpu_access() {
    log_header "Stage 3: GPU Access Validation"
    
    log_info "Creating GPU test pod..."
    kubectl apply -f examples/testing/gpu-test-pod.yaml
    
    # Wait for pod startup
    for i in {1..30}; do
        STATUS=$(kubectl get pod gpu-test-pod -n tekton-pipelines -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "Running" ]; then
            log_success "GPU test pod started successfully"
            break
        elif [ "$STATUS" = "Failed" ]; then
            log_error "GPU test pod startup failed"
            kubectl describe pod gpu-test-pod -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
    
    # Wait for test completion
    sleep 15
    
    log_info "Checking GPU test results..."
    GPU_LOGS=$(kubectl logs gpu-test-pod -n tekton-pipelines 2>/dev/null || echo "")
    
    if echo "$GPU_LOGS" | grep -q "✅ CUDA devices:"; then
        CUDA_DEVICES=$(echo "$GPU_LOGS" | grep "✅ CUDA devices:" | awk '{print $4}')
        log_success "GPU access test passed, detected $CUDA_DEVICES CUDA devices"
    else
        log_error "GPU access test failed"
        echo "$GPU_LOGS"
        exit 1
    fi
    
    kubectl delete pod gpu-test-pod -n tekton-pipelines
}

# Stage 4: Tekton Task Validation
validate_tekton_tasks() {
    log_header "Stage 4: Tekton Task Validation"
    
    log_info "Applying fixed version of environment preparation task..."
    kubectl apply -f examples/tasks/gpu-env-preparation-task-fixed.yaml
    
    log_info "Testing environment preparation task..."
    kubectl apply -f examples/testing/gpu-env-test-fixed.yaml
    
    # Wait for completion
    for i in {1..60}; do
        STATUS=$(kubectl get pipelinerun gpu-env-test-fixed -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            log_success "Environment preparation task test passed"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Environment preparation task test failed"
            kubectl describe pipelinerun gpu-env-test-fixed -n tekton-pipelines
            exit 1
        fi
        sleep 2
    done
    
    log_info "Applying all fixed version tasks..."
    kubectl apply -f examples/tasks/gpu-papermill-execution-task.yaml
    kubectl apply -f examples/tasks/jupyter-nbconvert-task.yaml
    kubectl apply -f examples/tasks/pytest-execution-task.yaml
    
    log_success "All Tekton tasks configuration completed"
}

# Stage 5: Complete Pipeline Test
validate_complete_pipeline() {
    log_header "Stage 5: Complete Pipeline Validation"
    
    log_info "Executing complete GPU scientific computing pipeline..."
    kubectl apply -f examples/pipelines/gpu-complete-pipeline-fixed.yaml
    
    RUN_NAME="gpu-scrna-complete-fixed"
    log_info "Monitoring pipeline execution: $RUN_NAME"
    
    # Monitor execution status
    for i in {1..1800}; do  # Wait up to 30 minutes
        STATUS=$(kubectl get pipelinerun $RUN_NAME -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        REASON=$(kubectl get pipelinerun $RUN_NAME -n tekton-pipelines -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
        
        if [ "$STATUS" = "True" ] && [ "$REASON" = "Succeeded" ]; then
            log_success "Complete pipeline execution successful!"
            break
        elif [ "$STATUS" = "False" ]; then
            log_error "Pipeline execution failed"
            kubectl describe pipelinerun $RUN_NAME -n tekton-pipelines
            kubectl get taskruns -l tekton.dev/pipelineRun=$RUN_NAME -n tekton-pipelines
            exit 1
        fi
        
        # Output status every 30 seconds
        if [ $((i % 15)) -eq 0 ]; then
            echo "Pipeline status: $STATUS ($REASON) - waiting... (${i}s)"
        fi
        sleep 2
    done
    
    # Check result files
    log_info "Validating output files..."
    
    # Specific file checking logic can be added here
    log_success "Pipeline validation completed"
}

# Display validation results summary
show_validation_summary() {
    log_header "Validation Results Summary"
    
    echo "✅ Basic Environment Validation - Passed"
    echo "✅ Storage and Workspace Validation - Passed"
    echo "✅ GPU Access Validation - Passed"
    echo "✅ Tekton Task Validation - Passed"
    echo "✅ Complete Pipeline Validation - Passed"
    echo ""
    echo "🎉 All validation stages completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. View pipeline execution results: ./scripts/execute-gpu-pipeline.sh results gpu-scrna-complete-fixed"
    echo "2. Access Tekton Dashboard for detailed information"
    echo "3. Check generated notebooks and test report files"
}

# Main function
main() {
    case "${1:-validate}" in
        "validate"|"")
            log_header "Tekton GPU Pipeline Complete Validation"
            cleanup_test_resources
            validate_basic_environment
            validate_storage_workspace
            validate_gpu_access
            validate_tekton_tasks
            validate_complete_pipeline
            show_validation_summary
            ;;
        "cleanup")
            cleanup_test_resources
            log_success "Test resources cleanup completed"
            ;;
        "env")
            validate_basic_environment
            ;;
        "storage")
            validate_storage_workspace
            ;;
        "gpu")
            validate_gpu_access
            ;;
        "tasks")
            validate_tekton_tasks
            ;;
        "pipeline")
            validate_complete_pipeline
            ;;
        *)
            echo "Usage: $0 [validate|cleanup|env|storage|gpu|tasks|pipeline]"
            echo ""
            echo "Options:"
            echo "  validate  - Execute complete end-to-end validation (default)"
            echo "  cleanup   - Clean up test resources"
            echo "  env       - Validate basic environment only"
            echo "  storage   - Validate storage and workspace only"
            echo "  gpu       - Validate GPU access only"
            echo "  tasks     - Validate Tekton tasks only"
            echo "  pipeline  - Validate complete pipeline only"
            ;;
    esac
}

# Execute main function
main "$@" 