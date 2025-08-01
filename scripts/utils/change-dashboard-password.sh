#!/bin/bash

set -euo pipefail

# Quick Dashboard Password Change Script
# Changes the Tekton Dashboard authentication password
#
# Usage:
#   # Change password to admin123:
#   ./change-dashboard-password.sh admin123
#
#   # Interactive mode (prompts for password):
#   ./change-dashboard-password.sh

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
    echo "   Tekton Dashboard Password Change Utility"
    echo "   Quick and secure password modification"
    echo "=================================================================="
    echo -e "${NC}"
}

# Configuration
NAMESPACE="tekton-pipelines"
SECRET_NAME="tekton-dashboard-auth"
USERNAME="admin"

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

# Check if secret exists
check_secret_exists() {
    if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_error "Dashboard authentication secret '$SECRET_NAME' not found in namespace '$NAMESPACE'"
        log_info "Please run the dashboard configuration script first:"
        log_info "  scripts/install/02-configure-tekton-dashboard.sh"
        exit 1
    fi
}

# Get password from argument or prompt
get_new_password() {
    if [ $# -eq 1 ]; then
        NEW_PASSWORD="$1"
        log_info "Using provided password"
    else
        echo -n "Enter new password for dashboard user '$USERNAME': "
        read -s NEW_PASSWORD
        echo
        
        if [ -z "$NEW_PASSWORD" ]; then
            log_error "Password cannot be empty"
            exit 1
        fi
        
        echo -n "Confirm new password: "
        read -s CONFIRM_PASSWORD
        echo
        
        if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
            log_error "Passwords do not match"
            exit 1
        fi
    fi
}

# Generate authentication file
generate_auth_file() {
    log_info "Generating authentication hash for user: $USERNAME"
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Generate password hash using openssl (compatible with NGINX)
    if command -v htpasswd &> /dev/null; then
        htpasswd -nb "$USERNAME" "$NEW_PASSWORD" > "$temp_file"
    else
        # Use openssl to generate APR1 MD5 hash (compatible with NGINX)
        local hash
        hash=$(openssl passwd -apr1 "$NEW_PASSWORD")
        echo "$USERNAME:$hash" > "$temp_file"
    fi
    
    echo "$temp_file"
}

# Update Kubernetes secret
update_secret() {
    local auth_file="$1"
    
    log_info "Updating Kubernetes secret: $SECRET_NAME"
    
    # Delete existing secret
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
    
    # Create new secret
    kubectl create secret generic "$SECRET_NAME" \
        --from-file=auth="$auth_file" \
        -n "$NAMESPACE"
    
    # Add labels
    kubectl label secret "$SECRET_NAME" \
        app.kubernetes.io/name=tekton-dashboard \
        app.kubernetes.io/component=dashboard-auth \
        -n "$NAMESPACE" --overwrite
}

# Update access info file
update_access_info() {
    log_info "Updating access information file"
    
    # Get dashboard URL
    local node_ip
    node_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    local dashboard_url="https://tekton.${node_ip}.nip.io"
    
    # Create/update access info file
    cat > dashboard-access-info.txt << EOF
Dashboard Access Information:
URL: $dashboard_url
Username: $USERNAME
Password: $NEW_PASSWORD
EOF
    
    log_success "Access information saved to: dashboard-access-info.txt"
}

# Verify the update
verify_update() {
    log_info "Verifying the password update..."
    
    # Check if secret exists and has the auth field
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.auth}' &> /dev/null; then
        log_success "Secret updated successfully"
        
        # Get the auth data and decode it (for verification, don't show the hash)
        local auth_entry
        auth_entry=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.auth}' | base64 -d | cut -d: -f1)
        
        if [ "$auth_entry" = "$USERNAME" ]; then
            log_success "Username verification passed"
        else
            log_warning "Username in secret doesn't match expected value"
        fi
    else
        log_error "Failed to verify secret update"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    if [ -n "${TEMP_AUTH_FILE:-}" ] && [ -f "$TEMP_AUTH_FILE" ]; then
        rm -f "$TEMP_AUTH_FILE"
    fi
}

# Main function
main() {
    print_banner
    
    # Setup cleanup trap
    trap cleanup EXIT
    
    # Validate environment
    check_kubectl
    check_secret_exists
    
    # Get new password
    get_new_password "$@"
    
    # Generate authentication file
    log_info "Generating authentication hash for user: $USERNAME"
    
    # Create temporary file
    TEMP_AUTH_FILE=$(mktemp)
    
    # Generate password hash using openssl (compatible with NGINX)
    if command -v htpasswd &> /dev/null; then
        htpasswd -nb "$USERNAME" "$NEW_PASSWORD" > "$TEMP_AUTH_FILE"
    else
        # Use openssl to generate APR1 MD5 hash (compatible with NGINX)
        hash=$(openssl passwd -apr1 "$NEW_PASSWORD")
        echo "$USERNAME:$hash" > "$TEMP_AUTH_FILE"
    fi
    
    # Update the secret
    update_secret "$TEMP_AUTH_FILE"
    
    # Update access info
    update_access_info
    
    # Verify the update
    verify_update
    
    # Success message
    log_success "Dashboard password has been successfully updated!"
    log_info "New credentials:"
    log_info "  Username: $USERNAME"
    log_info "  Password: $NEW_PASSWORD"
    log_warning "Please update your bookmarks and inform authorized users"
    
    # Security reminder
    echo
    log_warning "Security reminders:"
    log_warning "- The password is stored in 'dashboard-access-info.txt'"
    log_warning "- Please secure this file and consider deleting it after noting the credentials"
    log_warning "- The change takes effect immediately"
}

# Run main function
main "$@"