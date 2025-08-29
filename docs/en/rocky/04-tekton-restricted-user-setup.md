# Tekton User Permissions and Security Configuration Guide

This guide provides detailed instructions for configuring appropriate user permissions, ServiceAccounts, and security policies for Tekton to ensure security and controllability in production environments.

## 🎯 Configuration Planning

### Permission Model Design
- **Administrator Permissions**: Complete cluster-level Tekton resource management
- **Developer Permissions**: Namespace-level Pipeline creation and execution
- **Restricted User Permissions**: View-only access to PipelineRun status
- **CI/CD Bot Permissions**: Automation system dedicated permissions

### Security Architecture
```
Tekton Permission Security Architecture
├── Cluster-level Permissions (Cluster Administrator)
│   ├── ClusterRole: tekton-admin
│   └── ClusterRoleBinding: tekton-admin-binding
├── Namespace-level Permissions (Development Team)
│   ├── Role: tekton-developer
│   └── RoleBinding: tekton-dev-binding
├── EventListener Permissions (Triggers System)
│   ├── ClusterRole: tekton-triggers-cluster
│   └── ServiceAccount: tekton-triggers-sa
└── Restricted View Permissions (Read-only Users)
    ├── Role: tekton-viewer
    └── RoleBinding: tekton-viewer-binding
```

## 🏁 Step 1: Diagnose Current Permission Issues

### Check EventListener Permission Errors
```bash
# View current EventListener status
kubectl get pods -l eventlistener=hello-event-listener
kubectl logs -l eventlistener=hello-event-listener --tail=20
```

**Permission Error Analysis**:
```
Permission insufficient errors:
- cannot list resource "interceptors" in API group "triggers.tekton.dev"
- cannot list resource "clustertriggerbindings" in API group "triggers.tekton.dev"  
- cannot list resource "clusterinterceptors" in API group "triggers.tekton.dev"
```

**Root Cause**: ServiceAccount `tekton-triggers-sa` lacks necessary cluster-level permissions

## 🔧 Step 2: Fix EventListener Permissions

### Remove Existing Incomplete Permission Configuration
```bash
# Delete existing ClusterRole and ClusterRoleBinding
kubectl delete clusterrole tekton-triggers-clusterrole
kubectl delete clusterrolebinding tekton-triggers-binding

# Confirm deletion
kubectl get clusterrole | grep tekton-triggers
kubectl get clusterrolebinding | grep tekton-triggers
```

### Create Complete EventListener Permissions
```bash
# Create complete Triggers ClusterRole
cat <<EOF | kubectl apply -f -
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
EOF
```

### Bind Permissions to ServiceAccount
```bash
# Create ClusterRoleBinding
cat <<EOF | kubectl apply -f -
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

### Verify Permission Fix
```bash
# Restart EventListener Pod to apply new permissions
kubectl delete pod -l eventlistener=hello-event-listener

# Wait for Pod recreation
kubectl wait --for=condition=ready pod -l eventlistener=hello-event-listener --timeout=120s

# Check new Pod status and logs
kubectl get pods -l eventlistener=hello-event-listener
kubectl logs -l eventlistener=hello-event-listener --tail=10
```

**Permission Fix Verification Results**:
```
# EventListener Pod status
NAME                                      READY   STATUS    RESTARTS   AGE
el-hello-event-listener-c5f79b595-nx59d   1/1     Running   0          5m28s

# EventListener service status
NAME                      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
el-hello-event-listener   ClusterIP   10.96.149.58   <none>        8080/TCP,9000/TCP   12m

# EventListener status
NAME                   ADDRESS                                                         AVAILABLE   READY
hello-event-listener   http://el-hello-event-listener.default.svc.cluster.local:8080   True        True
```

- ✅ EventListener Pod running normally, no permission errors
- ✅ ClusterRole `tekton-triggers-eventlistener-roles` created successfully
- ✅ ClusterRoleBinding `tekton-triggers-eventlistener-binding` bound successfully
- ✅ ServiceAccount `tekton-triggers-sa` has sufficient permissions

## 🧪 Step 3: Functionality Verification Testing

### Test EventListener Permissions are Sufficient
```bash
# Test webhook endpoint functionality
curl -X POST http://localhost:30088 \
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

# Check if PipelineRun is automatically created
kubectl get pipelinerun

# View Pipeline execution logs
kubectl logs -l tekton.dev/pipelineRun=$(kubectl get pipelinerun -o name | head -1 | cut -d'/' -f2)
```

**Functionality Verification Test Results**:
```
# Webhook response
{"eventListener":"hello-event-listener","namespace":"default","eventListenerUID":"e19a8483-e1c6-4796-867c-0bed0f84a583","eventID":"c4d5dd48-9599-447e-aece-00095adf263c"}

# PipelineRun automatic creation
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

- ✅ EventListener permissions sufficient, normally handles webhook requests
- ✅ TriggerBinding correctly extracts parameters
- ✅ TriggerTemplate successfully creates PipelineRun
- ✅ Pipeline execution completed successfully

## 👨‍💼 Step 4: Optional - Create Administrator Permissions

### Create Tekton Administrator ClusterRole
```bash
# Create complete Tekton management permissions
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-admin
rules:
# Complete Tekton resource management permissions
- apiGroups: ["tekton.dev"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["*"] 
  verbs: ["*"]
# Monitoring and debugging permissions
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
```

### Add Administrator Permissions for Current User
```bash
# Get current user information
CURRENT_USER=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.user}')

# Create administrator binding
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-admin-binding
subjects:
- kind: User
  name: $CURRENT_USER
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: tekton-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Added Tekton administrator permissions for user $CURRENT_USER"
```

## 👨‍💻 Step 5: Optional - Create Developer Permissions

### Create Namespace-level Developer Permissions
```bash
# Create developer Role (namespace level)
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: tekton-developer
rules:
# Pipeline development and execution permissions
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "tasks", "pipelineruns", "taskruns"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["triggerbindings", "triggertemplates", "eventlisteners", "triggers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# Basic resource permissions
- apiGroups: [""]
  resources: ["configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
EOF
```

### Create Developer ServiceAccount
```bash
# Create developer ServiceAccount
kubectl create serviceaccount tekton-developer-sa

# Bind developer permissions
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-developer-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: tekton-developer-sa
  namespace: default
roleRef:
  kind: Role
  name: tekton-developer
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 👀 Step 6: Optional - Create Read-only View Permissions

### Create Viewer Permissions
```bash
# Create read-only view Role
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: tekton-viewer
rules:
# Read-only view permissions
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "tasks", "pipelineruns", "taskruns"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["triggers.tekton.dev"]
  resources: ["triggerbindings", "triggertemplates", "eventlisteners", "triggers"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/log", "configmaps"]
  verbs: ["get", "list", "watch"]
EOF
```

### Create Viewer ServiceAccount
```bash
# Create viewer ServiceAccount
kubectl create serviceaccount tekton-viewer-sa

# Bind viewer permissions
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-viewer-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: tekton-viewer-sa
  namespace: default
roleRef:
  kind: Role
  name: tekton-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 🤖 Step 7: Optional - Create CI/CD Bot Permissions

### Create Bot Dedicated Permissions
```bash
# Create CI/CD bot ClusterRole
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-cicd-bot
rules:
# Pipeline trigger and monitoring permissions
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "taskruns"]
  verbs: ["create", "get", "list", "watch", "update", "patch"]
- apiGroups: ["tekton.dev"] 
  resources: ["pipelines", "tasks"]
  verbs: ["get", "list", "watch"]
# Webhook trigger permissions
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggers"]
  verbs: ["get", "list", "watch"]
# Basic resource permissions
- apiGroups: [""]
  resources: ["pods", "pods/log", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list"]
EOF
```

### Create Bot ServiceAccount and Token
```bash
# Create CI/CD bot ServiceAccount
kubectl create serviceaccount tekton-cicd-bot-sa

# Bind bot permissions
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-cicd-bot-binding
subjects:
- kind: ServiceAccount
  name: tekton-cicd-bot-sa
  namespace: default
roleRef:
  kind: ClusterRole
  name: tekton-cicd-bot
  apiGroup: rbac.authorization.k8s.io
EOF

# Create persistent Token (Kubernetes 1.24+)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tekton-cicd-bot-token
  namespace: default
  annotations:
    kubernetes.io/service-account.name: tekton-cicd-bot-sa
type: kubernetes.io/service-account-token
EOF
```

## 🔐 Step 8: Optional - Security Policy Configuration

### Configure NetworkPolicy (Optional)
```bash
# Create Tekton network access policy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tekton-network-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: tekton-pipelines
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: tekton-pipelines
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to: []
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
EOF
```

### Configure PodSecurityPolicy (Optional)
```bash
# Create Tekton Pod security policy
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: tekton-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
EOF
```

## 🧪 Step 9: Optional - Permission Verification Testing

### Test EventListener Permissions
```bash
# Check if EventListener is running normally
kubectl get pods -l eventlistener=hello-event-listener
kubectl get eventlistener hello-event-listener

# Test webhook endpoint
curl -X POST http://localhost:30088 \
  -H "Content-Type: application/json" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/test/repo.git",
      "name": "test-repo"
    },
    "head_commit": {
      "id": "abc123"
    },
    "pusher": {
      "name": "test-user"
    }
  }'

# Check if PipelineRun was automatically created
kubectl get pipelinerun
```

### Test Different Permission Levels
```bash
# Test developer permissions
kubectl auth can-i create pipelineruns --as=system:serviceaccount:default:tekton-developer-sa
kubectl auth can-i delete pipelineruns --as=system:serviceaccount:default:tekton-developer-sa

# Test viewer permissions
kubectl auth can-i get pipelineruns --as=system:serviceaccount:default:tekton-viewer-sa
kubectl auth can-i create pipelineruns --as=system:serviceaccount:default:tekton-viewer-sa

# Test bot permissions
kubectl auth can-i create pipelineruns --as=system:serviceaccount:default:tekton-cicd-bot-sa
kubectl auth can-i delete pipelines --as=system:serviceaccount:default:tekton-cicd-bot-sa
```

## 📊 Step 10: Optional - Get Access Credentials

### Get ServiceAccount Tokens
```bash
# Get developer Token
DEV_TOKEN=$(kubectl get secret $(kubectl get serviceaccount tekton-developer-sa -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 --decode)

# Get viewer Token
VIEWER_TOKEN=$(kubectl get secret $(kubectl get serviceaccount tekton-viewer-sa -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 --decode)

# Get bot Token
BOT_TOKEN=$(kubectl get secret tekton-cicd-bot-token -o jsonpath='{.data.token}' | base64 --decode)

echo "Developer Token: $DEV_TOKEN"
echo "Viewer Token: $VIEWER_TOKEN" 
echo "Bot Token: $BOT_TOKEN"
```

### Create kubeconfig Files
```bash
# Create separate kubeconfig for developer
kubectl config set-cluster tekton-cluster --server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}') --certificate-authority-data=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}') --kubeconfig=tekton-developer.kubeconfig

kubectl config set-credentials tekton-developer --token=$DEV_TOKEN --kubeconfig=tekton-developer.kubeconfig

kubectl config set-context tekton-developer-context --cluster=tekton-cluster --user=tekton-developer --namespace=default --kubeconfig=tekton-developer.kubeconfig

kubectl config use-context tekton-developer-context --kubeconfig=tekton-developer.kubeconfig

echo "Developer kubeconfig file: tekton-developer.kubeconfig"
```

## 📋 Permission Configuration Results Summary

### ✅ Actually Completed Permission Configuration
1. **EventListener Permission Fix**: Resolved Triggers system permission issues
2. **Functionality Verification**: Confirmed webhook and Pipeline execution working normally
3. **Optional Permission Configuration**: Provided permission templates for administrator, developer and other roles

### 🔐 **Actually Configured Permission Summary**

| Component | ServiceAccount | Permission Scope | Status |
|-----------|----------------|------------------|--------|
| EventListener | tekton-triggers-sa | Cluster level | ✅ Configured |
| Triggers Controller | System auto-created | Cluster level | ✅ Configured |
| Pipelines Controller | System auto-created | Cluster level | ✅ Configured |
| Dashboard | System auto-created | Cluster level | ✅ Configured |

**Core Issues Resolved**:
- ✅ EventListener startup failure due to insufficient permissions
- ✅ CA certificate errors due to missing ClusterInterceptor
- ✅ Complete workflow verification of webhook triggering Pipeline

### 🎯 Production Environment Security Configuration
This permission configuration is optimized for production environments:
- **Principle of Least Privilege**: Each role gets only necessary permissions
- **Permission Isolation**: Complete isolation between different user types
- **Security Audit**: All permission changes are traceable
- **Token Management**: Independent access credential management
- **Network Policy**: Optional network access control

## 🚀 Next Steps

After completing permission configuration, you can continue with:
1. [GPU Pipeline Deployment](07-gpu-pipeline-deployment.md)
2. [Advanced Pipeline Configuration](08-advanced-pipeline-configuration.md)
3. [Monitoring and Logging Setup](09-monitoring-logging-setup.md)

## 🎉 Summary

Successfully completed the diagnosis and fix of Tekton permission issues! Now you have:

**🔧 Fixed EventListener**: Complete permissions, working normally  
**✅ Verified Webhook Functionality**: Automatic Pipeline execution triggering  
**📚 Optional Permission Configuration**: Configure different role permissions as needed  

Core issues resolved, Tekton Triggers system running normally!
