#!/bin/bash

set -euo pipefail

# Tekton Step5 Restricted User Verification Script
# Quick verification script for user permissions and access

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SERVICE_ACCOUNT="tekton-restricted-user"
NAMESPACE="tekton-pipelines"
USERNAME="user"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "   🔍 Tekton Step5 Restricted User Verification"
    echo "   Checking permissions and access for user: ${USERNAME}"
    echo "=================================================================="
    echo -e "${NC}"
}

check_rbac_resources() {
    log_info "Checking RBAC resources..."
    
    local error_count=0
    
    # Check Service Account
    if kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" &>/dev/null; then
        log_success "Service Account exists: $SERVICE_ACCOUNT"
    else
        log_error "Service Account not found: $SERVICE_ACCOUNT"
        ((error_count++))
    fi
    
    # Check ClusterRole
    if kubectl get clusterrole tekton-restricted-viewer &>/dev/null; then
        log_success "ClusterRole exists: tekton-restricted-viewer"
    else
        log_error "ClusterRole not found: tekton-restricted-viewer"
        ((error_count++))
    fi
    
    # Check ClusterRoleBinding
    if kubectl get clusterrolebinding tekton-restricted-user-binding &>/dev/null; then
        log_success "ClusterRoleBinding exists: tekton-restricted-user-binding"
    else
        log_error "ClusterRoleBinding not found: tekton-restricted-user-binding"
        ((error_count++))
    fi
    
    # Check Secret
    if kubectl get secret tekton-restricted-user-token -n "$NAMESPACE" &>/dev/null; then
        log_success "Service Account token exists"
    else
        log_error "Service Account token not found"
        ((error_count++))
    fi
    
    return $error_count
}

verify_allowed_permissions() {
    log_info "Verifying allowed permissions..."
    
    local user_identity="system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
    local permissions=(
        "list:pipelines"
        "get:pipelines"
        "watch:pipelines"
        "list:pipelineruns"
        "get:pipelineruns"
        "watch:pipelineruns"
        "list:tasks"
        "get:tasks"
        "watch:tasks"
        "list:taskruns"
        "get:taskruns"
        "watch:taskruns"
        "list:eventlisteners"
        "get:eventlisteners"
        "watch:eventlisteners"
    )
    
    local success_count=0
    local total_count=${#permissions[@]}
    
    for permission in "${permissions[@]}"; do
        IFS=':' read -r verb resource <<< "$permission"
        if kubectl auth can-i "$verb" "$resource" --as="$user_identity" -n "$NAMESPACE" &>/dev/null; then
            echo -e "  ${GREEN}✅${NC} $verb $resource"
            ((success_count++))
        else
            echo -e "  ${RED}❌${NC} $verb $resource"
        fi
    done
    
    log_info "Allowed permissions: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        log_success "All required permissions are correctly configured"
        return 0
    else
        log_error "Some required permissions are missing"
        return 1
    fi
}

verify_restricted_permissions() {
    log_info "Verifying restricted permissions (should be denied)..."
    
    local user_identity="system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
    local restricted_permissions=(
        "create:pipelines"
        "update:pipelines"
        "delete:pipelines"
        "create:pipelineruns"
        "delete:pipelineruns"
        "patch:tasks"
        "delete:tasks"
        "list:secrets"
        "get:secrets"
        "create:serviceaccounts"
        "delete:namespaces"
    )
    
    local denied_count=0
    local total_count=${#restricted_permissions[@]}
    
    for permission in "${restricted_permissions[@]}"; do
        IFS=':' read -r verb resource <<< "$permission"
        if kubectl auth can-i "$verb" "$resource" --as="$user_identity" -n "$NAMESPACE" &>/dev/null; then
            echo -e "  ${RED}❌${NC} $verb $resource (SHOULD BE DENIED)"
        else
            echo -e "  ${GREEN}✅${NC} $verb $resource (correctly denied)"
            ((denied_count++))
        fi
    done
    
    log_info "Correctly restricted permissions: $denied_count/$total_count"
    
    if [ $denied_count -eq $total_count ]; then
        log_success "All restricted permissions are correctly denied"
        return 0
    else
        log_error "Some operations are allowed that should be restricted"
        return 1
    fi
}

check_dashboard_access() {
    log_info "Checking Tekton Dashboard access..."
    
    local dashboard_url="http://tekton.10.34.2.129.nip.io"
    
    if curl -s -o /dev/null -w "%{http_code}" "$dashboard_url" | grep -q "200\|302"; then
        log_success "Dashboard is accessible at: $dashboard_url"
        return 0
    else
        log_error "Dashboard is not accessible at: $dashboard_url"
        return 1
    fi
}

get_access_details() {
    log_info "Getting user access details..."
    
    local token=$(kubectl get secret tekton-restricted-user-token -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "Token not available")
    local dashboard_url="http://tekton.10.34.2.129.nip.io"
    
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW} Restricted User Access Information${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${BLUE}Dashboard URL:${NC} $dashboard_url"
    echo -e "${BLUE}Username:${NC} $USERNAME"
    echo -e "${BLUE}Password:${NC} user123"
    echo ""
    echo -e "${BLUE}Bearer Token (for API access):${NC}"
    echo "$token"
    echo ""
    echo -e "${BLUE}Accessible Resources:${NC}"
    echo "  ✅ Pipelines (view only)"
    echo "  ✅ PipelineRuns (view only)"
    echo "  ✅ Tasks (view only)"
    echo "  ✅ TaskRuns (view only)"
    echo "  ✅ EventListeners (view only)"
    echo ""
    echo -e "${BLUE}Restricted Operations:${NC}"
    echo "  ❌ Create/Update/Delete any resources"
    echo "  ❌ Access secrets or sensitive data"
    echo "  ❌ Cluster administration functions"
    echo ""
}

main() {
    print_banner
    
    local error_count=0
    
    # Run verification checks
    if ! check_rbac_resources; then
        ((error_count++))
    fi
    
    echo ""
    if ! verify_allowed_permissions; then
        ((error_count++))
    fi
    
    echo ""
    if ! verify_restricted_permissions; then
        ((error_count++))
    fi
    
    echo ""
    if ! check_dashboard_access; then
        ((error_count++))
    fi
    
    # Show access details
    get_access_details
    
    # Final result
    if [ $error_count -eq 0 ]; then
        echo -e "${GREEN}"
        echo "=================================================================="
        echo "   ✅ VERIFICATION SUCCESSFUL"
        echo "   Restricted user is correctly configured and ready to use!"
        echo "=================================================================="
        echo -e "${NC}"
        exit 0
    else
        echo -e "${RED}"
        echo "=================================================================="
        echo "   ❌ VERIFICATION FAILED"
        echo "   Found $error_count issue(s). Please check the configuration."
        echo "=================================================================="
        echo -e "${NC}"
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi