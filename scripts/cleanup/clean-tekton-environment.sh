#!/bin/bash

set -euo pipefail

# Tekton Environment Complete Cleanup Script
# Thoroughly clean existing Tekton installation before fresh deployment

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
    echo "   Tekton Complete Environment Cleanup"
    echo "   Preparing for fresh installation"
    echo "=================================================================="
    echo -e "${NC}"
}

# Cleanup Tekton custom resources
cleanup_tekton_resources() {
    log_info "Cleaning up Tekton custom resources..."
    
    # Delete PipelineRuns
    log_info "Deleting PipelineRuns..."
    if kubectl get pipelineruns -n tekton-pipelines &>/dev/null; then
        kubectl delete pipelineruns --all -n tekton-pipelines --timeout=60s || log_warning "Some PipelineRuns deletion may have timed out"
    fi
    
    # Delete TaskRuns
    log_info "Deleting TaskRuns..."
    if kubectl get taskruns -n tekton-pipelines &>/dev/null; then
        kubectl delete taskruns --all -n tekton-pipelines --timeout=60s || log_warning "Some TaskRuns deletion may have timed out"
    fi
    
    # Delete EventListeners
    log_info "Deleting EventListeners..."
    if kubectl get eventlisteners -n tekton-pipelines &>/dev/null; then
        kubectl delete eventlisteners --all -n tekton-pipelines --timeout=60s || log_warning "Some EventListeners deletion may have timed out"
    fi
    
    # Delete TriggerTemplates
    log_info "Deleting TriggerTemplates..."
    if kubectl get triggertemplates -n tekton-pipelines &>/dev/null; then
        kubectl delete triggertemplates --all -n tekton-pipelines --timeout=60s || log_warning "Some TriggerTemplates deletion may have timed out"
    fi
    
    # Delete TriggerBindings
    log_info "Deleting TriggerBindings..."
    if kubectl get triggerbindings -n tekton-pipelines &>/dev/null; then
        kubectl delete triggerbindings --all -n tekton-pipelines --timeout=60s || log_warning "Some TriggerBindings deletion may have timed out"
    fi
    
    # Delete Pipelines
    log_info "Deleting Pipelines..."
    if kubectl get pipelines -n tekton-pipelines &>/dev/null; then
        kubectl delete pipelines --all -n tekton-pipelines --timeout=60s || log_warning "Some Pipelines deletion may have timed out"
    fi
    
    # Delete Tasks
    log_info "Deleting Tasks..."
    if kubectl get tasks -n tekton-pipelines &>/dev/null; then
        kubectl delete tasks --all -n tekton-pipelines --timeout=60s || log_warning "Some Tasks deletion may have timed out"
    fi
    
    log_success "Tekton custom resources cleanup completed"
}

# Cleanup Tekton installation
cleanup_tekton_installation() {
    log_info "Cleaning up Tekton installation..."
    
    # Delete Tekton Triggers
    log_info "Uninstalling Tekton Triggers..."
    kubectl delete --ignore-not-found=true -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml --timeout=120s || log_warning "Tekton Triggers deletion may have timed out"
    kubectl delete --ignore-not-found=true -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml --timeout=120s || log_warning "Tekton Triggers interceptors deletion may have timed out"
    
    # Delete Tekton Dashboard
    log_info "Uninstalling Tekton Dashboard..."
    kubectl delete --ignore-not-found=true -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml --timeout=120s || log_warning "Tekton Dashboard deletion may have timed out"
    
    # Delete Tekton Pipelines
    log_info "Uninstalling Tekton Pipelines..."
    kubectl delete --ignore-not-found=true -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml --timeout=120s || log_warning "Tekton Pipelines deletion may have timed out"
    
    log_success "Tekton installation cleanup completed"
}

# Cleanup namespaces
cleanup_namespaces() {
    log_info "Cleaning up namespaces..."
    
    # Check if tekton-pipelines namespace exists and delete it
    if kubectl get namespace tekton-pipelines &>/dev/null; then
        log_info "Deleting tekton-pipelines namespace..."
        kubectl delete namespace tekton-pipelines --timeout=180s || log_warning "Namespace deletion may have timed out"
        
        # Wait for namespace to be completely removed
        log_info "Waiting for namespace to be completely removed..."
        while kubectl get namespace tekton-pipelines &>/dev/null; do
            echo -n "."
            sleep 5
        done
        echo ""
    fi
    
    # Check if tekton-pipelines-resolvers namespace exists and delete it
    if kubectl get namespace tekton-pipelines-resolvers &>/dev/null; then
        log_info "Deleting tekton-pipelines-resolvers namespace..."
        kubectl delete namespace tekton-pipelines-resolvers --timeout=180s || log_warning "Namespace deletion may have timed out"
        
        # Wait for namespace to be completely removed
        log_info "Waiting for namespace to be completely removed..."
        while kubectl get namespace tekton-pipelines-resolvers &>/dev/null; do
            echo -n "."
            sleep 5
        done
        echo ""
    fi
    
    log_success "Namespaces cleanup completed"
}

# Cleanup cluster-wide resources
cleanup_cluster_resources() {
    log_info "Cleaning up cluster-wide resources..."
    
    # Delete ClusterRoles and ClusterRoleBindings related to Tekton
    log_info "Cleaning up ClusterRoles and ClusterRoleBindings..."
    kubectl get clusterroles | grep tekton | awk '{print $1}' | xargs -r kubectl delete clusterrole --ignore-not-found=true || log_warning "Some ClusterRoles may not exist"
    kubectl get clusterrolebindings | grep tekton | awk '{print $1}' | xargs -r kubectl delete clusterrolebinding --ignore-not-found=true || log_warning "Some ClusterRoleBindings may not exist"
    
    # Delete ValidatingAdmissionConfiguration and MutatingAdmissionConfiguration
    log_info "Cleaning up admission configurations..."
    kubectl get validatingadmissionpolicies | grep tekton | awk '{print $1}' | xargs -r kubectl delete validatingadmissionpolicy --ignore-not-found=true || log_warning "Some ValidatingAdmissionPolicies may not exist"
    kubectl get mutatingwebhookconfigurations | grep tekton | awk '{print $1}' | xargs -r kubectl delete mutatingwebhookconfiguration --ignore-not-found=true || log_warning "Some MutatingWebhookConfigurations may not exist"
    kubectl get validatingwebhookconfigurations | grep tekton | awk '{print $1}' | xargs -r kubectl delete validatingwebhookconfiguration --ignore-not-found=true || log_warning "Some ValidatingWebhookConfigurations may not exist"
    
    # Delete CRDs related to Tekton
    log_info "Cleaning up Custom Resource Definitions..."
    kubectl get crd | grep tekton | awk '{print $1}' | xargs -r kubectl delete crd --ignore-not-found=true || log_warning "Some CRDs may not exist"
    kubectl get crd | grep triggers.tekton.dev | awk '{print $1}' | xargs -r kubectl delete crd --ignore-not-found=true || log_warning "Some Triggers CRDs may not exist"
    
    log_success "Cluster-wide resources cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_success=true
    
    # Check namespaces
    if kubectl get namespace tekton-pipelines &>/dev/null; then
        log_error "tekton-pipelines namespace still exists"
        cleanup_success=false
    fi
    
    if kubectl get namespace tekton-pipelines-resolvers &>/dev/null; then
        log_error "tekton-pipelines-resolvers namespace still exists"
        cleanup_success=false
    fi
    
    # Check cluster resources
    tekton_clusterroles=$(kubectl get clusterroles | grep tekton | wc -l)
    if [ "$tekton_clusterroles" -gt 0 ]; then
        log_warning "$tekton_clusterroles Tekton ClusterRoles still exist"
    fi
    
    tekton_crds=$(kubectl get crd | grep tekton | wc -l)
    if [ "$tekton_crds" -gt 0 ]; then
        log_warning "$tekton_crds Tekton CRDs still exist"
    fi
    
    if [ "$cleanup_success" = true ]; then
        log_success "Environment cleanup verification passed!"
        log_info "Ready for fresh Tekton installation"
    else
        log_error "Environment cleanup verification failed!"
        log_error "Manual intervention may be required"
        exit 1
    fi
}

# Cleanup temp files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Clean up any webhook secrets or temp files
    if [ -f "webhook-secret.txt" ]; then
        rm -f webhook-secret.txt
        log_info "Removed old webhook-secret.txt"
    fi
    
    log_success "Temporary files cleanup completed"
}

# Main execution
main() {
    print_banner
    
    log_warning "This will completely remove ALL Tekton components!"
    log_warning "This action cannot be undone."
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Execute cleanup steps
    cleanup_tekton_resources
    cleanup_tekton_installation
    cleanup_namespaces
    cleanup_cluster_resources
    cleanup_temp_files
    verify_cleanup
    
    log_success "🎊 Complete environment cleanup finished!"
    log_info "Environment is now ready for fresh Tekton installation"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

main "$@" 