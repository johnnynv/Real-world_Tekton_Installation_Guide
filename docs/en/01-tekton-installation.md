# Tekton Core Components Installation Guide

This guide provides detailed instructions for installing Tekton core components on a Kubernetes cluster.

## ⚠️ Important: Environment Cleanup

**If you already have Tekton components installed in your environment, please perform a complete cleanup first!**

### Check Existing Installation
```bash
# Check if Tekton namespaces exist
kubectl get namespaces | grep tekton

# Check existing Tekton components
kubectl get pods --all-namespaces | grep tekton
```

### Complete Environment Cleanup
If existing Tekton components are found, perform complete cleanup:

```bash
# Grant cleanup script execution permission
chmod +x scripts/cleanup/clean-tekton-environment.sh

# Execute complete cleanup (requires confirmation)
./scripts/cleanup/clean-tekton-environment.sh
```

⚠️ **Cleanup Confirmation**:
- Script will require `yes` input for confirmation
- Cleanup operation is irreversible, proceed with caution
- Environment will be completely clean after cleanup

## 📋 Installation Goals

- ✅ Complete cleanup of existing environment (if needed)
- ✅ Install Tekton Pipelines (core engine)
- ✅ Install Tekton Dashboard (Web UI)
- ✅ Configure Ingress access (optional)
- ✅ Verify installation integrity

## 🔧 Prerequisites

### System Requirements
- **Kubernetes Cluster**: v1.24+ (supports kubeadm/minikube/cloud providers)
- **kubectl**: configured and accessible to cluster
- **Administrator Privileges**: cluster-level RBAC permissions

### kubeadm Environment kubectl Configuration
If using a kubeadm-built cluster, you need to configure kubectl first:
```bash
# Create kubectl configuration directory
mkdir -p ~/.kube

# Copy kubeadm admin configuration (requires sudo privileges)
sudo cp /etc/kubernetes/admin.conf ~/.kube/config

# Change file ownership to current user
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### Check Cluster Status
```bash
# Check Kubernetes version
kubectl version

# Check cluster connection status
kubectl cluster-info

# Check cluster node status
kubectl get nodes

# Check available resources (if metrics-server is installed)
kubectl top nodes
```

## 🚀 Step 1: Install Tekton Pipelines

### Install Core Components
```bash
# Install latest stable Tekton Pipelines
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for all Pods to be running
kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
```

### ⚠️ Important: Kubernetes 1.24+ Pod Security Standards Configuration

**Kubernetes 1.24+ enables Pod Security Standards by default**, which will block Tekton tasks from running!

#### Problem Symptoms
```bash
# TaskRun will fail with similar error:
# pods "task-run-xxx-pod" is forbidden: violates PodSecurity "restricted:latest"
```

#### Solution
```bash
# Set privileged security policy for tekton-pipelines namespace
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/audit=privileged
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/warn=privileged

# Verify settings
kubectl get namespace tekton-pipelines -o yaml | grep pod-security
```

🔥 **This step is mandatory**, otherwise all Tekton tasks will fail due to security policy violations!

### Verify Pipelines Installation
```bash
# Check namespace
kubectl get namespace tekton-pipelines

# Check Pod status
kubectl get pods -n tekton-pipelines

# Check if CRDs are created
kubectl get crd | grep tekton
```

Expected output:
```
tekton-pipelines-controller-xxx    Running
tekton-pipelines-webhook-xxx       Running
```

## 🎨 Step 2: Install Tekton Dashboard

### Install Dashboard
```bash
# Install latest Dashboard version
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Wait for Dashboard Pod to be running
kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
```

### Verify Dashboard Installation
```bash
# Check Dashboard Pod
kubectl get pods -n tekton-pipelines | grep dashboard

# Check Dashboard Service
kubectl get svc -n tekton-pipelines | grep dashboard
```

## 🌐 Step 3: Configure Dashboard Access

### Install Nginx Ingress Controller
```bash
# Install nginx ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

# Wait for startup completion
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# Configure to use standard ports (80/443)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx -p '{"spec":{"template":{"spec":{"hostNetwork":true,"dnsPolicy":"ClusterFirstWithHostNet"}}}}'

# Wait for redeployment to complete
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s
```

### Configure Domain Access
```bash
# Get node IP
NODE_IP=$(hostname -I | awk '{print $1}')
DOMAIN="tekton.$NODE_IP.nip.io"

# Change Dashboard service to ClusterIP (required by Ingress)
kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"type":"ClusterIP"}}'

# Configure basic Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: tekton-pipelines
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
EOF
```

### Configure HTTPS Access (Optional)
```bash
# Generate self-signed certificate (with SAN to avoid modern browser warnings)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key \
  -out /tmp/tls.crt \
  -subj "/CN=$DOMAIN/O=tekton-dashboard" \
  -addext "subjectAltName=DNS:$DOMAIN"

# Create TLS Secret
kubectl create secret tls tekton-dashboard-tls \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n tekton-pipelines

# Update Ingress to enable HTTPS
kubectl patch ingress tekton-dashboard -n tekton-pipelines --type='merge' -p='
{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/ssl-redirect": "true",
      "nginx.ingress.kubernetes.io/force-ssl-redirect": "true"
    }
  },
  "spec": {
    "tls": [
      {
        "hosts": ["'$DOMAIN'"],
        "secretName": "tekton-dashboard-tls"
      }
    ]
  }
}'
```

### Configure Dashboard Basic Authentication (Production Recommended)

#### Method 1: Using Default Random Password
```bash
# Generate random password
DASHBOARD_PASSWORD=$(openssl rand -base64 12)
echo "admin:$(openssl passwd -apr1 $DASHBOARD_PASSWORD)" > /tmp/dashboard-auth

# Create authentication Secret
kubectl create secret generic tekton-dashboard-auth \
  --from-file=auth=/tmp/dashboard-auth \
  -n tekton-pipelines

# Update Ingress to enable basic authentication
kubectl patch ingress tekton-dashboard -n tekton-pipelines --type='merge' -p='
{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/auth-type": "basic",
      "nginx.ingress.kubernetes.io/auth-secret": "tekton-dashboard-auth",
      "nginx.ingress.kubernetes.io/auth-realm": "Tekton Dashboard"
    }
  }
}'

# Save authentication information
echo "Dashboard Access Information:" > dashboard-access-info.txt
echo "URL: https://tekton.$(hostname -I | awk '{print $1}').nip.io" >> dashboard-access-info.txt
echo "Username: admin" >> dashboard-access-info.txt
echo "Password: $DASHBOARD_PASSWORD" >> dashboard-access-info.txt

echo "🔐 Dashboard authentication configured"
echo "🔑 Username: admin"
echo "🔑 Password: $DASHBOARD_PASSWORD"
echo "📝 Authentication info saved to: dashboard-access-info.txt"
```

#### Method 2: Using Custom Password (e.g., admin123)
```bash
# Set custom password
DASHBOARD_PASSWORD="admin123"
echo "admin:$(openssl passwd -apr1 $DASHBOARD_PASSWORD)" > /tmp/dashboard-auth

# Create authentication Secret
kubectl create secret generic tekton-dashboard-auth \
  --from-file=auth=/tmp/dashboard-auth \
  -n tekton-pipelines

# Update Ingress to enable basic authentication
kubectl patch ingress tekton-dashboard -n tekton-pipelines --type='merge' -p='
{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/auth-type": "basic",
      "nginx.ingress.kubernetes.io/auth-secret": "tekton-dashboard-auth",
      "nginx.ingress.kubernetes.io/auth-realm": "Tekton Dashboard"
    }
  }
}'

# Save authentication information
echo "Dashboard Access Information:" > dashboard-access-info.txt
echo "URL: https://tekton.$(hostname -I | awk '{print $1}').nip.io" >> dashboard-access-info.txt
echo "Username: admin" >> dashboard-access-info.txt
echo "Password: $DASHBOARD_PASSWORD" >> dashboard-access-info.txt

echo "🔐 Dashboard authentication configured"
echo "🔑 Username: admin"
echo "🔑 Password: $DASHBOARD_PASSWORD"
echo "📝 Authentication info saved to: dashboard-access-info.txt"
```

#### Change Existing Password to admin123
If you have already configured Dashboard authentication, you can change the password using these commands:

```bash
# Set new password
NEW_PASSWORD="admin123"

# Generate new authentication file
echo "admin:$(openssl passwd -apr1 $NEW_PASSWORD)" > /tmp/dashboard-auth-new

# Delete existing authentication Secret
kubectl delete secret tekton-dashboard-auth -n tekton-pipelines --ignore-not-found

# Create new authentication Secret
kubectl create secret generic tekton-dashboard-auth \
  --from-file=auth=/tmp/dashboard-auth-new \
  -n tekton-pipelines

# Update access information file
echo "Dashboard Access Information:" > dashboard-access-info.txt
echo "URL: https://tekton.$(hostname -I | awk '{print $1}').nip.io" >> dashboard-access-info.txt
echo "Username: admin" >> dashboard-access-info.txt
echo "Password: $NEW_PASSWORD" >> dashboard-access-info.txt

echo "🔐 Dashboard password updated to: $NEW_PASSWORD"
echo "📝 Authentication info saved to: dashboard-access-info.txt"

# Clean up temporary files
rm -f /tmp/dashboard-auth-new
```

#### Using Convenience Script to Change Password
The project provides a convenient password change script:

```bash
# Use the script to quickly change password to admin123
scripts/utils/change-dashboard-password.sh admin123

# Or use interactive mode to enter password
scripts/utils/change-dashboard-password.sh
```

⚠️ **Security Notes**:
- Basic authentication provides necessary access control for production environments
- Password is randomly generated and saved to `dashboard-access-info.txt`
- Please securely store the authentication information

### Get Access Address
```bash
# Get node IP and domain
NODE_IP=$(hostname -I | awk '{print $1}')
DOMAIN="tekton.$NODE_IP.nip.io"

echo "🌐 HTTP Access:  http://$DOMAIN (auto-redirects to HTTPS)"
echo "🔒 HTTPS Access: https://$DOMAIN"
```

## ✅ Verify Installation

### 1. Run Verification Script
```bash
# Run complete verification
chmod +x scripts/utils/verify-step1-installation.sh
./scripts/utils/verify-step1-installation.sh
```

### 2. Test TaskRun
```bash
# Create and run test task
cat <<EOF | kubectl create -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: hello-world-run-
  namespace: tekton-pipelines
spec:
  taskRef:
    name: hello-world
EOF

# View execution logs
kubectl logs -l tekton.dev/task=hello-world -n tekton-pipelines --tail=10
```

### 3. Access Dashboard
```bash
# Get access address
NODE_IP=$(hostname -I | awk '{print $1}')
echo "🌐 Dashboard Access: https://tekton.$NODE_IP.nip.io"
echo "   (HTTP auto-redirects to HTTPS)"
```

Open browser and access **https://tekton.10.34.2.129.nip.io**, you should see:
- ✅ Tekton Dashboard interface
- ✅ Tasks and TaskRuns list  
- ✅ Real-time log viewing functionality
- ✅ Using standard port 443, no port number needed

## 🔧 Troubleshooting

### Common Issues

**1. Pods Cannot Start**
```bash
# Check Pod events
kubectl describe pod <pod-name> -n tekton-pipelines

# Check logs
kubectl logs <pod-name> -n tekton-pipelines
```

**2. CRD Installation Failed**
```bash
# Manually install CRDs
kubectl apply -f https://raw.githubusercontent.com/tektoncd/pipeline/main/config/500-controller.yaml
```

**3. Dashboard Inaccessible**
```bash
# Check service status
kubectl get svc -n tekton-pipelines
kubectl get endpoints -n tekton-pipelines

# Check Ingress configuration
kubectl get ingress tekton-dashboard -n tekton-pipelines

# Check SSL certificate
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=10
```

⚠️ **Common Access Issues**:
- **SSL Certificate Issues**: See [Troubleshooting Guide - SSL Certificate SAN Warning](troubleshooting.md#issue-dashboard-https-access-failure---ssl-certificate-san-warning)
- **Complete Inaccessibility**: See [Troubleshooting Guide - Ingress Controller Configuration Conflict](troubleshooting.md#issue-dashboard-completely-inaccessible---ingress-controller-configuration-conflict)

## 📚 Next Steps

After installation, you can:
1. Configure Tekton Triggers (automation triggers)
2. Set up GitHub Webhooks (CI/CD integration)  
3. Deploy GPU Pipeline (scientific computing workflows)

Continue reading: [02-tekton-triggers-setup.md](02-tekton-triggers-setup.md) 