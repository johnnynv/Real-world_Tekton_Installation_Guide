# Tekton Triggers v0.33.0 Configuration Guide

This guide provides detailed instructions for configuring Tekton Triggers v0.33.0 on top of the existing Tekton Pipelines v1.3.0 installation to enable automated CI/CD triggering capabilities.

## 🎯 Configuration Planning

### Version Selection
- **Tekton Triggers**: v0.33.0 (Latest stable version)
- **Base Environment**: Kubernetes v1.30.14 + Tekton Pipelines v1.3.0
- **Trigger Methods**: Git Webhook + EventListener
- **Supported Git Platforms**: GitHub, GitLab, Bitbucket

### Component Architecture
```
Complete Tekton Triggers Architecture
├── EventListener (Event Listener)
│   ├── TriggerBinding (Parameter Binding)
│   ├── TriggerTemplate (Template Definition)
│   └── Interceptor (Interceptor/Filter)
├── Webhook Service (Webhook Service)
├── Triggers Controller (Triggers Controller)
└── Pipeline Integration (Pipeline Integration)
```

## 🏁 Step 1: Environment Verification

### Verify Tekton Pipelines Status
```bash
# Check existing Tekton components
kubectl get pods -n tekton-pipelines
kubectl get crd | grep tekton
```

**Verification Results**:
```
# Tekton component status
NAME                                           READY   STATUS    RESTARTS   AGE
tekton-dashboard-75d96bd9f-lvfhn               1/1     Running   0          51m
tekton-events-controller-bcd894689-2wtff       1/1     Running   0          53m
tekton-pipelines-controller-685d97d7db-pwwxx   1/1     Running   0          53m
tekton-pipelines-webhook-6f7d65db5-jmgpn       1/1     Running   0          53m
tekton-pipelines-remote-resolvers-xxx          1/1     Running   0          53m

# Custom Resource Definitions
customruns.tekton.dev                                 2025-08-20T11:19:39Z
pipelineruns.tekton.dev                               2025-08-20T11:19:39Z
pipelines.tekton.dev                                  2025-08-20T11:19:39Z
tasks.tekton.dev                                      2025-08-20T11:19:39Z
taskruns.tekton.dev                                   2025-08-20T11:19:39Z
```

- ✅ Tekton Pipelines v1.3.0 running normally
- ✅ All core components status normal

## 🔧 Step 2: Install Tekton Triggers v0.33.0

### Get Latest Version Information
```bash
# Check latest Tekton Triggers version
curl -s https://api.github.com/repos/tektoncd/triggers/releases/latest | grep -E '"tag_name"'
```

**Version Information Result**:
```json
"tag_name": "v0.33.0"
```

### Install Tekton Triggers
```bash
# Install Tekton Triggers latest version
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
```

**Installation Results**:
```
clusterrole.rbac.authorization.k8s.io/tekton-triggers-admin created
clusterrole.rbac.authorization.k8s.io/tekton-triggers-core-interceptors created
clusterrole.rbac.authorization.k8s.io/tekton-triggers-core-interceptors-secrets created
clusterrole.rbac.authorization.k8s.io/tekton-triggers-eventlistener-roles created
clusterrole.rbac.authorization.k8s.io/tekton-triggers-eventlistener-clusterroles created
serviceaccount/tekton-triggers-controller created
serviceaccount/tekton-triggers-webhook created
serviceaccount/tekton-triggers-core-interceptors created
customresourcedefinition.apiextensions.k8s.io/clusterinterceptors.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/clustertriggerbindings.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/eventlisteners.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/interceptors.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/triggers.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/triggerbindings.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/triggertemplates.triggers.tekton.dev created
deployment.apps/tekton-triggers-controller created
deployment.apps/tekton-triggers-webhook created
```

### Verify Installation
```bash
# Check Triggers component status
kubectl get pods -n tekton-pipelines | grep triggers
kubectl get crd | grep triggers

# Get version information
kubectl get deployment tekton-triggers-controller -n tekton-pipelines -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Verification Results**:
```
# Triggers component status
tekton-triggers-controller-7ddb4685-zmzhf      1/1     Running   0          22m
tekton-triggers-webhook-5b8765fdc9-gndtv       1/1     Running   0          22m

# Triggers related CRDs
clusterinterceptors.triggers.tekton.dev               2025-08-20T11:50:00Z
clustertriggerbindings.triggers.tekton.dev            2025-08-20T11:50:00Z
eventlisteners.triggers.tekton.dev                    2025-08-20T11:50:00Z
interceptors.triggers.tekton.dev                      2025-08-20T11:50:00Z
triggerbindings.triggers.tekton.dev                   2025-08-20T11:50:00Z
triggers.triggers.tekton.dev                          2025-08-20T11:50:00Z
triggertemplates.triggers.tekton.dev                  2025-08-20T11:50:00Z

# Version information
ghcr.io/tektoncd/triggers/controller:v0.33.0
```

**Triggers Installation Verification Results**:
- ✅ Tekton Triggers v0.33.0 installed successfully
- ✅ Controller and Webhook running normally
- ✅ 7 Custom Resource Definitions created

**⚠️ Important Note**: After basic installation, you also need to install the Interceptors component, otherwise EventListener will fail to start.

## 📝 Step 3: Create Sample Pipeline

### Create Simple Build Pipeline
```bash
# Create sample Pipeline
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: hello-pipeline
  namespace: default
spec:
  params:
  - name: git-url
    type: string
    description: Git repository URL
  - name: git-revision
    type: string
    description: Git revision
    default: main
  - name: message
    type: string
    description: Message to display
    default: "Hello from Tekton!"
  tasks:
  - name: hello-task
    taskSpec:
      params:
      - name: git-url
        type: string
      - name: git-revision
        type: string
      - name: message
        type: string
      steps:
      - name: hello
        image: alpine:latest
        script: |
          #!/bin/sh
          echo "==================================="
          echo "Git URL: \$(params.git-url)"
          echo "Git Revision: \$(params.git-revision)"
          echo "Message: \$(params.message)"
          echo "==================================="
          echo "Pipeline executed successfully!"
    params:
    - name: git-url
      value: \$(params.git-url)
    - name: git-revision
      value: \$(params.git-revision)
    - name: message
      value: \$(params.message)
EOF
```

### Verify Pipeline Creation
```bash
# Verify Pipeline creation
kubectl get pipeline hello-pipeline
kubectl describe pipeline hello-pipeline
```

## 🎯 Step 4: Configure TriggerTemplate

### Create TriggerTemplate
```bash
# Create TriggerTemplate defining how to create PipelineRun
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: hello-trigger-template
  namespace: default
spec:
  params:
  - name: git-url
    description: Git repository URL
  - name: git-revision
    description: Git revision
    default: main
  - name: message
    description: Trigger message
    default: "Triggered by webhook!"
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: hello-pipeline-run-
    spec:
      pipelineRef:
        name: hello-pipeline
      params:
      - name: git-url
        value: \$(tt.params.git-url)
      - name: git-revision
        value: \$(tt.params.git-revision)
      - name: message
        value: \$(tt.params.message)
EOF
```

### Verify TriggerTemplate
```bash
# Verify TriggerTemplate creation
kubectl get triggertemplate hello-trigger-template
kubectl describe triggertemplate hello-trigger-template
```

## 🔗 Step 5: Configure TriggerBinding

### Create TriggerBinding
```bash
# Create TriggerBinding to extract parameters from webhook payload
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: hello-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.repository.clone_url)
  - name: git-revision
    value: \$(body.head_commit.id)
  - name: message
    value: "Triggered by \$(body.pusher.name) on \$(body.repository.name)"
EOF
```

### Verify TriggerBinding
```bash
# Verify TriggerBinding creation
kubectl get triggerbinding hello-trigger-binding
kubectl describe triggerbinding hello-trigger-binding
```

## 🔌 Step 6: Install Tekton Interceptors

### Install Interceptors Component
```bash
# Install Tekton Triggers Interceptors (required component)
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# Verify Interceptors installation
kubectl get pods -n tekton-pipelines | grep interceptors
kubectl get clusterinterceptor
```

**Interceptors Installation Results**:
```
# Core Interceptors component
tekton-triggers-core-interceptors-57885b7d99-r9wvl   1/1     Running   0          5m10s

# Available ClusterInterceptors
NAME        AGE
bitbucket   5m15s
cel         5m15s
github      5m15s
gitlab      5m14s
slack       5m15s
```

- ✅ Core Interceptors service running normally
- ✅ GitHub, GitLab and other platform interceptors available
- ✅ CA certificates required for EventListener startup configured

## 🎧 Step 7: Configure EventListener

### Create EventListener ServiceAccount
```bash
# Create ServiceAccount and permissions
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-eventlistener-roles
rules:
# Core permissions needed by EventListener
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggers", "triggerbindings", "triggertemplates"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["triggers.tekton.dev"] 
  resources: ["clustertriggerbindings", "clusterinterceptors"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["interceptors"]
  verbs: ["get", "list", "watch"]
# Pipeline execution permissions
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "taskruns", "pipelines", "tasks"]
  verbs: ["create", "get", "list", "watch"]
# Basic Kubernetes resource permissions
- apiGroups: [""]
  resources: ["configmaps", "secrets", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["serviceaccounts"]
  verbs: ["impersonate"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-eventlistener-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: default
roleRef:
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Create EventListener
```bash
# Create EventListener to listen for webhook events
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: hello-event-listener
  namespace: default
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: hello-trigger
    bindings:
    - ref: hello-trigger-binding
    template:
      ref: hello-trigger-template
EOF
```

### Verify EventListener
```bash
# Verify EventListener creation and service status
kubectl get eventlistener hello-event-listener
kubectl get svc el-hello-event-listener
kubectl get pods -l eventlistener=hello-event-listener
```

## 🌐 Step 8: Configure Webhook Access

### Check EventListener Service
```bash
# Get EventListener service information
kubectl get svc el-hello-event-listener -o wide
kubectl describe svc el-hello-event-listener
```

### Create NodePort Service
```bash
# Create NodePort service for external access
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: hello-webhook-nodeport
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30088
    protocol: TCP
  selector:
    eventlistener: hello-event-listener
EOF
```

### Verify Webhook Access
```bash
# Get NodePort service status
kubectl get svc hello-webhook-nodeport

# Test webhook endpoint
curl -X POST http://localhost:30088 \
  -H "Content-Type: application/json" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/example/repo.git",
      "name": "example-repo"
    },
    "head_commit": {
      "id": "abc123def456"
    },
    "pusher": {
      "name": "developer"
    }
  }'
```

## 🧪 Step 9: Test Triggers Functionality

### Manual Pipeline Trigger Test
```bash
# Send test webhook request
curl -X POST http://10.78.14.61:30088 \
  -H "Content-Type: application/json" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/test/repo.git",
      "name": "test-repo"
    },
    "head_commit": {
      "id": "abc123def456"
    },
    "pusher": {
      "name": "test-developer"
    }
  }'

# Check automatically created PipelineRun
kubectl get pipelinerun
kubectl logs -f $(kubectl get pipelinerun -o name | head -1)
```

### Verify Trigger Results
```bash
# Check latest PipelineRun status
kubectl get pipelinerun --sort-by=.metadata.creationTimestamp
kubectl describe pipelinerun $(kubectl get pipelinerun -o name | head -1)

# View Pipeline execution logs
kubectl logs -l tekton.dev/pipelineRun=$(kubectl get pipelinerun -o name | head -1 | cut -d'/' -f2)
```

**Real Test Results**:
```
# Webhook response
{"eventListener":"hello-event-listener","namespace":"default","eventListenerUID":"e19a8483-e1c6-4796-867c-0bed0f84a583","eventID":"c4d5dd48-9599-447e-aece-00095adf263c"}

# PipelineRun execution status
NAME                       SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
hello-pipeline-run-s9wrp   True        Succeeded   10s         0s

# Pipeline execution logs
===================================
Git URL: https://github.com/test/repo.git
Git Revision: abc123def456
Message: Triggered by test-developer on test-repo
===================================
Pipeline executed successfully!
```

- ✅ Webhook request successfully received and parsed
- ✅ PipelineRun automatically created and executed
- ✅ TriggerBinding parameters correctly extracted
- ✅ Pipeline execution completed successfully

## 📊 Step 10: Dashboard Monitoring Integration

### View Triggers in Tekton Dashboard
Access via browser: `https://tekton.10.78.14.61.nip.io`

Login credentials: `admin` / `admin123`

In the Dashboard you can see:
- EventListeners status
- Automatically triggered PipelineRuns
- Triggers configuration information
- Real-time logs and status

## 📋 Configuration Results Summary

### ✅ Successfully Configured Components
1. **Tekton Triggers**: v0.33.0 (Event trigger engine)
2. **EventListener**: hello-event-listener (Webhook listener)
3. **TriggerTemplate**: hello-trigger-template (Pipeline template)
4. **TriggerBinding**: hello-trigger-binding (Parameter binding)
5. **Pipeline**: hello-pipeline (Sample pipeline)
6. **NodePort Service**: Port 30088 (External access)
7. **Interceptors**: Core interceptors and platform-specific interceptors

### 🔄 Workflow Verification
```
Complete Triggers Workflow
├── Git Push Event (Git push event)
├── Webhook POST Request (Webhook request)
├── EventListener (Event listener receives)
├── TriggerBinding (Parameter extraction and binding)
├── TriggerTemplate (Create PipelineRun)
└── Pipeline Execution (Pipeline execution)
```

### 🌐 **Webhook Access Information**

**Webhook Endpoint URL**:
```
http://10.78.14.61:30088
```

**Test Command**:
```bash
curl -X POST http://10.78.14.61:30088 \
  -H "Content-Type: application/json" \
  -d '{"repository":{"clone_url":"https://github.com/example/repo.git","name":"test-repo"},"head_commit":{"id":"abc123def456"},"pusher":{"name":"developer"}}'
```

### 🎯 Production Environment Ready
This Tekton Triggers configuration is prepared for the following scenarios:
- **GitHub/GitLab Integration**: Support for standard webhook formats
- **Automated CI/CD**: Git push automatically triggers Pipeline
- **Multi-repository Support**: Can configure multiple EventListeners
- **Parameterized Builds**: Support for dynamic parameter passing
- **Monitoring Integration**: Full integration with Tekton Dashboard

## 🚀 Next Steps

After completing the Tekton Triggers configuration, you can continue with:
1. [Configure Git Webhook](05-tekton-webhook-configuration.md)
2. [Setup User Permissions](06-tekton-restricted-user-setup.md)
3. [Deploy GPU Pipeline](07-gpu-pipeline-deployment.md)

## 🎉 Summary

Successfully completed the complete configuration of Tekton Triggers! Now you can use it through the following methods:

**🎧 Webhook Endpoint**: http://10.78.14.61:30088  
**🌐 Dashboard Monitoring**: https://tekton.10.78.14.61.nip.io  
**👤 Login Credentials**: admin / admin123

Enjoy your automated CI/CD journey!