#!/bin/bash

set -euo pipefail

# Production Tekton Dashboard Configuration Script
# Configures secure HTTPS access with authentication

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
    echo "   Tekton Dashboard Production Configuration"
    echo "   Secure HTTPS access with authentication"
    echo "=================================================================="
    echo -e "${NC}"
}

# Configuration variables
# Auto-detect external IP and use nip.io domain
EXTERNAL_IP="${EXTERNAL_IP:-$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo '10.117.8.154')}"
DASHBOARD_HOST="${DASHBOARD_HOST:-tekton.${EXTERNAL_IP}.nip.io}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"
NAMESPACE="tekton-pipelines"

# Generate secure password if not provided
generate_admin_password() {
    if [ -z "$ADMIN_PASSWORD" ]; then
        ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
        log_info "Generated admin password: $ADMIN_PASSWORD"
        echo "$ADMIN_PASSWORD" > dashboard-admin-password.txt
        log_warning "Admin password saved to: dashboard-admin-password.txt"
        log_warning "Please save this password securely and delete the file!"
    fi
}

# Generate TLS certificate
generate_tls_certificate() {
    log_info "Generating TLS certificate for domain: $DASHBOARD_HOST"
    
    # Create temporary directory for certificate generation
    CERT_DIR=$(mktemp -d)
    
    # Generate private key
    openssl genrsa -out "$CERT_DIR/tls.key" 2048
    
    # Create certificate signing request configuration
    cat > "$CERT_DIR/csr.conf" << EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=Production
L=Production
O=Tekton
OU=GPU Pipeline
CN=$DASHBOARD_HOST

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DASHBOARD_HOST
DNS.2 = *.${DASHBOARD_HOST#*.}
EOF
    
    # Generate certificate signing request
    openssl req -new -key "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.csr" -config "$CERT_DIR/csr.conf"
    
    # Generate self-signed certificate (replace with CA-signed in production)
    openssl x509 -req -in "$CERT_DIR/tls.csr" -signkey "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" -days 365 -extensions v3_req -extfile "$CERT_DIR/csr.conf"
    
    # Base64 encode for Kubernetes secret
    TLS_CRT=$(base64 -w 0 < "$CERT_DIR/tls.crt")
    TLS_KEY=$(base64 -w 0 < "$CERT_DIR/tls.key")
    
    # Cleanup
    rm -rf "$CERT_DIR"
    
    log_success "TLS certificate generated for $DASHBOARD_HOST"
}

# Generate basic auth credentials
generate_basic_auth() {
    log_info "Generating basic authentication credentials"
    
    # Generate password hash using openssl (compatible with NGINX)
    if command -v htpasswd &> /dev/null; then
        AUTH_ENTRY=$(htpasswd -nb "$ADMIN_USER" "$ADMIN_PASSWORD")
    else
        # Use openssl to generate APR1 MD5 hash (compatible with NGINX)
        HASH=$(openssl passwd -apr1 "$ADMIN_PASSWORD")
        AUTH_ENTRY="$ADMIN_USER:$HASH"
    fi
    
    AUTH_B64=$(echo -n "$AUTH_ENTRY" | base64 -w 0)
    
    log_success "Basic authentication configured for user: $ADMIN_USER"
}

# Create production configuration
create_production_config() {
    log_info "Creating production Ingress configuration"
    
    # Backup original configuration if exists
    if [ -f "examples/dashboard/tekton-dashboard-ingress.yaml" ]; then
        cp examples/dashboard/tekton-dashboard-ingress.yaml examples/dashboard/tekton-dashboard-ingress.yaml.backup
    fi
    
    # Create production configuration with real values
    cat > examples/dashboard/tekton-dashboard-ingress-production.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: tekton-dashboard-auth
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: tekton-dashboard
    app.kubernetes.io/component: dashboard-auth
type: Opaque
data:
  auth: $AUTH_B64
---
apiVersion: v1
kind: Secret
metadata:
  name: tekton-dashboard-tls
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: tekton-dashboard
    app.kubernetes.io/component: dashboard-tls
type: kubernetes.io/tls
data:
  tls.crt: $TLS_CRT
  tls.key: $TLS_KEY
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: tekton-dashboard
    app.kubernetes.io/component: dashboard-ingress
  annotations:
    # Production security settings
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: tekton-dashboard-auth
    nginx.ingress.kubernetes.io/auth-realm: "Tekton Dashboard - Production Access"
    
    # Production security settings (without snippets)
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "1m"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "8k"
    
    # Rate limiting for production
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    nginx.ingress.kubernetes.io/rate-limit-status-code: "429"
    
    # Connection and timeout settings
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-next-upstream: "error timeout http_502 http_503 http_504"
spec:
  ingressClassName: $INGRESS_CLASS
  tls:
  - hosts:
    - $DASHBOARD_HOST
    secretName: tekton-dashboard-tls
  rules:
  - host: $DASHBOARD_HOST
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
 ---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-dashboard-netpol
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: tekton-dashboard
    app.kubernetes.io/component: dashboard-security
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: dashboard
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow NGINX Ingress Controller to access Dashboard
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 9097
  egress:
  # Allow access to Kubernetes API server
  - to: []
    ports:
    - protocol: TCP
      port: 443   # HTTPS API server access
    - protocol: TCP  
      port: 6443  # Secure API server port
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow access to other Tekton components in the same namespace
  - to:
    - namespaceSelector:
        matchLabels:
          name: tekton-pipelines
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 9090
    - protocol: TCP
      port: 8008
EOF

    log_success "Production configuration created: examples/dashboard/tekton-dashboard-ingress-production.yaml"
}

# Deploy production configuration
deploy_production_config() {
    log_info "Deploying production Dashboard configuration"
    
    # Apply the configuration
    kubectl apply -f examples/dashboard/tekton-dashboard-ingress-production.yaml
    
    # Wait for Ingress to be ready
    log_info "Waiting for Ingress to be ready..."
    kubectl wait --for=condition=Ready ingress/tekton-dashboard -n "$NAMESPACE" --timeout=60s || {
        log_warning "Ingress readiness check timed out, but resources may still be initializing"
    }
    
    log_success "Production configuration deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying production deployment"
    
    # Check Ingress status
    kubectl get ingress tekton-dashboard -n "$NAMESPACE" -o wide
    
    # Check secrets
    kubectl get secret tekton-dashboard-auth tekton-dashboard-tls -n "$NAMESPACE"
    
    # Check network policy
    kubectl get networkpolicy tekton-dashboard-netpol -n "$NAMESPACE"
    
    log_success "Deployment verification completed"
}

# Print access information
print_access_info() {
    echo -e "\n${GREEN}✅ Dashboard Production Configuration Complete!${NC}\n"
    
    echo -e "${BLUE}📋 Access Information:${NC}"
    echo -e "  🌐 Dashboard URL: https://$DASHBOARD_HOST"
    echo -e "  👤 Username: $ADMIN_USER"
    echo -e "  🔑 Password: $ADMIN_PASSWORD"
    echo ""
    
    echo -e "${YELLOW}⚠️  Important Production Notes:${NC}"
    echo -e "  1. Add '$DASHBOARD_HOST' to your DNS or /etc/hosts file"
    echo -e "  2. Replace self-signed certificate with CA-signed certificate"
    echo -e "  3. Change default password immediately"
    echo -e "  4. Configure RBAC for fine-grained access control"
    echo -e "  5. Set up monitoring and alerting"
    echo -e "  6. Regularly rotate certificates and passwords"
    echo ""
    
    echo -e "${BLUE}🔧 DNS Configuration:${NC}"
    echo -e "  Add this to your DNS or /etc/hosts:"
    
    # Get Ingress external IP if available
    EXTERNAL_IP=$(kubectl get ingress tekton-dashboard -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        EXTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    echo -e "  $EXTERNAL_IP    $DASHBOARD_HOST"
    echo ""
    
    echo -e "${GREEN}🎉 Production deployment completed successfully!${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for production deployment"
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed"
        exit 1
    fi
    
    # Check if htpasswd is available (optional, openssl fallback exists)
    if ! command -v htpasswd &> /dev/null; then
        log_warning "htpasswd not found, will use openssl fallback"
    fi
    
    # Check if kubectl is available and connected
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl is not properly configured or cluster is not accessible"
        exit 1
    fi
    
    # Check if Tekton Dashboard is installed
    if ! kubectl get deployment tekton-dashboard -n "$NAMESPACE" &> /dev/null; then
        log_error "Tekton Dashboard is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Ingress controller is available
    if ! kubectl get ingressclass "$INGRESS_CLASS" &> /dev/null; then
        log_warning "Ingress class '$INGRESS_CLASS' not found. Make sure NGINX Ingress Controller is installed."
    fi
    
    log_success "Prerequisites check completed"
}

# Main execution
main() {
    print_banner
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --host)
                DASHBOARD_HOST="$2"
                shift 2
                ;;
            --admin-user)
                ADMIN_USER="$2"
                shift 2
                ;;
            --admin-password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --ingress-class)
                INGRESS_CLASS="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --host             Dashboard hostname (default: tekton.<EXTERNAL_IP>.nip.io)"
                echo "  --admin-user       Admin username (default: admin)"
                echo "  --admin-password   Admin password (default: auto-generated)"
                echo "  --ingress-class    Ingress class name (default: nginx)"
                echo "  --help             Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    generate_admin_password
    generate_tls_certificate
    generate_basic_auth
    create_production_config
    deploy_production_config
    verify_deployment
    print_access_info
}

main "$@" 