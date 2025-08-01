#!/bin/bash

set -euo pipefail

# Fix Tekton Dashboard Read-Only Mode Issues
# Resolves missing menus and limited namespace access

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
    echo "   Tekton Dashboard Read-Only Mode Fix"
    echo "   Restores full Dashboard functionality"
    echo "=================================================================="
    echo -e "${NC}"
}

# Configuration
NAMESPACE="tekton-pipelines"
DEPLOYMENT_NAME="tekton-dashboard"

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we can access the cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

# Check if Dashboard deployment exists
check_dashboard_exists() {
    if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_error "Dashboard deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'"
        log_info "Please install Tekton Dashboard first:"
        log_info "  scripts/install/01-install-tekton-core.sh"
        exit 1
    fi
}

# Backup current configuration
backup_configuration() {
    log_info "Creating backup of current Dashboard configuration"
    
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o yaml > "dashboard-backup-$(date +%Y%m%d-%H%M%S).yaml"
    kubectl get clusterrolebinding tekton-dashboard-backend-view -o yaml >> "dashboard-backup-$(date +%Y%m%d-%H%M%S).yaml"
    
    log_success "Configuration backed up"
}

# Check current read-only status
check_readonly_status() {
    log_info "Checking current Dashboard configuration"
    
    local readonly_status
    readonly_status=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -o 'read-only=[^,]*' || echo "not-found")
    
    if [[ "$readonly_status" == *"read-only=true"* ]]; then
        log_warning "Dashboard is currently in read-only mode"
        return 0
    elif [[ "$readonly_status" == *"read-only=false"* ]]; then
        log_info "Dashboard read-only mode is already disabled"
        return 1
    else
        log_warning "Cannot determine read-only status, proceeding with fix"
        return 0
    fi
}

# Fix Dashboard deployment configuration
fix_deployment_config() {
    log_info "Updating Dashboard deployment to disable read-only mode"
    
    kubectl patch deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" --type='json' -p='[
      {
        "op": "replace",
        "path": "/spec/template/spec/containers/0/args",
        "value": [
          "--default-namespace=",
          "--external-logs=",
          "--log-format=json",
          "--log-level=info",
          "--logout-url=",
          "--namespaces=",
          "--pipelines-namespace=tekton-pipelines",
          "--port=9097",
          "--read-only=false",
          "--stream-logs=true",
          "--triggers-namespace=tekton-pipelines"
        ]
      }
    ]'
    
    log_success "Dashboard deployment configuration updated"
}

# Create comprehensive ClusterRole
create_comprehensive_clusterrole() {
    log_info "Creating comprehensive ClusterRole for Dashboard"
    
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-dashboard-backend-edit
  labels:
    app.kubernetes.io/component: dashboard
    app.kubernetes.io/part-of: tekton-dashboard
rules:
# Tekton resources full permissions
- apiGroups: ["tekton.dev"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["*"]
  verbs: ["*"]
# Kubernetes core resources permissions
- apiGroups: [""]
  resources: ["namespaces", "pods", "pods/log", "events", "configmaps", "secrets", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get", "list", "watch"]
# Additional permissions for extended functionality
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
EOF
    
    log_success "Comprehensive ClusterRole created"
}

# Update ClusterRoleBinding
update_clusterrolebinding() {
    log_info "Updating ClusterRoleBinding to use new ClusterRole"
    
    # Cannot patch roleRef, need to delete and recreate
    if kubectl get clusterrolebinding tekton-dashboard-backend-view &> /dev/null; then
        log_info "Deleting existing ClusterRoleBinding (roleRef cannot be patched)"
        kubectl delete clusterrolebinding tekton-dashboard-backend-view
    fi
    
    log_info "Creating new ClusterRoleBinding with updated ClusterRole"
    kubectl create clusterrolebinding tekton-dashboard-backend-view \
        --clusterrole=tekton-dashboard-backend-edit \
        --serviceaccount=tekton-pipelines:tekton-dashboard
    
    log_success "ClusterRoleBinding updated"
}

# Restart Dashboard deployment
restart_dashboard() {
    log_info "Restarting Dashboard deployment to apply changes"
    
    kubectl rollout restart deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"
    
    log_info "Waiting for Dashboard to be ready..."
    kubectl rollout status deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout=300s
    
    log_success "Dashboard restarted successfully"
}

# Verify the fix
verify_fix() {
    log_info "Verifying the fix..."
    
    # Check if deployment is running
    local ready_replicas
    ready_replicas=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$ready_replicas" -eq 0 ]; then
        log_error "Dashboard deployment is not ready"
        return 1
    fi
    
    # Check read-only status
    local readonly_status
    readonly_status=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -o 'read-only=[^,]*' || echo "not-found")
    
    if [[ "$readonly_status" == *"read-only=false"* ]]; then
        log_success "Read-only mode successfully disabled"
    else
        log_warning "Could not verify read-only mode status"
    fi
    
    # Check permissions
    local permissions_count
    permissions_count=$(kubectl auth can-i --list --as=system:serviceaccount:tekton-pipelines:tekton-dashboard 2>/dev/null | wc -l)
    
    if [ "$permissions_count" -gt 20 ]; then
        log_success "Dashboard permissions expanded successfully"
    else
        log_warning "Dashboard permissions may still be limited"
    fi
    
    log_success "Fix verification completed"
}

# Display access information
display_access_info() {
    log_info "Dashboard access information:"
    
    local node_ip
    node_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    local dashboard_url="https://tekton.${node_ip}.nip.io"
    
    echo
    log_success "Dashboard should now have full functionality:"
    log_info "  📍 URL: $dashboard_url"
    log_info "  👤 Username: admin"
    log_info "  🔑 Password: admin123"
    echo
    log_info "Expected features after fix:"
    log_info "  ✅ All namespaces visible"
    log_info "  ✅ Complete menu items (Pipelines, Tasks, Triggers, etc.)"
    log_info "  ✅ Create, edit, delete operations available"
    log_info "  ✅ Real-time logs and detailed information"
    log_info "  ✅ No more proxy errors"
    echo
    log_warning "Security note: Dashboard now has broader permissions for full functionality."
    log_warning "In production, consider implementing additional access controls."
}

# Main function
main() {
    print_banner
    
    # Validate environment
    check_kubectl
    check_dashboard_exists
    
    # Check if fix is needed
    if ! check_readonly_status; then
        log_info "Dashboard appears to be already configured correctly"
        read -p "Do you want to proceed anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Create backup
    backup_configuration
    
    # Apply fixes
    fix_deployment_config
    create_comprehensive_clusterrole
    update_clusterrolebinding
    restart_dashboard
    
    # Verify and display results
    verify_fix
    display_access_info
    
    log_success "Tekton Dashboard read-only mode fix completed successfully!"
}

# Run main function
main "$@"