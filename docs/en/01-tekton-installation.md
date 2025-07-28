# Tekton Core Components Installation Guide

This guide provides detailed instructions for installing Tekton core components on a Kubernetes cluster.

## 📋 Installation Goals

- ✅ Install Tekton Pipelines (core engine)
- ✅ Install Tekton Dashboard (Web UI)
- ✅ Configure Ingress access (optional)
- ✅ Verify installation integrity

## 🔧 Prerequisites

### System Requirements
- **Kubernetes Cluster**: v1.24+ 
- **kubectl**: configured and accessible to cluster
- **Administrator Privileges**: cluster-level RBAC permissions

### Check Cluster Status
```bash
# Check Kubernetes version
kubectl version

# Check cluster node status
kubectl get nodes

# Check available resources
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

## 🌐 Step 3: Configure Production-Grade Access (HTTPS + Authentication)

### Production Security Configuration
```bash
# Install required tools
sudo apt-get update && sudo apt-get install -y apache2-utils openssl

# Grant execution permission to configuration script
chmod +x scripts/install/02-configure-tekton-dashboard.sh

# Execute production-grade configuration (auto-generate certificate and password)
./scripts/install/02-configure-tekton-dashboard.sh
```

### Custom Configuration Parameters
```bash
# Use custom domain and password
./scripts/install/02-configure-tekton-dashboard.sh \
  --host tekton.YOUR_IP.nip.io \
  --admin-user admin \
  --admin-password your-secure-password \
  --ingress-class nginx
```

### Configure Domain Access
Use nip.io free domain service, no need to configure DNS or hosts file:
```bash
# Use actual external IP address to configure domain
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Dashboard URL: https://tekton.${EXTERNAL_IP}.nip.io"
```

### Direct Access
```bash
# Example: Use currently configured domain
# https://tekton.10.117.8.154.nip.io
# Username: admin
# Password: (script-generated password)
```

## ✅ Verify Complete Installation

### 1. Check All Component Status
```bash
# Run verification script
./scripts/en/utils/verify-installation.sh
```

### 2. Create Test Task
```bash
# Create test task
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: tekton-pipelines
spec:
  steps:
  - name: hello
    image: ubuntu
    script: |
      #!/bin/bash
      echo "Hello from Tekton!"
      echo "Installation successful!"
EOF
```

### 3. Run Test TaskRun
```bash
# Create TaskRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: hello-world-run-
  namespace: tekton-pipelines
spec:
  taskRef:
    name: hello-world
EOF

# Check run status
kubectl get taskruns -n tekton-pipelines

# View logs
kubectl logs -l tekton.dev/task=hello-world -n tekton-pipelines
```

### 4. Dashboard Verification
In the Dashboard you should see:
- ✅ Tasks list
- ✅ TaskRuns execution history
- ✅ Real-time log viewing

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
```

## 📚 Next Steps

After installation, you can:
1. Configure Tekton Triggers (automation triggers)
2. Set up GitHub Webhooks (CI/CD integration)  
3. Deploy GPU Pipeline (scientific computing workflows)

Continue reading: [02-tekton-triggers-setup.md](02-tekton-triggers-setup.md) 