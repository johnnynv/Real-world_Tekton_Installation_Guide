# Tekton Triggers Installation and Configuration Guide

This guide describes how to install and configure Tekton Triggers for event-driven Pipeline automation.

## 📋 Configuration Goals

- ✅ Install Tekton Triggers
- ✅ Configure RBAC permissions
- ✅ Create EventListener service
- ✅ Verify Triggers functionality

## 🔧 Prerequisites

- ✅ Completed [Tekton Core Installation](01-tekton-installation.md)
- ✅ Tekton Pipelines running normally
- ✅ kubectl access permissions

## 🚀 Step 1: Install Tekton Triggers

### Install Triggers Components
```bash
# Install latest Tekton Triggers version
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# Install Interceptors (event interceptors)
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# Wait for all Pods to be running
kubectl wait --for=condition=Ready pod --all -n tekton-pipelines --timeout=300s
```

### Verify Triggers Installation
```bash
# Check Triggers Pod status
kubectl get pods -n tekton-pipelines | grep triggers

# Check Triggers CRDs
kubectl get crd | grep triggers.tekton.dev
```

Expected output:
```
tekton-triggers-controller-xxx    Running
tekton-triggers-webhook-xxx       Running
tekton-triggers-core-interceptors-xxx    Running
```

## 🔐 Step 2: Configure RBAC Permissions

### Create Service Account and Permissions
```bash
# Create basic RBAC configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: tekton-pipelines
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
# Tekton Pipelines permissions
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "pipelineruns", "tasks", "taskruns"]
  verbs: ["get", "list", "create", "update", "patch", "watch"]

# Tekton Triggers permissions
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates", "triggers", "clusterinterceptors", "interceptors", "clustertriggerbindings"]
  verbs: ["get", "list", "create", "update", "patch", "watch"]

# Core Kubernetes resources
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "watch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: tekton-pipelines
roleRef:
  kind: ClusterRole
  name: tekton-triggers-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tekton-triggers-namespace-role
  namespace: tekton-pipelines
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-triggers-namespace-binding
  namespace: tekton-pipelines
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: tekton-pipelines
roleRef:
  kind: Role
  name: tekton-triggers-namespace-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 📝 Step 3: Create Basic Trigger Components

### Create Example TriggerTemplate
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: hello-world-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    description: Git repository URL
  - name: git-revision
    description: Git revision
    default: main
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: TaskRun
    metadata:
      generateName: hello-world-run-
    spec:
      taskSpec:
        params:
        - name: repo-url
          type: string
        - name: revision
          type: string
        steps:
        - name: hello
          image: ubuntu
          script: |
            #!/bin/bash
            echo "Triggered by event!"
            echo "Repository: \$(params.repo-url)"
            echo "Revision: \$(params.revision)"
      params:
      - name: repo-url
        value: \$(tt.params.git-repo-url)
      - name: revision
        value: \$(tt.params.git-revision)
EOF
```

### Create TriggerBinding
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: hello-world-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: \$(body.repository.clone_url)
  - name: git-revision
    value: \$(body.head_commit.id)
EOF
```

### Create EventListener
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: hello-world-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: hello-world-trigger
    bindings:
    - ref: hello-world-binding
    template:
      ref: hello-world-template
EOF
```

## 🌐 Step 4: Configure EventListener Access

### Get EventListener Service Information
```bash
# View EventListener service
kubectl get svc -n tekton-pipelines | grep el-

# Configure as NodePort service (for external access)
kubectl patch svc el-hello-world-listener -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'

# Get access address
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc el-hello-world-listener -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')

echo "EventListener access URL: http://${NODE_IP}:${NODE_PORT}"
```

## ✅ Verify Triggers Configuration

### 1. Run Verification Script (Recommended)
```bash
# Run complete verification script
chmod +x scripts/utils/verify-step2-triggers-setup.sh
./scripts/utils/verify-step2-triggers-setup.sh
```

The verification script automatically checks:
- ✅ Tekton Triggers component status
- ✅ Tekton Triggers CRDs
- ✅ RBAC permissions configuration
- ✅ Trigger resources configuration
- ✅ EventListener ready status
- ✅ EventListener functionality test (automatic trigger test)

### 2. Manual Component Check (Optional)
```bash
# Check EventListener status
kubectl get eventlistener -n tekton-pipelines

# Check TriggerTemplate and TriggerBinding
kubectl get triggertemplate,triggerbinding -n tekton-pipelines

# Check services and endpoints
kubectl get svc,endpoints -n tekton-pipelines | grep el-
```

### 3. Manual Test EventListener (Optional)
```bash
# Test EventListener response
curl -X POST http://${NODE_IP}:${NODE_PORT} \
  -H 'Content-Type: application/json' \
  -d '{
    "repository": {
      "clone_url": "https://github.com/example/test-repo.git"
    },
    "head_commit": {
      "id": "abcd1234"
    }
  }'
```

### 3. Verify Triggered TaskRun
```bash
# View triggered TaskRun
kubectl get taskruns -n tekton-pipelines

# View latest TaskRun logs
kubectl logs -l tekton.dev/task -n tekton-pipelines --tail=50
```

### 4. Dashboard Verification
Verify in Tekton Dashboard:
- ✅ EventListeners page shows listeners
- ✅ TaskRuns page shows triggered tasks
- ✅ Can view real-time execution logs

## 🔧 Troubleshooting

### Common Issues

**1. EventListener Pod Cannot Start**
```bash
# Check RBAC permissions
kubectl auth can-i create taskruns --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa -n tekton-pipelines

# Check Pod logs
kubectl logs -l app.kubernetes.io/component=eventlistener -n tekton-pipelines

# If you see permission errors, you may need to update ClusterRole permissions
# Common errors: cannot list resource "clusterinterceptors"/"interceptors"/"clustertriggerbindings"
kubectl patch clusterrole tekton-triggers-role --type='merge' -p='
{
  "rules": [
    {
      "apiGroups": ["tekton.dev"],
      "resources": ["pipelines", "pipelineruns", "tasks", "taskruns"],
      "verbs": ["get", "list", "create", "update", "patch", "watch"]
    },
    {
      "apiGroups": ["triggers.tekton.dev"],
      "resources": ["eventlisteners", "triggerbindings", "triggertemplates", "triggers", "clusterinterceptors", "interceptors", "clustertriggerbindings"],
      "verbs": ["get", "list", "create", "update", "patch", "watch"]
    },
    {
      "apiGroups": [""],
      "resources": ["pods", "services", "endpoints", "persistentvolumeclaims", "configmaps", "secrets"],
      "verbs": ["get", "list", "create", "update", "patch", "watch", "delete"]
    }
  ]
}'

# Restart EventListener Pod to apply new permissions
kubectl delete pod -l eventlistener=hello-world-listener -n tekton-pipelines
```

**2. Webhook Call Failed**
```bash
# Check service endpoints
kubectl get endpoints el-hello-world-listener -n tekton-pipelines

# Check network connectivity
kubectl run test-curl --image=curlimages/curl -it --rm -- curl -v http://el-hello-world-listener.tekton-pipelines.svc.cluster.local:8080
```

**3. TriggerTemplate Parameter Error**
```bash
# Check TriggerTemplate syntax
kubectl describe triggertemplate hello-world-template -n tekton-pipelines

# Check parameter binding
kubectl get triggerbinding hello-world-binding -o yaml -n tekton-pipelines
```

## 📊 Performance Optimization

### EventListener Configuration Optimization
```bash
# Configure multiple replicas for high-load scenarios
kubectl patch eventlistener hello-world-listener -n tekton-pipelines --type='merge' -p='
{
  "spec": {
    "resources": {
      "kubernetesResource": {
        "replicas": 3,
        "serviceType": "LoadBalancer"
      }
    }
  }
}'
```

## 📚 Next Steps

After Triggers configuration is complete, you can:
1. Configure GitHub Webhooks (automated CI/CD)
2. Deploy GPU scientific computing Pipeline

Continue reading: [03-tekton-webhook-configuration.md](03-tekton-webhook-configuration.md) 