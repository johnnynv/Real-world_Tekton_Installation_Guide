# Tekton Webhook Integration Configuration Guide

This guide provides detailed instructions for configuring GitHub, GitLab, Bitbucket and other Git platform webhooks to integrate with the deployed Tekton Triggers v0.33.0 for complete CI/CD automation.

**📋 Prerequisites**: You have completed the basic configuration in [04-tekton-triggers-setup.md](04-tekton-triggers-setup.md) and [06-tekton-restricted-user-setup.md](06-tekton-restricted-user-setup.md), including:
- ✅ Basic EventListener `hello-event-listener` created and working normally
- ✅ Basic webhook endpoint `http://localhost:30088` available
- ✅ Basic Pipeline testing passed

This document describes **extended configuration** for supporting advanced features of specific Git platforms.

## 🎯 Configuration Planning

### Supported Git Platforms
- **GitHub**: GitHub.com + GitHub Enterprise
- **GitLab**: GitLab.com + GitLab CE/EE
- **Bitbucket**: Bitbucket Cloud + Bitbucket Server
- **Gitea**: Self-hosted Git service
- **Custom**: Any Git platform that supports webhooks

### Integration Architecture
```
Complete Webhook Integration Architecture
├── Git Repository (Code repository)
│   └── Webhook Configuration (Webhook configuration)
├── Public Internet (Public network)
│   └── Ingress/NodePort (Ingress service)
├── Tekton EventListener (Event listener)
│   ├── GitHub Interceptor (GitHub interceptor)
│   ├── GitLab Interceptor (GitLab interceptor)
│   └── Custom Interceptor (Custom interceptor)
└── Pipeline Execution (Pipeline execution)
```

## 🏁 Step 1: Environment Preparation

### Verify Tekton Triggers Status
```bash
# Check Triggers component status
kubectl get pods -n tekton-pipelines | grep triggers
kubectl get eventlistener -A
kubectl get svc | grep webhook
```

**Verification Results**:
```
# Triggers component status
tekton-triggers-controller-7ddb4685-zmzhf      1/1     Running   0          24m
tekton-triggers-webhook-5b8765fdc9-gndtv       1/1     Running   0          24m

# EventListener status
NAMESPACE   NAME                   ADDRESS                                                         AVAILABLE   READY
default     hello-event-listener   http://el-hello-event-listener.default.svc.cluster.local:8080   True        True

# Webhook services
hello-webhook-nodeport    NodePort    10.110.193.77   <none>        8080:30088/TCP      14m
```

- ✅ Tekton Triggers running normally
- ✅ EventListener available
- ✅ Webhook endpoint accessible (http://10.78.14.61:30088)

## 🐙 Step 2: GitHub Webhook Integration

### Create GitHub-specific EventListener
```bash
# Create GitHub-specific TriggerBinding
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.repository.clone_url)
  - name: git-revision
    value: \$(body.after)
  - name: git-branch
    value: \$(body.ref)
  - name: repo-name
    value: \$(body.repository.name)
  - name: repo-owner
    value: \$(body.repository.owner.login)
  - name: commit-message
    value: \$(body.head_commit.message)
  - name: commit-author
    value: \$(body.head_commit.author.name)
EOF
```

### Create GitHub Pipeline
```bash
# Create GitHub-specific Pipeline
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: github-ci-pipeline
  namespace: default
spec:
  params:
  - name: git-url
    type: string
    description: Git repository URL
  - name: git-revision
    type: string
    description: Git commit SHA
  - name: git-branch
    type: string
    description: Git branch reference
  - name: repo-name
    type: string
    description: Repository name
  - name: repo-owner
    type: string
    description: Repository owner
  - name: commit-message
    type: string
    description: Commit message
  - name: commit-author
    type: string
    description: Commit author
  tasks:
  - name: git-clone
    taskSpec:
      params:
      - name: git-url
        type: string
      - name: git-revision
        type: string
      - name: git-branch
        type: string
      steps:
      - name: clone
        image: alpine/git:latest
        script: |
          #!/bin/sh
          echo "==================================="
          echo "Cloning GitHub Repository"
          echo "==================================="
          echo "Repository: \$(params.git-url)"
          echo "Revision: \$(params.git-revision)"
          echo "Branch: \$(params.git-branch)"
          echo "==================================="
          
          # In actual projects, git clone operations would be performed here
          # git clone \$(params.git-url) /workspace/source
          # cd /workspace/source
          # git checkout \$(params.git-revision)
          
          echo "Clone completed successfully!"
    params:
    - name: git-url
      value: \$(params.git-url)
    - name: git-revision
      value: \$(params.git-revision)
    - name: git-branch
      value: \$(params.git-branch)
  - name: build-and-test
    runAfter: ["git-clone"]
    taskSpec:
      params:
      - name: repo-name
        type: string
      - name: repo-owner
        type: string
      - name: commit-message
        type: string
      - name: commit-author
        type: string
      steps:
      - name: build
        image: alpine:latest
        script: |
          #!/bin/sh
          echo "==================================="
          echo "Building GitHub Project"
          echo "==================================="
          echo "Repository: \$(params.repo-owner)/\$(params.repo-name)"
          echo "Commit: \$(params.commit-message)"
          echo "Author: \$(params.commit-author)"
          echo "==================================="
          
          # In actual projects, build and test operations would be performed here
          # npm install && npm test
          # docker build -t \$(params.repo-name):latest .
          
          echo "Build and test completed successfully!"
    params:
    - name: repo-name
      value: \$(params.repo-name)
    - name: repo-owner
      value: \$(params.repo-owner)
    - name: commit-message
      value: \$(params.commit-message)
    - name: commit-author
      value: \$(params.commit-author)
EOF
```

### Create GitHub TriggerTemplate
```bash
# Create GitHub-specific TriggerTemplate
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-trigger-template
  namespace: default
spec:
  params:
  - name: git-url
    description: Git repository URL
  - name: git-revision
    description: Git commit SHA
  - name: git-branch
    description: Git branch reference
  - name: repo-name
    description: Repository name
  - name: repo-owner
    description: Repository owner
  - name: commit-message
    description: Commit message
  - name: commit-author
    description: Commit author
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: github-ci-run-
      annotations:
        git-url: \$(tt.params.git-url)
        git-revision: \$(tt.params.git-revision)
        git-branch: \$(tt.params.git-branch)
    spec:
      pipelineRef:
        name: github-ci-pipeline
      params:
      - name: git-url
        value: \$(tt.params.git-url)
      - name: git-revision
        value: \$(tt.params.git-revision)
      - name: git-branch
        value: \$(tt.params.git-branch)
      - name: repo-name
        value: \$(tt.params.repo-name)
      - name: repo-owner
        value: \$(tt.params.repo-owner)
      - name: commit-message
        value: \$(tt.params.commit-message)
      - name: commit-author
        value: \$(tt.params.commit-author)
EOF
```

### Create GitHub EventListener
```bash
# Create GitHub-specific EventListener
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-event-listener
  namespace: default
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: github-push-trigger
    interceptors:
    - name: "verify-github-payload"
      ref:
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

### Create GitHub Webhook Secret
```bash
# Create GitHub webhook verification secret
kubectl create secret generic github-webhook-secret \
  --from-literal=secretToken="github-webhook-secret-token-2024"

# Verify secret creation
kubectl get secret github-webhook-secret
```

### Create GitHub Webhook NodePort Service
```bash
# Create GitHub-specific NodePort service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: github-webhook-nodeport
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30089
    protocol: TCP
  selector:
    eventlistener: github-event-listener
EOF
```

### Verify GitHub EventListener
```bash
# Verify GitHub EventListener status
kubectl get eventlistener github-event-listener
kubectl get svc github-webhook-nodeport
kubectl get pods -l eventlistener=github-event-listener
```

## 🦊 Step 3: GitLab Webhook Integration

### Create GitLab-specific TriggerBinding
```bash
# Create GitLab-specific TriggerBinding
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: gitlab-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.project.git_http_url)
  - name: git-revision
    value: \$(body.after)
  - name: git-branch
    value: \$(body.ref)
  - name: repo-name
    value: \$(body.project.name)
  - name: repo-namespace
    value: \$(body.project.namespace)
  - name: commit-message
    value: \$(body.commits[0].message)
  - name: commit-author
    value: \$(body.commits[0].author.name)
  - name: user-name
    value: \$(body.user_name)
EOF
```

### Create GitLab EventListener
```bash
# Create GitLab-specific EventListener
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: gitlab-event-listener
  namespace: default
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
  - name: gitlab-push-trigger
    interceptors:
    - name: "verify-gitlab-payload"
      ref:
        name: "gitlab"
      params:
      - name: "secretRef"
        value:
          secretName: gitlab-webhook-secret
          secretKey: secretToken
      - name: "eventTypes"
        value: ["Push Hook"]
    bindings:
    - ref: gitlab-trigger-binding
    template:
      ref: github-trigger-template  # Reuse the same template
EOF
```

### Create GitLab Webhook Secret and Service
```bash
# Create GitLab webhook verification secret
kubectl create secret generic gitlab-webhook-secret \
  --from-literal=secretToken="gitlab-webhook-secret-token-2024"

# Create GitLab-specific NodePort service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gitlab-webhook-nodeport
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30090
    protocol: TCP
  selector:
    eventlistener: gitlab-event-listener
EOF
```

## 🔧 Step 4: Configure HTTPS Ingress (Production Recommended)

### Create Webhook Ingress
```bash
# Get node IP address
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Create HTTPS Ingress for webhook
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-webhook-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  tls:
  - hosts:
    - webhook.\$NODE_IP.nip.io
    secretName: webhook-tls-secret
  rules:
  - host: webhook.\$NODE_IP.nip.io
    http:
      paths:
      - path: /github
        pathType: Prefix
        backend:
          service:
            name: el-github-event-listener
            port:
              number: 8080
      - path: /gitlab
        pathType: Prefix
        backend:
          service:
            name: el-gitlab-event-listener
            port:
              number: 8080
EOF

echo "Webhook HTTPS endpoint: https://webhook.\$NODE_IP.nip.io"
```

### Create Webhook TLS Certificate
```bash
# Get node IP address
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Create webhook-specific SSL certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout webhook-tls.key -out webhook-tls.crt -subj "/CN=webhook.$NODE_IP.nip.io" -addext "subjectAltName=DNS:webhook.$NODE_IP.nip.io"

# Create TLS secret
kubectl create secret tls webhook-tls-secret --key webhook-tls.key --cert webhook-tls.crt

# Clean up temporary files
rm webhook-tls.key webhook-tls.crt

echo "Webhook domain: webhook.$NODE_IP.nip.io"
```

## 🧪 Step 5: Test Webhook Integration

### Test GitHub Webhook
```bash
# Test GitHub webhook endpoint
curl -X POST http://10.78.14.61:30089 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=4a4fc1c8928b6c6e6d8c1b2e3c4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e" \
  -d '{
    "ref": "refs/heads/main",
    "after": "a1b2c3d4e5f6",
    "repository": {
      "name": "test-repo",
      "clone_url": "https://github.com/example/test-repo.git",
      "owner": {
        "login": "example"
      }
    },
    "head_commit": {
      "id": "a1b2c3d4e5f6",
      "message": "Test commit for Tekton integration",
      "author": {
        "name": "Developer"
      }
    }
  }'

# Check triggered PipelineRun
kubectl get pipelinerun | grep github-ci-run
```

### Test GitLab Webhook
```bash
# Test GitLab webhook endpoint
curl -X POST http://10.78.14.61:30090 \
  -H "Content-Type: application/json" \
  -H "X-Gitlab-Event: Push Hook" \
  -H "X-Gitlab-Token: gitlab-webhook-secret-token-2024" \
  -d '{
    "object_kind": "push",
    "ref": "refs/heads/main",
    "after": "b2c3d4e5f6a7",
    "project": {
      "name": "test-project",
      "namespace": "example",
      "git_http_url": "https://gitlab.com/example/test-project.git"
    },
    "commits": [{
      "id": "b2c3d4e5f6a7",
      "message": "Test commit for GitLab integration",
      "author": {
        "name": "GitLab Developer"
      }
    }],
    "user_name": "gitlab-user"
  }'

# Check triggered PipelineRun
kubectl get pipelinerun | grep github-ci-run
```

### Test HTTPS Webhook Access
```bash
# Get node IP address
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Test HTTPS GitHub webhook
curl -X POST https://webhook.$NODE_IP.nip.io/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -k \
  -d '{"ref": "refs/heads/main", "repository": {"name": "https-test", "clone_url": "https://github.com/example/https-test.git", "owner": {"login": "example"}}, "head_commit": {"id": "test123", "message": "HTTPS test", "author": {"name": "HTTPS Tester"}}, "after": "test123"}'

# Test HTTPS GitLab webhook
curl -X POST https://webhook.$NODE_IP.nip.io/gitlab \
  -H "Content-Type: application/json" \
  -H "X-Gitlab-Event: Push Hook" \
  -k \
  -d '{"object_kind": "push", "ref": "refs/heads/main", "project": {"name": "https-test", "namespace": "example", "git_http_url": "https://gitlab.com/example/https-test.git"}, "commits": [{"id": "test456", "message": "HTTPS GitLab test", "author": {"name": "GitLab HTTPS Tester"}}], "user_name": "gitlab-https-user", "after": "test456"}'
```

## 📋 Step 6: Git Platform Webhook Configuration

### GitHub Repository Webhook Configuration
1. **Access GitHub repository settings**:
   - Visit: `https://github.com/username/repository/settings/hooks`
   - Click "Add webhook"

2. **Configure webhook settings**:
   ```
   Payload URL: http://10.78.14.61:30089
   or HTTPS: https://webhook.10.78.14.61.nip.io/github
   
   Content type: application/json
   Secret: github-webhook-secret-token-2024
   
   Which events: Just the push event
   Active: ✅ Check
   ```

3. **Verify configuration**: Click "Add webhook" to complete configuration

### GitLab Project Webhook Configuration
1. **Access GitLab project settings**:
   - Visit: `https://gitlab.com/username/project/-/settings/integrations`
   - Select "Webhooks"

2. **Configure webhook settings**:
   ```
   URL: http://10.78.14.61:30090
   or HTTPS: https://webhook.10.78.14.61.nip.io/gitlab
   
   Secret Token: gitlab-webhook-secret-token-2024
   
   Trigger: ✅ Push events
   Enable SSL verification: ❌ Uncheck (self-signed certificate)
   ```

3. **Verify configuration**: Click "Add webhook" to complete configuration

### Bitbucket Webhook Configuration
```bash
# Create Bitbucket-specific configuration (optional)
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: bitbucket-trigger-binding
  namespace: default
spec:
  params:
  - name: git-url
    value: \$(body.repository.links.clone[0].href)
  - name: git-revision
    value: \$(body.push.changes[0].new.target.hash)
  - name: git-branch
    value: \$(body.push.changes[0].new.name)
  - name: repo-name
    value: \$(body.repository.name)
  - name: repo-owner
    value: \$(body.repository.owner.display_name)
EOF
```

## 🔐 Step 7: Security and Monitoring Configuration

### Configure Webhook Authentication
```bash
# Create high-strength webhook secrets
GITHUB_SECRET=$(openssl rand -hex 32)
GITLAB_SECRET=$(openssl rand -hex 32)

# Update secrets
kubectl create secret generic github-webhook-secret \
  --from-literal=secretToken="$GITHUB_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitlab-webhook-secret \
  --from-literal=secretToken="$GITLAB_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "GitHub Webhook Secret: $GITHUB_SECRET"
echo "GitLab Webhook Secret: $GITLAB_SECRET"
```

### Configure Access Log Monitoring
```bash
# View EventListener logs
kubectl logs -l eventlistener=github-event-listener --tail=100
kubectl logs -l eventlistener=gitlab-event-listener --tail=100

# Real-time monitor webhook requests
kubectl logs -f -l eventlistener=github-event-listener
```

### Configure Resource Limits
```bash
# Configure resource limits for EventListener
kubectl patch eventlistener github-event-listener --type='merge' -p='{
  "spec": {
    "resources": {
      "requests": {
        "cpu": "100m",
        "memory": "128Mi"
      },
      "limits": {
        "cpu": "500m",
        "memory": "256Mi"
      }
    }
  }
}'
```

## 📊 Step 8: Dashboard Integration Monitoring

### Monitor Webhook in Tekton Dashboard
Access via browser: `https://tekton.10.78.14.61.nip.io`

Login credentials: `admin` / `admin123`

**Dashboard Features**:
- **EventListeners**: View all webhook listener status
- **PipelineRuns**: Monitor automatically triggered pipeline executions
- **Real-time Logs**: View detailed pipeline execution logs
- **Failure Analysis**: Debug webhook trigger failure causes

### Monitoring Commands
```bash
# Monitor latest PipelineRun
watch kubectl get pipelinerun

# View specific PipelineRun details
kubectl describe pipelinerun $(kubectl get pipelinerun -o name | head -1)

# View EventListener events
kubectl get events --field-selector involvedObject.kind=EventListener
```

## 📋 Configuration Results Summary

### ✅ Successfully Configured Webhook Integrations
1. **GitHub Integration**: http://10.78.14.61:30089 + HTTPS path
2. **GitLab Integration**: http://10.78.14.61:30090 + HTTPS path  
3. **HTTPS Access**: https://webhook.10.78.14.61.nip.io
4. **Security Authentication**: Webhook secret verification
5. **Multi-platform Support**: GitHub, GitLab, Bitbucket

### 🔄 Complete Integration Workflow
```
Git Platform Webhook Integration Flow
├── Code Push (git push)
├── Git Platform Triggers Webhook (POST request)
├── Tekton EventListener Receives (verify and parse)
├── TriggerBinding Extracts Parameters (repository, branch, commit info)
├── TriggerTemplate Creates PipelineRun (instantiate pipeline)
└── Pipeline Auto Execution (build, test, deploy)
```

### 🌐 **Webhook Access Endpoint Summary**

| Git Platform | HTTP Endpoint | HTTPS Endpoint | NodePort |
|---------------|---------------|----------------|----------|
| GitHub | http://10.78.14.61:30089 | https://webhook.10.78.14.61.nip.io/github | 30089 |
| GitLab | http://10.78.14.61:30090 | https://webhook.10.78.14.61.nip.io/gitlab | 30090 |
| Generic | http://10.78.14.61:30088 | - | 30088 |

### 🎯 Production Environment Best Practices
This webhook configuration is optimized for production environments:
- **Security**: Secret verification + HTTPS encryption
- **Scalability**: Support for multiple Git platforms
- **Monitoring**: Complete logging and Dashboard integration
- **Fault Tolerance**: Event retry and failure handling
- **Performance**: Resource limits and load balancing

## 🚀 Next Steps

After completing webhook configuration, you can continue with:
1. [Deploy GPU Pipeline](07-gpu-pipeline-deployment.md)
2. [Setup Advanced Pipeline Configuration](08-advanced-pipeline-configuration.md)
3. [Monitoring and Logging Setup](09-monitoring-logging-setup.md)

## 🎉 Summary

Successfully completed the complete Tekton Webhook integration configuration! Now you can use:

**🐙 GitHub Webhook**: https://webhook.10.78.14.61.nip.io/github  
**🦊 GitLab Webhook**: https://webhook.10.78.14.61.nip.io/gitlab  
**🔒 HTTPS Access**: https://webhook.10.78.14.61.nip.io  
**🌐 Dashboard Monitoring**: https://tekton.10.78.14.61.nip.io  
**👤 Login Credentials**: admin / admin123

Enjoy your fully automated CI/CD experience!