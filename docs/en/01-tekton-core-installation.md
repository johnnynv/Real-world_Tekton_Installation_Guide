# Stage 1: Tekton Core Infrastructure Installation Guide

This guide provides detailed instructions for installing Tekton core infrastructure on a Kubernetes cluster, including Pipelines, Dashboard, and Ingress configuration for production-grade Web UI access.

## 📋 Stage 1 Objectives

- ✅ Install Nginx Ingress Controller (production-grade configuration)
- ✅ Deploy Tekton Pipelines (latest stable version)
- ✅ Deploy Tekton Dashboard (Web UI)
- ✅ Configure Ingress and IngressClass (external access)
- ✅ Verify complete installation and access

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                External Access                   │
│         http://tekton.YOUR_NODE_IP.nip.io/      │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│           Nginx Ingress Controller               │
│          (Host Network + External IP)           │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│              Tekton Dashboard                   │
│           (Service: port 9097)                 │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│            Tekton Pipelines                     │
│        (Core Pipeline Engine)                  │
└─────────────────────────────────────────────────┘
```

## 🔧 Prerequisites

### System Requirements

- ✅ **Kubernetes Cluster**: v1.20+ (recommended v1.24+)
- ✅ **kubectl**: configured and accessible to cluster
- ✅ **Helm**: v3.0+ (for Ingress Controller)
- ✅ **Administrator Privileges**: cluster-level RBAC permissions
- ✅ **Network Access**: external IP reachable

### Resource Requirements

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| **Tekton Pipelines** | 200m | 256Mi | - |
| **Tekton Dashboard** | 100m | 128Mi | - |
| **Nginx Ingress** | 100m | 128Mi | - |
| **Total Recommended** | 500m | 512Mi | - |

### Environment Configuration

```bash
# Set environment variables
export TEKTON_NAMESPACE="tekton-pipelines"
export NODE_IP="YOUR_NODE_IP"
export TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"

# Verify environment
echo "Cluster info:"
kubectl cluster-info
echo "Node info:"
kubectl get nodes -o wide
```

## 🚀 Installation Steps

### Step 1: Environment Verification and Cleanup

```bash
# Check existing installation
kubectl get namespace ${TEKTON_NAMESPACE} || echo "Namespace doesn't exist, safe to continue"

# Clean if needed (optional)
echo "If cleanup is needed, run: ./scripts/en/cleanup/01-cleanup-tekton-core.sh"
```

### Step 2: Install and Configure Nginx Ingress Controller

#### 2.1 Add Helm Repository

```bash
# Add and update Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Verify repository
helm search repo ingress-nginx/ingress-nginx
```

#### 2.2 Production-Grade Ingress Installation

```bash
# Install Nginx Ingress Controller (production configuration)
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet \
  --set controller.service.type=ClusterIP \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.service.externalIPs="{${NODE_IP}}" \
  --set controller.resources.limits.cpu=200m \
  --set controller.resources.limits.memory=256Mi \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi \
  --wait --timeout=300s

# Verify installation
kubectl get pods -n ingress-nginx
kubectl get daemonset -n ingress-nginx
```

#### 2.3 Create IngressClass

```bash
# Create standard IngressClass
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  controller: k8s.io/ingress-nginx
EOF

# Verify IngressClass
kubectl get ingressclass
```

#### 2.4 Test Ingress Controller

```bash
# Test Ingress Controller response
curl -I http://${NODE_IP}
# Expected: HTTP 404 (means controller is responding)
```

### Step 3: Install Tekton Pipelines

#### 3.1 Install Core Pipelines

```bash
# Install Tekton Pipelines (latest release)
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for deployment completion
kubectl wait --for=condition=ready pod \
  --selector=app.kubernetes.io/part-of=tekton-pipelines \
  --namespace=${TEKTON_NAMESPACE} \
  --timeout=300s

# Verify installation
kubectl get pods -n ${TEKTON_NAMESPACE}
kubectl get customresourcedefinitions | grep tekton
```

#### 3.2 Configure Pod Security Standards

```bash
# Apply Pod Security Standards for production
kubectl label namespace ${TEKTON_NAMESPACE} \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### Step 4: Install Tekton Dashboard

#### 4.1 Deploy Dashboard

```bash
# Install Tekton Dashboard
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Wait for deployment
kubectl wait --for=condition=ready pod \
  --selector=app.kubernetes.io/name=tekton-dashboard \
  --namespace=${TEKTON_NAMESPACE} \
  --timeout=300s

# Verify Dashboard service
kubectl get service tekton-dashboard -n ${TEKTON_NAMESPACE}
```

#### 4.2 Configure Resource Limits

```bash
# Apply production resource limits
kubectl patch deployment tekton-dashboard -n ${TEKTON_NAMESPACE} --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "tekton-dashboard",
          "resources": {
            "limits": {
              "cpu": "200m",
              "memory": "256Mi"
            },
            "requests": {
              "cpu": "100m",
              "memory": "128Mi"
            }
          }
        }]
      }
    }
  }
}'
```

### Step 5: Configure External Access

#### 5.1 Create Dashboard Ingress

```bash
# Create Ingress for Dashboard access
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: ${TEKTON_NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: ${TEKTON_DOMAIN}
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

# Verify Ingress
kubectl get ingress -n ${TEKTON_NAMESPACE}
```

#### 5.2 Test External Access

```bash
# Test Dashboard access
curl -I http://${TEKTON_DOMAIN}/
# Expected: HTTP 200

# Test API endpoint
curl -I http://${TEKTON_DOMAIN}/api/v1/namespaces
# Expected: HTTP 200
```

### Step 6: Apply Production Configurations

#### 6.1 Network Policies

```bash
# Create network policy for Dashboard access
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-dashboard-access
  namespace: ${TEKTON_NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: tekton-dashboard
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 9097
  - from: []
    ports:
    - protocol: TCP
      port: 9097
EOF
```

### Step 7: Create Test Resources

#### 7.1 Create Sample Task

```bash
# Create test Task
kubectl apply -f - <<EOF
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: ${TEKTON_NAMESPACE}
spec:
  steps:
  - name: hello
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "🎉 Welcome to Tekton!"
      echo "✅ Core infrastructure is working!"
      echo "🌐 Dashboard URL: http://${TEKTON_DOMAIN}/"
      echo "📊 Cluster: \$(hostname)"
      echo "⏰ Time: \$(date)"
EOF
```

#### 7.2 Create Sample Pipeline

```bash
# Create test Pipeline
kubectl apply -f - <<EOF
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: hello-pipeline
  namespace: ${TEKTON_NAMESPACE}
spec:
  tasks:
  - name: say-hello
    taskRef:
      name: hello-world
EOF
```

#### 7.3 Run Test Pipeline

```bash
# Create and run test PipelineRun
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: hello-run-
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: hello-pipeline
EOF

# Wait for completion and check result
kubectl wait --for=condition=succeeded pipelinerun \
  --selector=tekton.dev/pipeline=hello-pipeline \
  --namespace=${TEKTON_NAMESPACE} \
  --timeout=300s

# View logs
kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --sort-by=.metadata.creationTimestamp
```

## ✅ Verification Checklist

### Core Components Status

```bash
# Check all pods are running
kubectl get pods -n ${TEKTON_NAMESPACE}
kubectl get pods -n ingress-nginx

# Verify services
kubectl get services -n ${TEKTON_NAMESPACE}

# Check Ingress configuration
kubectl get ingress -n ${TEKTON_NAMESPACE}
```

### Access Verification

```bash
# Dashboard UI access
echo "Dashboard: http://${TEKTON_DOMAIN}/"
curl -I http://${TEKTON_DOMAIN}/

# API endpoint access
echo "API: http://${TEKTON_DOMAIN}/api/v1/namespaces"
curl -I http://${TEKTON_DOMAIN}/api/v1/namespaces
```

### Functional Testing

```bash
# List available resources
kubectl get tasks,pipelines,pipelineruns -n ${TEKTON_NAMESPACE}

# Test Pipeline execution
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: verify-run-
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: hello-pipeline
EOF
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Ingress Controller Not Responding

```bash
# Check Ingress Controller pods
kubectl get pods -n ingress-nginx

# Check DaemonSet status
kubectl describe daemonset ingress-nginx-controller -n ingress-nginx

# Check node network configuration
kubectl get nodes -o wide
```

#### 2. Dashboard Not Accessible

```bash
# Check Dashboard pod logs
kubectl logs -l app.kubernetes.io/name=tekton-dashboard -n ${TEKTON_NAMESPACE}

# Check service endpoints
kubectl get endpoints tekton-dashboard -n ${TEKTON_NAMESPACE}

# Test internal service access
kubectl run test-pod --rm -i --tty --image=alpine:latest -- sh
# Inside pod: wget -qO- http://tekton-dashboard.tekton-pipelines.svc.cluster.local:9097
```

#### 3. Pipeline Execution Issues

```bash
# Check Tekton Pipelines controller logs
kubectl logs -l app.kubernetes.io/name=tekton-pipelines-controller -n ${TEKTON_NAMESPACE}

# Check CustomResourceDefinitions
kubectl get crd | grep tekton

# Verify RBAC permissions
kubectl auth can-i create pipelinerun --namespace=${TEKTON_NAMESPACE}
```

### Log Collection

```bash
# Collect logs for troubleshooting
kubectl logs -l app.kubernetes.io/name=tekton-dashboard -n ${TEKTON_NAMESPACE} > dashboard.log
kubectl logs -l app.kubernetes.io/name=tekton-pipelines-controller -n ${TEKTON_NAMESPACE} > controller.log
kubectl describe ingress tekton-dashboard -n ${TEKTON_NAMESPACE} > ingress.log
```

## 📊 Production Considerations

### Security

- ✅ RBAC configured with minimal permissions
- ✅ Pod Security Standards enforced
- ✅ Network policies for traffic control
- ✅ TLS termination at Ingress (configure separately)

### Monitoring

- ✅ Resource limits configured
- ✅ Health checks enabled
- ✅ Logging configured for troubleshooting
- ✅ Metrics exposure for monitoring systems

### Scalability

- ✅ Horizontal Pod Autoscaler ready
- ✅ Resource requests/limits defined
- ✅ Node affinity for production workloads
- ✅ Persistent storage for pipeline artifacts (configure separately)

## 🔄 Next Steps

After successful completion of Stage 1:

1. **Verify Dashboard Access**: Visit `http://${TEKTON_DOMAIN}/`
2. **Test Pipeline Execution**: Run test pipelines through the UI
3. **Review Logs**: Check all components are functioning properly
4. **Proceed to Stage 2**: Install Tekton Triggers for CI/CD automation

```bash
# Continue to Stage 2
echo "✅ Stage 1 completed successfully!"
echo "🚀 Ready for Stage 2: CI/CD automation"
echo "📖 Next: cat docs/en/02-tekton-triggers-setup.md"
```

---

## 📚 Additional Resources

- **Tekton Pipelines Documentation**: https://tekton.dev/docs/pipelines/
- **Tekton Dashboard Documentation**: https://tekton.dev/docs/dashboard/
- **Nginx Ingress Controller**: https://kubernetes.github.io/ingress-nginx/
- **Kubernetes Ingress**: https://kubernetes.io/docs/concepts/services-networking/ingress/ 