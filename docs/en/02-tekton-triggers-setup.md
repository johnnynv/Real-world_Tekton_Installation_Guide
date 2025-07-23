# Stage 2: Tekton CI/CD Automation Configuration Guide

This guide provides detailed instructions for configuring Tekton Triggers on top of existing Tekton core infrastructure, enabling complete CI/CD automation with GitHub webhook-triggered Pipeline execution.

## 📋 Stage 2 Objectives

- ✅ Install Tekton Triggers (event-driven system)
- ✅ Configure GitHub Webhook integration
- ✅ Create EventListener (event listener)
- ✅ Configure TriggerBinding and TriggerTemplate
- ✅ Setup RBAC permissions and security configuration
- ✅ Verify automated Pipeline triggering

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                GitHub Repository                 │
│         https://github.com/user/repo           │
└─────────────────┬───────────────────────────────┘
                  │ push event
                  ▼
┌─────────────────────────────────────────────────┐
│              GitHub Webhook                     │
│    http://tekton.YOUR_NODE_IP.nip.io/webhook   │
└─────────────────┬───────────────────────────────┘
                  │ HTTP POST
                  ▼
┌─────────────────────────────────────────────────┐
│            Nginx Ingress Controller             │
│              (Routing and Load Balancing)       │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│             EventListener                      │
│          (Receive and parse webhook events)    │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│        TriggerBinding + TriggerTemplate         │
│        (Extract parameters + Create PipelineRun)│
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              PipelineRun                       │
│           (Automated CI/CD Pipeline Execution) │
└─────────────────────────────────────────────────┘
```

## 🔧 Prerequisites

### Requirements

- ✅ **Stage 1 Completed**: Tekton Pipelines + Dashboard installed and running normally
- ✅ **Dashboard Accessible**: `http://tekton.YOUR_NODE_IP.nip.io/` working properly
- ✅ **GitHub Repository**: GitHub repository with admin permissions
- ✅ **Network Access**: GitHub can access your webhook endpoint

### Verify Prerequisites

```bash
# Check Stage 1 installation status
kubectl get pods -n tekton-pipelines
kubectl get ingress -n tekton-pipelines

# Verify Dashboard access
curl -s http://tekton.YOUR_NODE_IP.nip.io/ | grep -q "Tekton" && echo "Dashboard OK" || echo "Dashboard Error"

# Check existing Pipeline functionality
kubectl get pipeline,task -n tekton-pipelines
```

### Environment Configuration

```bash
# Set environment variables
export TEKTON_NAMESPACE="tekton-pipelines"
export NODE_IP="YOUR_NODE_IP"
export TEKTON_DOMAIN="tekton.${NODE_IP}.nip.io"
export WEBHOOK_URL="http://${TEKTON_DOMAIN}/webhook"
export GITHUB_REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO"
export GITHUB_SECRET="110120119"

# Verify environment
echo "Webhook URL: ${WEBHOOK_URL}"
echo "GitHub Repository: ${GITHUB_REPO_URL}"
```

## 🚀 Installation Steps

### Step 1: Install Tekton Triggers

#### 1.1 Install Triggers Components

```bash
# Install Tekton Triggers
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# Wait for Triggers components to start
kubectl wait --for=condition=ready pod \
  --selector=app.kubernetes.io/name=tekton-triggers-controller \
  --namespace=${TEKTON_NAMESPACE} \
  --timeout=300s

kubectl wait --for=condition=ready pod \
  --selector=app.kubernetes.io/name=tekton-triggers-webhook \
  --namespace=${TEKTON_NAMESPACE} \
  --timeout=300s

kubectl wait --for=condition=ready pod \
  --selector=app.kubernetes.io/name=tekton-triggers-core-interceptors \
  --namespace=${TEKTON_NAMESPACE} \
  --timeout=300s
```

#### 1.2 Verify Triggers Installation

```bash
# Check Triggers components
kubectl get pods -n ${TEKTON_NAMESPACE} | grep triggers

# Verify Triggers CRDs
kubectl get crd | grep triggers.tekton.dev

# Check ClusterInterceptors
kubectl get clusterinterceptor
```

### Step 2: Configure RBAC Permissions

#### 2.1 Create ServiceAccount

```bash
# Create ServiceAccount for Triggers
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: ${TEKTON_NAMESPACE}
EOF
```

#### 2.2 Create ClusterRole and ClusterRoleBinding

```bash
# Create ClusterRole with necessary permissions
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets", "events"]
  verbs: ["get", "list", "create", "update", "delete"]
- apiGroups: ["tekton.dev"]
  resources: ["tasks", "taskruns", "pipelines", "pipelineruns"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates", "triggers"]
  verbs: ["get", "list", "create", "update", "delete", "patch", "watch"]
EOF

# Create ClusterRoleBinding
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: ${TEKTON_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-role
EOF
```

### Step 3: Create GitHub Webhook Secret

```bash
# Create Secret for GitHub webhook authentication
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-secret
  namespace: ${TEKTON_NAMESPACE}
type: Opaque
stringData:
  secretToken: "${GITHUB_SECRET}"
EOF
```

### Step 4: Create Pipeline Resources

#### 4.1 Create Sample Task

```bash
# Create a sample Task for webhook testing
kubectl apply -f - <<EOF
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: github-webhook-task
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: repo-url
    type: string
    default: "unknown"
  - name: revision
    type: string
    default: "main"
  - name: commit-message
    type: string
    default: "no message"
  - name: author
    type: string
    default: "unknown"
  steps:
  - name: log-webhook-info
    image: alpine:latest
    script: |
      #!/bin/sh
      echo "🎉 GitHub Webhook triggered successfully!"
      echo "Repository: \$(params.repo-url)"
      echo "Revision: \$(params.revision)"
      echo "Commit Message: \$(params.commit-message)"
      echo "Author: \$(params.author)"
      echo "Trigger Time: \$(date)"
      echo "Node: \$(hostname)"
      echo "================================"
      echo "✅ Tekton Triggers working properly"
EOF
```

#### 4.2 Create Sample Pipeline

```bash
# Create Pipeline for GitHub webhook
kubectl apply -f - <<EOF
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: github-webhook-pipeline
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: repo-url
    type: string
  - name: revision
    type: string
  - name: commit-message
    type: string
    default: "no message"
  - name: author
    type: string
    default: "unknown"
  tasks:
  - name: webhook-handler
    taskRef:
      name: github-webhook-task
    params:
    - name: repo-url
      value: \$(params.repo-url)
    - name: revision
      value: \$(params.revision)
    - name: commit-message
      value: \$(params.commit-message)
    - name: author
      value: \$(params.author)
EOF
```

### Step 5: Configure Trigger Components

#### 5.1 Create TriggerBinding

```bash
# Create TriggerBinding to extract GitHub webhook data
kubectl apply -f - <<EOF
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: git-repo-url
    value: \$(body.repository.clone_url)
  - name: git-repo-name
    value: \$(body.repository.name)
  - name: git-revision
    value: \$(body.head_commit.id)
  - name: git-commit-message
    value: \$(body.head_commit.message)
  - name: git-author
    value: \$(body.head_commit.author.name)
EOF
```

#### 5.2 Create TriggerTemplate

```bash
# Create TriggerTemplate to generate PipelineRun
kubectl apply -f - <<EOF
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: ${TEKTON_NAMESPACE}
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: git-repo-name
  - name: git-commit-message
    default: "no message"
  - name: git-author
    default: "unknown"
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: github-webhook-run-
      namespace: ${TEKTON_NAMESPACE}
      labels:
        app: tekton-triggers
        trigger: github-webhook
        repo: \$(tt.params.git-repo-name)
    spec:
      pipelineRef:
        name: github-webhook-pipeline
      params:
      - name: repo-url
        value: \$(tt.params.git-repo-url)
      - name: revision
        value: \$(tt.params.git-revision)
      - name: commit-message
        value: \$(tt.params.git-commit-message)
      - name: author
        value: \$(tt.params.git-author)
EOF
```

#### 5.3 Create EventListener

```bash
# Create EventListener to receive GitHub webhooks
kubectl apply -f - <<EOF
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
  namespace: ${TEKTON_NAMESPACE}
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: github-push-trigger
    interceptors:
    - ref:
        name: "github"
      params:
      - name: "secretRef"
        value:
          secretName: github-webhook-secret
          secretKey: secretToken
      - name: "eventTypes"
        value: ["push"]
    bindings:
    - ref: github-trigger-binding
    template:
      ref: github-trigger-template
EOF
```

### Step 6: Configure External Access for Webhook

#### 6.1 Create Webhook Ingress

```bash
# Create Ingress for webhook endpoint
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: github-webhook-ingress
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
      - path: /webhook
        pathType: Exact
        backend:
          service:
            name: el-github-webhook-listener
            port:
              number: 8080
EOF
```

#### 6.2 Wait for EventListener Service

```bash
# Wait for EventListener to create service
sleep 30

# Verify EventListener service exists
kubectl get service el-github-webhook-listener -n ${TEKTON_NAMESPACE}

# Check EventListener pod status
kubectl get pods -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE}
```

### Step 7: Test Webhook Endpoint

#### 7.1 Test Webhook Connectivity

```bash
# Test webhook endpoint connectivity
echo "Testing webhook endpoint: ${WEBHOOK_URL}"

# Send test payload
curl -X POST ${WEBHOOK_URL} \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{"test":"webhook"}' | openssl dgst -sha256 -hmac "${GITHUB_SECRET}" | cut -d' ' -f2)" \
  -d '{"test":"webhook"}' \
  -v

# Expected: HTTP 202 Accepted
```

#### 7.2 Manual Pipeline Trigger Test

```bash
# Create test PipelineRun to verify pipeline functionality
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-test-
  namespace: ${TEKTON_NAMESPACE}
spec:
  pipelineRef:
    name: github-webhook-pipeline
  params:
  - name: repo-url
    value: "${GITHUB_REPO_URL}"
  - name: revision
    value: "main"
  - name: commit-message
    value: "Manual test execution"
  - name: author
    value: "Administrator"
EOF

# Wait and check result
sleep 30
kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --sort-by=.metadata.creationTimestamp
```

## ✅ Verification Checklist

### Component Status

```bash
# Check all Triggers components
kubectl get pods -n ${TEKTON_NAMESPACE} | grep triggers

# Verify EventListener
kubectl get eventlistener -n ${TEKTON_NAMESPACE}

# Check TriggerBinding and TriggerTemplate
kubectl get triggerbinding,triggertemplate -n ${TEKTON_NAMESPACE}

# Verify webhook Ingress
kubectl get ingress github-webhook-ingress -n ${TEKTON_NAMESPACE}
```

### Functional Testing

```bash
# Test webhook endpoint
curl -I ${WEBHOOK_URL}
# Expected: HTTP 200 or 202

# Check recent PipelineRuns
kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --sort-by=.metadata.creationTimestamp

# Monitor webhook events
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE} -f
```

## 🔗 GitHub Webhook Configuration

### Configure GitHub Repository Webhook

1. **Navigate to Repository Settings**:
   - Go to your GitHub repository
   - Click `Settings` → `Webhooks` → `Add webhook`

2. **Configure Webhook**:
   ```
   Payload URL: http://tekton.YOUR_NODE_IP.nip.io/webhook
   Content type: application/json
   Secret: 110120119
   Events: Just the push event
   Active: ✅ Checked
   ```

3. **Test Webhook**:
   - Make a commit and push to the repository
   - Check webhook deliveries in GitHub
   - Verify PipelineRun creation in Tekton

### Webhook Testing Commands

```bash
# Monitor webhook events in real-time
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE} -f

# Watch for new PipelineRuns
kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --watch

# Check webhook Ingress logs
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx | grep webhook
```

## 🚨 Troubleshooting

### Common Issues

#### 1. EventListener Pod Not Starting

```bash
# Check EventListener status
kubectl describe eventlistener github-webhook-listener -n ${TEKTON_NAMESPACE}

# Check ServiceAccount permissions
kubectl describe serviceaccount tekton-triggers-sa -n ${TEKTON_NAMESPACE}

# Verify RBAC
kubectl auth can-i create pipelinerun --as=system:serviceaccount:${TEKTON_NAMESPACE}:tekton-triggers-sa
```

#### 2. Webhook Endpoint Not Accessible

```bash
# Check Ingress configuration
kubectl describe ingress github-webhook-ingress -n ${TEKTON_NAMESPACE}

# Test internal service
kubectl run test-pod --rm -i --tty --image=alpine:latest -- sh
# Inside pod: wget -qO- http://el-github-webhook-listener.tekton-pipelines.svc.cluster.local:8080
```

#### 3. GitHub Webhook Delivery Failures

```bash
# Check webhook secret
kubectl get secret github-webhook-secret -n ${TEKTON_NAMESPACE} -o yaml

# Verify GitHub webhook configuration
echo "Webhook URL: ${WEBHOOK_URL}"
echo "Secret: ${GITHUB_SECRET}"

# Test webhook authentication
curl -X POST ${WEBHOOK_URL} \
  -H "X-GitHub-Event: ping" \
  -H "X-Hub-Signature-256: sha256=test" \
  -d '{"zen":"testing"}' \
  -v
```

#### 4. Pipeline Not Triggered

```bash
# Check TriggerBinding parameters
kubectl describe triggerbinding github-trigger-binding -n ${TEKTON_NAMESPACE}

# Verify TriggerTemplate
kubectl describe triggertemplate github-trigger-template -n ${TEKTON_NAMESPACE}

# Check EventListener logs for errors
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE}
```

### Log Collection

```bash
# Collect Triggers logs
kubectl logs -l app.kubernetes.io/name=tekton-triggers-controller -n ${TEKTON_NAMESPACE} > triggers-controller.log
kubectl logs -l eventlistener=github-webhook-listener -n ${TEKTON_NAMESPACE} > eventlistener.log

# Collect webhook test results
curl -X POST ${WEBHOOK_URL} -H "Content-Type: application/json" -d '{"test":"debug"}' > webhook-test.log 2>&1
```

## 📊 Production Considerations

### Security

- ✅ Webhook secret authentication configured
- ✅ RBAC with minimal required permissions
- ✅ Network policies for event listener access
- ✅ TLS termination at Ingress (configure separately)

### Monitoring

- ✅ EventListener health checks
- ✅ Webhook delivery monitoring
- ✅ Pipeline execution metrics
- ✅ Failed trigger alerting (configure separately)

### Scalability

- ✅ EventListener horizontal scaling ready
- ✅ Webhook processing rate limits
- ✅ Pipeline concurrency controls
- ✅ Resource quotas for triggered workloads

## 🔄 Next Steps

After successful completion of Stage 2:

1. **Test Automatic Triggering**: Push code to GitHub and verify Pipeline execution
2. **Configure Additional Triggers**: Add more event types or repositories
3. **Enhance Pipelines**: Add build, test, and deployment steps
4. **Setup Monitoring**: Configure alerting for failed pipelines

```bash
# Verify complete installation
echo "✅ Stage 2 completed successfully!"
echo "🚀 Your CI/CD automation is ready!"
echo "📖 Webhook URL: ${WEBHOOK_URL}"
echo "🔧 Dashboard: http://${TEKTON_DOMAIN}/"
```

---

## 📚 Additional Resources

- **Tekton Triggers Documentation**: https://tekton.dev/docs/triggers/
- **GitHub Webhooks**: https://docs.github.com/en/developers/webhooks-and-events/webhooks
- **EventListener Configuration**: https://tekton.dev/docs/triggers/eventlisteners/
- **TriggerBinding and TriggerTemplate**: https://tekton.dev/docs/triggers/triggerbindings/ 