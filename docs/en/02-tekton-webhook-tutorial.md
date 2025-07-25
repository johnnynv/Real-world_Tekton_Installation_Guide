# Tekton Webhook Triggers Getting Started Tutorial

This tutorial will guide you through configuring and using Tekton Triggers to implement GitHub Webhook-triggered Pipeline execution, with best practices demonstration based on the [johnnynv/tekton-poc](https://github.com/johnnynv/tekton-poc) project.

## 📋 Table of Contents

1. [Tekton Triggers Overview](#tekton-triggers-overview)
2. [Environment Setup](#environment-setup)
3. [Core Components Deep Dive](#core-components-deep-dive)
4. [Configure GitHub Webhook](#configure-github-webhook)
5. [Create Trigger Resources](#create-trigger-resources)
6. [Test Webhook Triggers](#test-webhook-triggers)
7. [Dashboard Monitoring](#dashboard-monitoring)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Configuration](#advanced-configuration)

## 🌟 Tekton Triggers Overview

### What is Tekton Triggers?

Tekton Triggers is a component of the Tekton ecosystem that automatically starts Pipeline execution based on external events (such as Git commits, Pull Requests).

### Core Components

- **EventListener**: Service that listens for HTTP events
- **TriggerBinding**: Extracts parameters from event data
- **TriggerTemplate**: Defines how to create Tekton resources
- **Interceptor**: Processes and filters incoming events

## 🔧 Environment Setup

### 1. Verify Tekton Triggers Installation

```bash
# Check Tekton Triggers components
kubectl get pods -n tekton-pipelines | grep trigger

# Check Triggers version
tkn version | grep Triggers

# View EventListener
kubectl get eventlistener -n tekton-pipelines
```

### 2. Clone Sample Project

```bash
# Clone tekton-poc project
git clone https://github.com/johnnynv/tekton-poc.git
cd tekton-poc

# View project structure
tree examples/
```

### 3. Check Existing Configuration

```bash
# View existing EventListener
kubectl get eventlistener -n tekton-pipelines -o yaml

# View Trigger-related resources
kubectl get triggertemplate,triggerbinding -n tekton-pipelines
```

## 📦 Core Components Deep Dive

### EventListener Configuration

View current EventListener configuration:

```bash
# View EventListener configuration
cat examples/triggers/github-eventlistener.yaml
```

**Configuration Explanation**:
- **Service Account**: `tekton-triggers-sa` - execution permission management
- **Interceptor**: GitHub interceptor validates webhook signature
- **Event Types**: Only processes "push" events
- **Binding Reference**: Connects to TriggerBinding and TriggerTemplate

### TriggerBinding Creation

Create TriggerBinding to extract parameters from GitHub events:

```yaml
# examples/triggers/github-trigger-binding.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: $(body.repository.clone_url)
  - name: git-revision
    value: $(body.head_commit.id)
  - name: git-repo-name
    value: $(body.repository.name)
```

### TriggerTemplate Creation

Create TriggerTemplate to define the Pipeline to start:

```yaml
# examples/triggers/github-trigger-template.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    description: Git repository URL
  - name: git-revision
    description: Git revision
  - name: git-repo-name
    description: Git repository name
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: webhook-pipeline-run-
      namespace: tekton-pipelines
      labels:
        app: tekton-webhook
        trigger: github-push
    spec:
      pipelineRef:
        name: git-clone-and-build-pipeline
      params:
      - name: repo-url
        value: $(tt.params.git-repo-url)
      - name: revision
        value: $(tt.params.git-revision)
      - name: repo-name
        value: $(tt.params.git-repo-name)
```

## 🔐 Configure GitHub Webhook

### 1. Create Webhook Secret

```bash
# Generate random token
WEBHOOK_SECRET=$(openssl rand -hex 20)
echo "Generated webhook secret: $WEBHOOK_SECRET"

# Create Kubernetes Secret
kubectl create secret generic github-webhook-secret \
  --from-literal=secretToken=$WEBHOOK_SECRET \
  -n tekton-pipelines

# Verify Secret creation
kubectl get secret github-webhook-secret -n tekton-pipelines
```

### 2. Get EventListener Service Address

```bash
# View EventListener service
kubectl get service -n tekton-pipelines | grep listener

# If using LoadBalancer
kubectl get service el-github-webhook-listener -n tekton-pipelines

# If using NodePort or need port forwarding
kubectl port-forward service/el-github-webhook-listener -n tekton-pipelines 8080:8080
```

### 3. Configure Webhook on GitHub

1. Go to your GitHub repository (johnnynv/tekton-poc)
2. Click **Settings** → **Webhooks** → **Add webhook**
3. Configure the following:
   - **Payload URL**: `http://your-eventlistener-url:8080`
   - **Content type**: `application/json`
   - **Secret**: Enter the previously generated `$WEBHOOK_SECRET`
   - **Events**: Select "Just the push event"
   - **Active**: ✅ Check

## 🛠️ Create Trigger Resources

### 1. Create Git Clone Pipeline

```bash
# Create Pipeline for Git clone and build
cat << 'EOF' > examples/pipelines/git-clone-build-pipeline.yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: git-clone-and-build-pipeline
  namespace: tekton-pipelines
spec:
  description: |
    Pipeline triggered by GitHub webhook to clone and build
  params:
  - name: repo-url
    type: string
    description: Git repository URL
  - name: revision
    type: string
    description: Git revision to checkout
    default: main
  - name: repo-name
    type: string
    description: Repository name
  tasks:
  - name: fetch-repository
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.repo-url)
    - name: revision
      value: $(params.revision)
    workspaces:
    - name: output
      workspace: shared-data
  - name: build-project
    taskRef:
      name: hello-world
    runAfter:
    - fetch-repository
  workspaces:
  - name: shared-data
EOF
```

### 2. Apply All Trigger Resources

```bash
# Create TriggerBinding
kubectl apply -f - << 'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
    value: $(body.repository.clone_url)
  - name: git-revision
    value: $(body.head_commit.id)
  - name: git-repo-name
    value: $(body.repository.name)
EOF

# Create TriggerTemplate
kubectl apply -f - << 'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: git-repo-name
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: webhook-pipeline-run-
      namespace: tekton-pipelines
      labels:
        app: tekton-webhook
        trigger: github-push
    spec:
      pipelineRef:
        name: hello-world-pipeline
      workspaces:
      - name: shared-data
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
EOF

# Apply existing EventListener
kubectl apply -f examples/triggers/github-eventlistener.yaml

# Verify resource creation
kubectl get triggertemplate,triggerbinding,eventlistener -n tekton-pipelines
```

## 🧪 Test Webhook Triggers

### 1. Manual Trigger Test

```bash
# Get EventListener service address
EL_URL=$(kubectl get route el-github-webhook-listener -n tekton-pipelines -o jsonpath='{.spec.host}' 2>/dev/null || echo "localhost:8080")

# If using port forwarding
kubectl port-forward service/el-github-webhook-listener -n tekton-pipelines 8080:8080 &

# Send test webhook request
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{"repository":{"clone_url":"https://github.com/johnnynv/tekton-poc.git","name":"tekton-poc"},"head_commit":{"id":"test123"}}' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | cut -d' ' -f2)" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/johnnynv/tekton-poc.git",
      "name": "tekton-poc"
    },
    "head_commit": {
      "id": "test123"
    }
  }'
```

### 2. Trigger via Git Push

```bash
# Make changes in locally cloned project
echo "# Test webhook trigger $(date)" >> README.md

# Commit and push changes
git add README.md
git commit -m "Test webhook trigger"
git push origin main
```

### 3. Monitor Trigger Results

```bash
# View newly created PipelineRun
tkn pipelinerun list -n tekton-pipelines | head -5

# View latest PipelineRun logs
tkn pipelinerun logs --last -f -n tekton-pipelines

# View EventListener pod logs
kubectl logs -l app.kubernetes.io/name=eventlistener -n tekton-pipelines -f
```

## 📊 Dashboard Monitoring

### Access Dashboard

```bash
# Check Dashboard status
kubectl get pods -n tekton-pipelines | grep dashboard

# Port forward to access Dashboard
kubectl port-forward service/tekton-dashboard -n tekton-pipelines 9097:9097
```

Open browser and visit `http://localhost:9097`

### Dashboard Features

1. **PipelineRuns Page**
   - View webhook-triggered run records
   - Monitor execution status in real-time
   - Filter runs with label `trigger: github-push`

2. **Events Page**
   - View events received by EventListener
   - Monitor webhook trigger history

3. **Logs Viewing**
   - Click specific PipelineRun to view detailed logs
   - View output of each Task execution

## 🔧 Troubleshooting

### 1. EventListener Issues

```bash
# Check EventListener pod status
kubectl get pods -l app.kubernetes.io/name=eventlistener -n tekton-pipelines

# View EventListener details
kubectl describe eventlistener github-webhook-listener -n tekton-pipelines

# View EventListener logs
kubectl logs -l app.kubernetes.io/name=eventlistener -n tekton-pipelines
```

### 2. Webhook Verification Issues

```bash
# Check webhook secret
kubectl get secret github-webhook-secret -n tekton-pipelines -o yaml

# Test webhook signature verification
PAYLOAD='{"test":"data"}'
SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | cut -d' ' -f2)
echo "X-Hub-Signature-256: sha256=$SIGNATURE"
```

### 3. Pipeline Execution Issues

```bash
# View failed PipelineRuns
tkn pipelinerun list -n tekton-pipelines | grep Failed

# View specific error information
tkn pipelinerun describe <failed-pipelinerun> -n tekton-pipelines

# View related events
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp' | tail -10
```

### 4. Permission Issues

```bash
# Check ServiceAccount
kubectl get serviceaccount tekton-triggers-sa -n tekton-pipelines

# Check ClusterRoleBinding
kubectl get clusterrolebinding | grep tekton-triggers

# Check permissions
kubectl auth can-i create pipelineruns --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa
```

## 🚀 Advanced Configuration

### 1. Multiple Event Type Support

```yaml
# Support multiple GitHub events
spec:
  triggers:
  - name: github-push-trigger
    interceptors:
    - ref:
        name: "github"
      params:
      - name: "eventTypes"
        value: ["push", "pull_request"]
```

### 2. Conditional Triggering

```yaml
# Only trigger for specific branches
interceptors:
- ref:
    name: "cel"
  params:
  - name: "filter"
    value: "body.ref == 'refs/heads/main'"
```

### 3. Parameter Mapping

```yaml
# More parameter extraction
spec:
  params:
  - name: git-branch
    value: $(body.ref)
  - name: git-author
    value: $(body.head_commit.author.name)
  - name: git-message
    value: $(body.head_commit.message)
```

### 4. Workspace Configuration

```yaml
# Persistent workspace
workspaces:
- name: shared-data
  persistentVolumeClaim:
    claimName: tekton-workspace-pvc
```

## 📝 Hands-on Exercises

### Exercise 1: Basic Webhook Setup

1. Configure GitHub webhook
2. Create simple trigger flow
3. Verify automatic execution after code push

### Exercise 2: Multi-stage Pipeline

1. Create Pipeline with build, test, deploy stages
2. Configure parameter passing
3. Test complete CI/CD flow

### Exercise 3: Conditional Execution

1. Set up branch filtering conditions
2. Configure different Pipelines for different branches
3. Test conditional trigger logic

## 🎉 Summary

Through this tutorial, you have learned:

- ✅ Core concepts and components of Tekton Triggers
- ✅ Configuring GitHub Webhook to automatically trigger Pipelines
- ✅ Creating EventListener, TriggerBinding, and TriggerTemplate
- ✅ Monitoring webhook-triggered executions in Dashboard
- ✅ Troubleshooting and problem-solving methods

### 🔗 Related Resources

- [Tekton Triggers Official Documentation](https://tekton.dev/docs/triggers/)
- [GitHub Webhook Documentation](https://docs.github.com/en/developers/webhooks-and-events/webhooks)
- [Tekton POC Project](https://github.com/johnnynv/tekton-poc)

Next recommended learning:
- Advanced Interceptor configuration
- Multi-cloud environment deployment
- Security best practices 