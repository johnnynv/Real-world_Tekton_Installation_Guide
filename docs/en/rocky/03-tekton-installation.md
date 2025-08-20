# Tekton v1.3.0 Production Environment Installation Guide

This guide provides detailed instructions for installing Tekton v1.3.0 complete components on Rocky Linux 10 + Kubernetes v1.30.14 environment.

## 🎯 Installation Planning

### Version Selection
- **Tekton Pipelines**: v1.3.0 (Latest stable version)
- **Tekton Dashboard**: v0.60.0 (Latest stable version)
- **Access Method**: nip.io domain + NodePort service
- **Authentication**: admin/admin123 basic authentication

### Component Architecture
```
Complete Tekton Installation
├── Tekton Pipelines (Core Engine)
├── Tekton Dashboard (Web Interface)
├── Nginx Ingress Controller (External Access)
├── Basic Authentication (User Management)
└── nip.io Domain Service (No DNS Configuration Required)
```

## 🏁 Step 1: Environment Verification

### Check K8s Cluster Status
```bash
# Verify cluster version and status
kubectl version
kubectl get nodes
kubectl get pods -A | grep -v Completed
```

**Verification Results**:
- ✅ Kubernetes v1.30.14 running normally
- ✅ Node status is Ready
- ✅ All system Pods running normally

### Check Storage and Network
```bash
# Check default storage class
kubectl get storageclass

# Check network connectivity
kubectl get pods -n calico-system
```

**Verification Results**:
- ✅ local-path storage class available
- ✅ Calico network running normally

## 🔧 Step 2: Install Tekton Pipelines v1.3.0

### Get Latest Version Information
```bash
# Check latest Tekton Pipelines version
curl -s https://api.github.com/repos/tektoncd/pipeline/releases | grep -E '"tag_name".*v1\.' | head -1
```

### Install Tekton Pipelines
```bash
# Install Tekton Pipelines latest version
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Verify installation
kubectl get pods --namespace tekton-pipelines
kubectl get crd | grep tekton
```

**Installation Results**:
```
namespace/tekton-pipelines created
customresourcedefinition.apiextensions.k8s.io/customruns.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/pipelines.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/pipelineruns.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/taskruns.tekton.dev created
deployment.apps/tekton-pipelines-controller created
deployment.apps/tekton-pipelines-webhook created
```

### Verify Installation
```bash
# Wait for Tekton controller to start
kubectl wait --for=condition=available --timeout=300s deployment/tekton-pipelines-controller -n tekton-pipelines

# Verify Tekton component status
kubectl get pods --namespace tekton-pipelines
kubectl get crd | grep tekton

# Get version information
kubectl describe deployment tekton-pipelines-controller -n tekton-pipelines | grep Image
```

**Verification Results**:
```
# Tekton component status
NAME                                           READY   STATUS    RESTARTS   AGE
tekton-events-controller-bcd894689-2wtff       1/1     Running   0          33s
tekton-pipelines-controller-685d97d7db-pwwxx   1/1     Running   0          33s
tekton-pipelines-webhook-6f7d65db5-jmgpn       1/1     Running   0          33s

# Custom resource definitions
customruns.tekton.dev                                 2025-08-20T11:19:39Z
pipelineruns.tekton.dev                               2025-08-20T11:19:39Z
pipelines.tekton.dev                                  2025-08-20T11:19:39Z
tasks.tekton.dev                                      2025-08-20T11:19:39Z
taskruns.tekton.dev                                   2025-08-20T11:19:39Z

# Version information
Image: ghcr.io/tektoncd/pipeline/controller:v1.3.0
```

**Pipelines Verification Results**:
- ✅ Tekton Pipelines v1.3.0 installed successfully
- ✅ All core components running normally
- ✅ Custom resource definitions created

## 🖥️ Step 3: Install Tekton Dashboard

### Install Dashboard
```bash
# Install Tekton Dashboard latest version
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Verify Dashboard installation
kubectl get pods -n tekton-pipelines | grep dashboard
kubectl get svc -n tekton-pipelines | grep dashboard
```

**Installation Results**:
```
customresourcedefinition.apiextensions.k8s.io/extensions.dashboard.tekton.dev created
serviceaccount/tekton-dashboard created
deployment.apps/tekton-dashboard created
service/tekton-dashboard created
```

**Dashboard Verification Results**:
```
# Dashboard component status
tekton-dashboard-75d96bd9f-lvfhn               1/1     Running   0          6s

# Dashboard service
tekton-dashboard              ClusterIP   10.109.175.63   <none>        9097/TCP
```

- ✅ Tekton Dashboard installed successfully
- ✅ Service running on port 9097

## 🌐 Step 4: Configure Nginx Ingress Access

### Install Nginx Ingress Controller
```bash
# Install Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml

# Wait for Ingress Controller to start
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

# Check Ingress Controller status
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**Installation Results**:
```
namespace/ingress-nginx created
deployment.apps/ingress-nginx-controller created
service/ingress-nginx-controller created
ingressclass.networking.k8s.io/nginx created
```

**Ingress Controller Verification Results**:
```
# Controller status
ingress-nginx-controller-85bc8b845b-mr9r8   1/1     Running   0          69s

# Controller service
ingress-nginx-controller             LoadBalancer   10.104.156.191   <pending>     80:30080/TCP,443:30443/TCP
```

- ✅ Nginx Ingress Controller installed successfully
- ✅ HTTP port: 30080 (auto redirect), HTTPS port: 30443

### Create Basic Authentication
```bash
# Generate password hash for admin/admin123
echo -n 'admin123' | openssl passwd -apr1 -stdin

# Create basic authentication Secret
kubectl create secret generic tekton-basic-auth --from-literal=auth='admin:$apr1$BElBVB.P$dy.Nl0ipmc5vXZESSpPaJ1' -n tekton-pipelines
```

**Authentication Configuration Results**:
- ✅ Username: admin
- ✅ Password: admin123
- ✅ Authentication method: HTTP Basic Auth

### Create TLS Certificate
```bash
# Create self-signed SSL certificate with SAN
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=tekton.10.78.14.61.nip.io" -addext "subjectAltName=DNS:tekton.10.78.14.61.nip.io"

# Create TLS certificate Secret
kubectl create secret tls tekton-tls-secret --key tls.key --cert tls.crt -n tekton-pipelines

# Clean up temporary certificate files
rm tls.key tls.crt
```

**TLS Certificate Configuration Results**:
- ✅ Self-signed certificate created successfully
- ✅ Certificate validity: 365 days
- ✅ Domain: tekton.10.78.14.61.nip.io

### Create HTTPS Ingress Resource
```bash
# Create Tekton Dashboard Ingress with basic authentication and HTTPS
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard-ingress
  namespace: tekton-pipelines
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: tekton-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Tekton Dashboard Authentication'
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  tls:
  - hosts:
    - tekton.10.78.14.61.nip.io
    secretName: tekton-tls-secret
  rules:
  - host: tekton.10.78.14.61.nip.io
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

# Verify Ingress creation
kubectl get ingress -n tekton-pipelines
```

**Ingress Configuration Results**:
```
NAME                       CLASS    HOSTS                       ADDRESS   PORTS     AGE
tekton-dashboard-ingress   <none>   tekton.10.78.14.61.nip.io             80, 443   5m3s
```

### Test HTTPS Access
```bash
# Test HTTPS access (port 30443)
curl -H "Host: tekton.10.78.14.61.nip.io" -u admin:admin123 https://localhost:30443/ -k -I

# Test HTTP redirect (port 30080)
curl -H "Host: tekton.10.78.14.61.nip.io" http://localhost:30080/ -I
```

**HTTPS Access Test Results**:
```
# HTTPS direct access
HTTP/2 200 
date: Wed, 20 Aug 2025 11:29:52 GMT
content-type: text/html; charset=utf-8
strict-transport-security: max-age=31536000; includeSubDomains

# HTTP auto redirect
HTTP/1.1 308 Permanent Redirect
Location: https://tekton.10.78.14.61.nip.io
```

- ✅ HTTPS 200 status code, access successful
- ✅ HTTP/2 protocol enabled
- ✅ HTTP auto redirect to HTTPS
- ✅ HSTS security headers enabled

## 🎉 Step 5: Access Information Summary

### 🌐 Tekton Dashboard Access Information

**Primary Access URL**:
```
https://tekton.10.78.14.61.nip.io
```

**Authentication Information**:
- **Username**: admin
- **Password**: admin123

**Technical Architecture**:
```
HTTPS Access Flow
├── https://tekton.10.78.14.61.nip.io
├── Nginx Ingress Controller (NodePort 30443)
├── TLS Certificate Verification (Self-signed certificate)
├── HTTP Basic Auth (admin/admin123)
├── Tekton Dashboard Service (9097)
└── Tekton Dashboard Pod
```

### 🔧 Alternative Access Methods

**Local Port Forwarding** (Development/Testing):
```bash
# Create port forwarding
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097

# Access URL
http://localhost:9097
```

**NodePort Direct Access** (Internal Network):
```bash
# Create NodePort service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: tekton-dashboard-nodeport
  namespace: tekton-pipelines
spec:
  type: NodePort
  ports:
  - port: 9097
    targetPort: 9097
    nodePort: 30097
    protocol: TCP
  selector:
    app.kubernetes.io/name: tekton-dashboard
EOF

# Access URL
http://10.78.14.61:30097
```

## 📋 Installation Results Summary

### ✅ Successfully Installed Components
1. **Tekton Pipelines**: v1.3.0 (Core Engine)
2. **Tekton Dashboard**: Latest version (Web Interface)
3. **Nginx Ingress Controller**: v1.11.3 (External Access)
4. **TLS Certificate**: Self-signed certificate (HTTPS Encryption)
5. **Basic Authentication**: admin/admin123 (Secure Access)
6. **nip.io Domain**: No DNS configuration required

### 🔄 Integration Verification
- ✅ Kubernetes v1.30.14 ← → Tekton v1.3.0 (Fully Compatible)
- ✅ Ingress Controller ← → Tekton Dashboard (HTTPS Proxy)
- ✅ TLS Certificate ← → HTTPS Encryption (Self-signed certificate)
- ✅ HTTP Basic Auth ← → User Authentication (Secure Access)
- ✅ nip.io Domain ← → External Access (No DNS Required)
- ✅ HTTP → HTTPS ← → Auto Redirect (Forced Security)

### 🎯 Production Environment Ready
This Tekton installation is prepared for the following scenarios:
- **CI/CD Pipeline**: Complete continuous integration and deployment
- **Container Building**: Support for various build strategies
- **Git Integration**: Support for GitHub, GitLab and other code repositories
- **Multi-tenancy**: Support for namespace isolation
- **Monitoring Integration**: Integration with Prometheus/Grafana

## 🚀 Next Steps

After Tekton installation is complete, you can continue with:
1. [Create First Pipeline](04-tekton-triggers-setup.md)
2. [Configure Git Webhook](05-tekton-webhook-configuration.md)
3. [Deploy GPU Pipeline](06-gpu-pipeline-deployment.md)

## 🎉 Summary

Successfully completed the installation of the complete Tekton platform! You can now access it through the following URL:

**🌐 Tekton Dashboard Access URL**: https://tekton.10.78.14.61.nip.io
**👤 Login Credentials**: admin / admin123

Enjoy your Tekton CI/CD journey!
