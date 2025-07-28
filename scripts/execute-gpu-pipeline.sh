#!/bin/bash

set -euo pipefail

# GPU Scientific Computing Pipeline Execution Script
# Manual execution and monitoring script for testing GPU pipeline

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
    echo "   GPU Scientific Computing Pipeline Manual Execution"
    echo "   Test and verify the complete notebook execution workflow"
    echo "=================================================================="
    echo -e "${NC}"
}

# Check if pipeline exists
check_pipeline_exists() {
    log_info "Checking if GPU pipeline exists..."
    
    if kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines &>/dev/null; then
        log_success "GPU pipeline found"
    else
        log_error "GPU pipeline not found. Please run deploy-complete-pipeline.sh first"
        exit 1
    fi
}

# Check workspace PVCs
check_workspaces() {
    log_info "Checking workspace PVCs..."
    
    local pvc_names=("source-code-workspace" "shared-artifacts-workspace" "gpu-cache-workspace" "test-execution-workspace")
    local missing_pvcs=()
    
    for pvc in "${pvc_names[@]}"; do
        if ! kubectl get pvc "$pvc" -n tekton-pipelines &>/dev/null; then
            missing_pvcs+=("$pvc")
        fi
    done
    
    if [ ${#missing_pvcs[@]} -eq 0 ]; then
        log_success "All workspace PVCs found"
    else
        log_warning "Missing PVCs: ${missing_pvcs[*]}"
        log_info "Creating missing PVCs..."
        kubectl apply -f examples/workspaces/gpu-pipeline-workspaces.yaml
        sleep 5
    fi
}

# Execute the pipeline
execute_pipeline() {
    log_info "Executing GPU scientific computing pipeline..."
    
    # Generate unique run name
    RUN_NAME="gpu-scrna-analysis-$(date +%Y%m%d-%H%M%S)"
    
    # Create PipelineRun from template
    sed "s/gpu-scrna-analysis-manual-run/${RUN_NAME}/" examples/runs/gpu-pipeline-manual-run.yaml | kubectl apply -f -
    
    log_success "Pipeline execution started: ${RUN_NAME}"
    echo "🎯 PipelineRun name: ${RUN_NAME}"
    
    return 0
}

# Monitor pipeline execution
monitor_pipeline() {
    local run_name="$1"
    log_info "Monitoring pipeline execution: ${run_name}"
    
    echo "🔍 Use the following commands to monitor progress:"
    echo ""
    echo "📊 Overall status:"
    echo "   kubectl get pipelinerun ${run_name} -n tekton-pipelines -w"
    echo ""
    echo "📋 Task details:"
    echo "   kubectl get taskruns -l tekton.dev/pipelineRun=${run_name} -n tekton-pipelines"
    echo ""
    echo "📖 Logs (replace <task-name> with actual task):"
    echo "   kubectl logs -f \$(kubectl get pods -l tekton.dev/pipelineRun=${run_name} -o name | head -1) -n tekton-pipelines"
    echo ""
    echo "🌐 Dashboard URL:"
    
    # Get dashboard info
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    DASHBOARD_PORT=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "pending")
    
    if [ "$DASHBOARD_PORT" != "pending" ]; then
        echo "   http://${NODE_IP}:${DASHBOARD_PORT}"
    else
        echo "   Dashboard port pending"
    fi
    
    echo ""
    echo "⏱️  Expected execution time: 30-60 minutes (depending on GPU performance)"
    echo ""
}

# Show execution results
show_results() {
    local run_name="$1"
    log_info "Checking execution results..."
    
    # Check if pipeline completed
    local status=$(kubectl get pipelinerun "${run_name}" -n tekton-pipelines -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    
    case "$status" in
        "True")
            log_success "Pipeline execution completed successfully!"
            echo ""
            echo "📁 Generated artifacts should be available in the shared-artifacts-workspace PVC:"
            echo "   - executed_scrna_notebook.ipynb (executed notebook)"
            echo "   - executed_scrna_notebook.html (HTML report)"
            echo "   - coverage.xml (test coverage report)"
            echo "   - pytest_results.xml (JUnit test results)"
            echo "   - pytest_report.html (HTML test report)"
            ;;
        "False")
            log_error "Pipeline execution failed!"
            echo ""
            echo "🔍 Check logs with:"
            echo "   kubectl describe pipelinerun ${run_name} -n tekton-pipelines"
            ;;
        "Unknown")
            log_warning "Pipeline status unknown or still running"
            ;;
    esac
}

# Extract artifacts from workspace
extract_artifacts() {
    local run_name="$1"
    log_info "Extracting artifacts from workspace..."
    
    # Create local artifacts directory
    mkdir -p "artifacts/${run_name}"
    
    # Get a pod that has the shared workspace mounted
    local pod_name=$(kubectl get pods -l tekton.dev/pipelineRun="${run_name}" -n tekton-pipelines -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$pod_name" ]; then
        log_info "Attempting to extract files from pod: ${pod_name}"
        
        # Try to copy artifacts (this may not work if pod is terminated)
        kubectl cp "tekton-pipelines/${pod_name}:/workspace/shared/artifacts/" "artifacts/${run_name}/" 2>/dev/null || {
            log_warning "Cannot extract artifacts directly from pod (pod may be terminated)"
            log_info "Artifacts are stored in the shared-artifacts-workspace PVC"
        }
    else
        log_warning "No pods found for pipeline run"
    fi
}

# Main execution
main() {
    print_banner
    
    # Parse command line arguments
    local action="${1:-execute}"
    local run_name="${2:-}"
    
    case "$action" in
        "execute")
            check_pipeline_exists
            check_workspaces
            if execute_pipeline; then
                local new_run_name=$(kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
                monitor_pipeline "$new_run_name"
            fi
            ;;
        "monitor")
            if [ -z "$run_name" ]; then
                log_error "Please provide run name: $0 monitor <run-name>"
                exit 1
            fi
            monitor_pipeline "$run_name"
            ;;
        "results")
            if [ -z "$run_name" ]; then
                log_error "Please provide run name: $0 results <run-name>"
                exit 1
            fi
            show_results "$run_name"
            extract_artifacts "$run_name"
            ;;
        "list")
            log_info "Recent pipeline runs:"
            kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp
            ;;
        *)
            echo "Usage: $0 {execute|monitor|results|list} [run-name]"
            echo ""
            echo "Commands:"
            echo "  execute  - Start a new pipeline execution"
            echo "  monitor  - Monitor an existing pipeline run"
            echo "  results  - Check results of a pipeline run"
            echo "  list     - List recent pipeline runs"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@" 