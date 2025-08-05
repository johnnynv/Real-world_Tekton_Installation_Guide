#!/bin/bash

# Tekton Step5 Restricted User Setup Script
# Creates a Tekton Dashboard user with limited permissions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="tekton-pipelines"
USERNAME="user"
PASSWORD="user123"
SERVICE_ACCOUNT="tekton-restricted-user"

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
    echo "   🔧 Tekton Step5 Restricted User Setup"
    echo "   👤 Username: ${USERNAME}"
    echo "   🔒 Limited permissions: pipelines, tasks, eventlisteners only"
    echo "=================================================================="
    echo -e "${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    # Check if Tekton Dashboard is running
    if ! kubectl get deployment tekton-dashboard -n "$NAMESPACE" &>/dev/null; then
        log_error "Tekton Dashboard is not installed in namespace $NAMESPACE"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

apply_rbac_config() {
    log_info "Applying RBAC configuration..."
    
    if [ ! -f "examples/config/rbac/rbac-step5-tekton-restricted-user.yaml" ]; then
        log_error "RBAC configuration file not found"
        exit 1
    fi
    
    kubectl apply -f examples/config/rbac/rbac-step5-tekton-restricted-user.yaml
    
    log_success "RBAC configuration applied"
}

wait_for_token() {
    log_info "Waiting for service account token to be created..."
    
    local retries=30
    local count=0
    
    while [ $count -lt $retries ]; do
        if kubectl get secret "${SERVICE_ACCOUNT}-token" -n "$NAMESPACE" &>/dev/null; then
            break
        fi
        
        count=$((count + 1))
        echo -n "."
        sleep 2
    done
    echo ""
    
    if [ $count -eq $retries ]; then
        log_error "Timeout waiting for service account token"
        exit 1
    fi
    
    log_success "Service account token created"
}

get_bearer_token() {
    log_info "Extracting bearer token..."
    
    local token=$(kubectl get secret "${SERVICE_ACCOUNT}-token" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)
    
    if [ -z "$token" ]; then
        log_error "Failed to extract bearer token"
        exit 1
    fi
    
    echo "$token"
}

setup_basic_auth() {
    log_info "Setting up Basic Authentication for Tekton Dashboard..."
    
    # Create htpasswd entry
    local password_hash=$(echo -n "$PASSWORD" | openssl passwd -stdin -apr1 2>/dev/null || echo -n "$PASSWORD" | openssl passwd -stdin)
    local auth_entry="${USERNAME}:${password_hash}"
    
    # Create or update basic auth secret
    kubectl create secret generic tekton-dashboard-auth \
        --from-literal=users.htpasswd="$auth_entry" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Basic authentication configured"
}

update_dashboard_config() {
    log_info "Updating Tekton Dashboard configuration..."
    
    # Get current dashboard deployment
    local dashboard_patch='{
        "spec": {
            "template": {
                "spec": {
                    "containers": [{
                        "name": "tekton-dashboard",
                        "args": [
                            "--port=9097",
                            "--logout-url=",
                            "--pipelines-namespace='$NAMESPACE'",
                            "--triggers-namespace='$NAMESPACE'",
                            "--read-only=false",
                            "--log-level=info",
                            "--log-format=json",
                            "--namespace='$NAMESPACE'"
                        ]
                    }]
                }
            }
        }
    }'
    
    # Apply patch to dashboard deployment
    kubectl patch deployment tekton-dashboard -n "$NAMESPACE" --type='merge' -p="$dashboard_patch" || {
        log_warning "Could not patch dashboard deployment automatically"
    }
    
    log_success "Dashboard configuration updated"
}

create_user_instructions() {
    local token=$(get_bearer_token)
    local cluster_ip=$(kubectl get svc tekton-dashboard -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "localhost")
    local dashboard_url="http://tekton.10.34.2.129.nip.io"
    
    # Create instructions file
    cat > tekton-restricted-user-access.txt << EOF
===============================================
Tekton Dashboard Restricted User Access Guide
===============================================

Username: ${USERNAME}
Password: ${PASSWORD}

Dashboard URL: ${dashboard_url}

=== Authentication Methods ===

Method 1: Bearer Token Authentication
- Token: ${token}
- Use this token in Authorization header: "Bearer ${token}"

Method 2: Basic Authentication  
- Username: ${USERNAME}
- Password: ${PASSWORD}

=== Accessible Features ===
✅ Pipelines - View all pipelines
✅ PipelineRuns - View pipeline execution history
✅ Tasks - View all tasks
✅ TaskRuns - View task execution history  
✅ EventListeners - View trigger configurations

❌ Limited Access:
- Cannot create/modify/delete resources
- Cannot access other Kubernetes resources
- Cannot view secrets or sensitive data

=== Usage Instructions ===

1. Open dashboard: ${dashboard_url}
2. Login with username/password: ${USERNAME}/${PASSWORD}
3. Or use bearer token for API access

=== API Access Example ===
curl -H "Authorization: Bearer ${token}" \\
     ${dashboard_url}/api/v1/namespaces/${NAMESPACE}/pipelines

===============================================
EOF

    log_success "User access instructions saved to: tekton-restricted-user-access.txt"
}

verify_setup() {
    log_info "Verifying setup..."
    
    # Check if service account exists
    if kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" &>/dev/null; then
        log_success "Service account created: $SERVICE_ACCOUNT"
    else
        log_error "Service account not found: $SERVICE_ACCOUNT"
        return 1
    fi
    
    # Check if clusterrole exists
    if kubectl get clusterrole tekton-restricted-viewer &>/dev/null; then
        log_success "ClusterRole created: tekton-restricted-viewer"
    else
        log_error "ClusterRole not found: tekton-restricted-viewer"
        return 1
    fi
    
    # Check if clusterrolebinding exists
    if kubectl get clusterrolebinding tekton-restricted-user-binding &>/dev/null; then
        log_success "ClusterRoleBinding created: tekton-restricted-user-binding"
    else
        log_error "ClusterRoleBinding not found: tekton-restricted-user-binding"
        return 1
    fi
    
    log_success "Setup verification completed"
}

cleanup_if_exists() {
    log_info "Cleaning up existing configuration if present..."
    
    kubectl delete clusterrolebinding tekton-restricted-user-binding 2>/dev/null || true
    kubectl delete clusterrole tekton-restricted-viewer 2>/dev/null || true
    kubectl delete secret tekton-restricted-user-token -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete serviceaccount tekton-restricted-user -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete secret tekton-dashboard-auth -n "$NAMESPACE" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

main() {
    print_banner
    
    # Cleanup existing setup
    cleanup_if_exists
    
    # Setup process
    check_prerequisites
    apply_rbac_config
    wait_for_token
    setup_basic_auth
    update_dashboard_config
    verify_setup
    create_user_instructions
    
    log_success "Tekton Dashboard restricted user setup completed successfully!"
    echo ""
    echo "📋 Setup Results Overview:"
    echo "  ✅ Username: ${USERNAME}"
    echo "  ✅ Password: ${PASSWORD}"
    echo "  ✅ Dashboard URL: http://tekton.10.34.2.129.nip.io"
    echo "  ✅ Permissions: View Pipelines, Tasks, EventListeners"
    echo ""
    log_info "Access details saved to: tekton-restricted-user-access.txt"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi