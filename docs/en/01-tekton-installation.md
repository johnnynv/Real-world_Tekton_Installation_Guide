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
kubectl version --short

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

## 🌐 Step 3: Configure Access Methods

### Method 1: Port Forwarding (Development Environment)
```bash
# Start port forwarding
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097

# Access in browser
# http://localhost:9097
```

### Method 2: NodePort Service (Recommended)
```bash
# Create NodePort service
kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'

# Get access port
kubectl get svc tekton-dashboard -n tekton-pipelines
```

Access Dashboard:
```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Get port
NODE_PORT=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')

echo "Dashboard access URL: http://${NODE_IP}:${NODE_PORT}"
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