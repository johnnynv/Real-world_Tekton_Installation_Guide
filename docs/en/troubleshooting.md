# Tekton Production Environment Deployment Troubleshooting Guide

This document summarizes common issues, root causes, and solutions encountered during the deployment of a production-grade Tekton system, categorized by the two deployment stages.

## 📋 Issue Classification Overview

### Stage 1: Core Infrastructure Issues
1. **Ingress Controller Installation Failures**
2. **Tekton Pipelines Component Startup Abnormalities**
3. **Dashboard Access Issues**
4. **DNS Resolution and Network Connectivity Problems**
5. **Resource Limits and Permission Issues**

### Stage 2: CI/CD Automation Issues
1. **API Version Compatibility Issues**
2. **RBAC Permission Insufficient Issues**
3. **Pod Security Standards Restriction Issues**
4. **EventListener Startup Failures**
5. **GitHub Webhook Connection Failures**
6. **Pipeline Automatic Trigger Failures**

---

## 🏗️ Stage 1: Core Infrastructure Troubleshooting

### 1. Ingress Controller Installation Failures

#### Problem Symptoms
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx
Error: INSTALLATION FAILED: failed to create resource: Internal error occurred: admission webhook failed
```

#### Root Causes
- Helm repository not updated or version conflicts
- Insufficient cluster permissions
- Network policies blocking webhook communication
- Insufficient node resources

#### Solutions

1. **Update Helm Repository and Retry**:
```bash
helm repo update
helm repo list
helm search repo ingress-nginx/ingress-nginx
```

2. **Check Cluster Permissions**:
```bash
kubectl auth can-i create clusterrole
kubectl auth can-i create namespace
```

3. **Verify Node Resources**:
```bash
kubectl describe nodes
kubectl top nodes
```

4. **Clean and Reinstall**:
```bash
helm uninstall ingress-nginx -n ingress-nginx || true
kubectl delete namespace ingress-nginx || true
./scripts/en/cleanup/01-cleanup-tekton-core.sh
./scripts/en/install/01-install-tekton-core.sh
```

---

### 2. Tekton Pipelines Component Startup Abnormalities

#### Problem Symptoms
```bash
kubectl get pods -n tekton-pipelines
NAME                                        READY   STATUS    RESTARTS   AGE
tekton-pipelines-controller-xxx             0/1     Pending   0          5m
tekton-pipelines-webhook-xxx                0/1     Error     3          5m
```

#### Root Causes
- Resource constraints (CPU/Memory insufficient)
- Pod Security Standards too restrictive
- Container image pull failures
- RBAC permission issues

#### Solutions

1. **Check Resource Allocation**:
```bash
kubectl describe pod tekton-pipelines-controller-xxx -n tekton-pipelines
kubectl top pods -n tekton-pipelines
```

2. **Verify Pod Security Configuration**:
```bash
kubectl get namespace tekton-pipelines -o yaml | grep pod-security
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
```

3. **Check Image Pull Status**:
```bash
kubectl describe pod tekton-pipelines-webhook-xxx -n tekton-pipelines
# Check Events section for image pull errors
```

4. **Verify RBAC Permissions**:
```bash
kubectl auth can-i create customresourcedefinitions
kubectl get clusterrole | grep tekton
```

---

### 3. Dashboard Access Issues

#### Problem Symptoms
```bash
curl -I http://tekton.YOUR_NODE_IP.nip.io/
curl: (7) Failed to connect to tekton.YOUR_NODE_IP.nip.io port 80: Connection refused
```

#### Root Causes
- Ingress configuration errors
- DNS resolution issues
- Dashboard service not running
- Network connectivity problems

#### Solutions

1. **Check Dashboard Pod Status**:
```bash
kubectl get pods -l app.kubernetes.io/name=tekton-dashboard -n tekton-pipelines
kubectl logs -l app.kubernetes.io/name=tekton-dashboard -n tekton-pipelines
```

2. **Verify Ingress Configuration**:
```bash
kubectl get ingress -n tekton-pipelines
kubectl describe ingress tekton-dashboard -n tekton-pipelines
```

3. **Test Internal Service Access**:
```bash
kubectl run test-pod --rm -i --tty --image=alpine:latest -- sh
# Inside pod:
wget -qO- http://tekton-dashboard.tekton-pipelines.svc.cluster.local:9097
```

4. **Check Ingress Controller Status**:
```bash
kubectl get pods -n ingress-nginx
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx
```

---

### 4. DNS Resolution and Network Connectivity Problems

#### Problem Symptoms
```bash
nslookup tekton.YOUR_NODE_IP.nip.io
;; connection timed out; no servers could be reached
```

#### Root Causes
- Incorrect NODE_IP configuration
- nip.io service unavailable
- Corporate firewall blocking external DNS
- Network policy restrictions

#### Solutions

1. **Verify NODE_IP Configuration**:
```bash
kubectl get nodes -o wide
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: ${NODE_IP}"
```

2. **Test nip.io Service**:
```bash
nslookup test.${NODE_IP}.nip.io 8.8.8.8
# Should resolve to NODE_IP
```

3. **Use Alternative DNS or Hosts Entry**:
```bash
# Add to /etc/hosts
echo "${NODE_IP} tekton.${NODE_IP}.nip.io" | sudo tee -a /etc/hosts
```

4. **Test Direct IP Access**:
```bash
curl -H "Host: tekton.${NODE_IP}.nip.io" http://${NODE_IP}/
```

---

### 5. Resource Limits and Permission Issues

#### Problem Symptoms
```bash
kubectl describe pod tekton-dashboard-xxx -n tekton-pipelines
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  2m    default-scheduler  0/3 nodes are available: 3 Insufficient memory.
```

#### Root Causes
- Insufficient cluster resources
- Resource quotas blocking deployment
- Pod Security Standards misconfiguration
- RBAC permission issues

#### Solutions

1. **Check Resource Availability**:
```bash
kubectl describe nodes
kubectl top nodes
kubectl get resourcequota -A
```

2. **Adjust Resource Limits**:
```bash
kubectl patch deployment tekton-dashboard -n tekton-pipelines --patch '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "tekton-dashboard",
          "resources": {
            "requests": {"cpu": "50m", "memory": "64Mi"},
            "limits": {"cpu": "200m", "memory": "256Mi"}
          }
        }]
      }
    }
  }
}'
```

3. **Verify Pod Security Settings**:
```bash
kubectl get namespace tekton-pipelines -o yaml | grep pod-security
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=restricted --overwrite
```

---

## 🚀 Stage 2: CI/CD Automation Troubleshooting

### 1. API Version Compatibility Issues

#### Problem Symptoms
```bash
kubectl apply -f eventlistener.yaml
error validating data: ValidationError(EventListener.spec): unknown field "serviceAccountName"
```

#### Root Causes
- API version mismatch between Tekton Triggers and cluster
- Outdated CRD definitions
- Incorrect YAML syntax

#### Solutions

1. **Check Tekton Triggers Version**:
```bash
kubectl get pods -n tekton-pipelines | grep triggers
kubectl get crd eventlisteners.triggers.tekton.dev -o yaml | grep version
```

2. **Update to Compatible API Version**:
```yaml
apiVersion: triggers.tekton.dev/v1beta1  # Use v1beta1 instead of v1alpha1
kind: EventListener
```

3. **Reinstall Tekton Triggers**:
```bash
kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
```

---

### 2. RBAC Permission Insufficient Issues

#### Problem Symptoms
```bash
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines
error creating pipelinerun: pipelineruns.tekton.dev is forbidden: User "system:serviceaccount:tekton-pipelines:tekton-triggers-sa" cannot create resource "pipelineruns"
```

#### Root Causes
- ServiceAccount missing or incorrect
- ClusterRole missing required permissions
- ClusterRoleBinding not properly configured

#### Solutions

1. **Verify ServiceAccount Exists**:
```bash
kubectl get serviceaccount tekton-triggers-sa -n tekton-pipelines
```

2. **Check ClusterRole Permissions**:
```bash
kubectl get clusterrole tekton-triggers-role -o yaml
kubectl auth can-i create pipelinerun --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa
```

3. **Recreate RBAC Resources**:
```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns"]
  verbs: ["create", "get", "list", "watch"]
EOF
```

---

### 3. Pod Security Standards Restriction Issues

#### Problem Symptoms
```bash
kubectl describe pod el-github-webhook-listener-xxx -n tekton-pipelines
Events:
  Warning  FailedCreate  pods "el-github-webhook-listener-xxx" is forbidden: violates PodSecurity "restricted:latest"
```

#### Root Causes
- Pod Security Standards too restrictive for Tekton components
- Security context not properly configured
- Namespace labels misconfigured

#### Solutions

1. **Adjust Pod Security Standards**:
```bash
kubectl label namespace tekton-pipelines pod-security.kubernetes.io/enforce=privileged --overwrite
```

2. **Check Current Security Labels**:
```bash
kubectl get namespace tekton-pipelines -o yaml | grep pod-security
```

3. **Apply Security Context**:
```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
spec:
  resources:
    kubernetesResource:
      spec:
        template:
          spec:
            securityContext:
              runAsNonRoot: true
              runAsUser: 65532
```

---

### 4. EventListener Startup Failures

#### Problem Symptoms
```bash
kubectl get eventlistener -n tekton-pipelines
NAME                     ADDRESS   AVAILABLE   REASON
github-webhook-listener            False       MinimumReplicasUnavailable
```

#### Root Causes
- ServiceAccount missing
- RBAC permissions insufficient
- Resource constraints
- Image pull failures

#### Solutions

1. **Check EventListener Status**:
```bash
kubectl describe eventlistener github-webhook-listener -n tekton-pipelines
```

2. **Verify Dependencies**:
```bash
kubectl get serviceaccount tekton-triggers-sa -n tekton-pipelines
kubectl get secret github-webhook-secret -n tekton-pipelines
```

3. **Check Generated Resources**:
```bash
kubectl get deployment -l eventlistener=github-webhook-listener -n tekton-pipelines
kubectl get service -l eventlistener=github-webhook-listener -n tekton-pipelines
```

4. **Delete and Recreate EventListener**:
```bash
kubectl delete eventlistener github-webhook-listener -n tekton-pipelines
# Recreate with corrected configuration
```

---

### 5. GitHub Webhook Connection Failures

#### Problem Symptoms
- GitHub webhook shows "Failed to connect" or timeout errors
- Webhook deliveries show HTTP 5xx errors
- EventListener not receiving webhook events

#### Root Causes
- Incorrect webhook URL configuration
- Network connectivity issues
- Ingress misconfiguration
- Webhook secret mismatch

#### Solutions

1. **Verify Webhook URL**:
```bash
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Webhook URL: http://tekton.${NODE_IP}.nip.io/webhook"
```

2. **Test Webhook Endpoint**:
```bash
curl -X POST http://tekton.${NODE_IP}.nip.io/webhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen":"testing webhook"}' \
  -v
```

3. **Check Ingress Configuration**:
```bash
kubectl get ingress github-webhook-ingress -n tekton-pipelines -o yaml
kubectl describe ingress github-webhook-ingress -n tekton-pipelines
```

4. **Verify Secret Configuration**:
```bash
kubectl get secret github-webhook-secret -n tekton-pipelines -o yaml
# Ensure secretToken matches GitHub webhook secret
```

---

### 6. Pipeline Automatic Trigger Failures

#### Problem Symptoms
- GitHub webhook deliveries succeed but no PipelineRuns created
- EventListener receives events but doesn't process them
- TriggerBinding parameter extraction fails

#### Root Causes
- TriggerBinding parameter mapping errors
- TriggerTemplate resource template issues
- EventListener trigger configuration problems
- GitHub webhook payload format changes

#### Solutions

1. **Check EventListener Logs**:
```bash
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f
```

2. **Verify TriggerBinding Parameters**:
```bash
kubectl describe triggerbinding github-trigger-binding -n tekton-pipelines
```

3. **Test Parameter Extraction**:
```bash
# Send sample GitHub webhook payload
curl -X POST http://tekton.${NODE_IP}.nip.io/webhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=correct_signature" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/user/repo.git",
      "name": "test-repo"
    },
    "head_commit": {
      "id": "abc123",
      "message": "Test commit",
      "author": {"name": "Test User"}
    }
  }'
```

4. **Check Generated PipelineRuns**:
```bash
kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp
kubectl describe pipelinerun <latest-run> -n tekton-pipelines
```

---

## 🔧 General Troubleshooting Commands

### Log Collection

```bash
# Collect all relevant logs
mkdir -p tekton-logs

# Core components
kubectl logs -l app.kubernetes.io/name=tekton-pipelines-controller -n tekton-pipelines > tekton-logs/pipelines-controller.log
kubectl logs -l app.kubernetes.io/name=tekton-dashboard -n tekton-pipelines > tekton-logs/dashboard.log

# Triggers components
kubectl logs -l app.kubernetes.io/name=tekton-triggers-controller -n tekton-pipelines > tekton-logs/triggers-controller.log
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines > tekton-logs/eventlistener.log

# Ingress Controller
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx > tekton-logs/ingress-nginx.log
```

### Resource Status Check

```bash
# Check all Tekton resources
kubectl get all -n tekton-pipelines
kubectl get eventlistener,triggerbinding,triggertemplate -n tekton-pipelines
kubectl get ingress -n tekton-pipelines

# Check CRDs
kubectl get crd | grep tekton

# Check RBAC
kubectl get clusterrole | grep tekton
kubectl get clusterrolebinding | grep tekton
```

### Network Connectivity Testing

```bash
# Test internal service connectivity
kubectl run test-pod --rm -i --tty --image=alpine:latest -- sh
# Inside pod:
wget -qO- http://tekton-dashboard.tekton-pipelines.svc.cluster.local:9097
wget -qO- http://el-github-webhook-listener.tekton-pipelines.svc.cluster.local:8080

# Test external access
curl -I http://tekton.${NODE_IP}.nip.io/
curl -I http://tekton.${NODE_IP}.nip.io/webhook
```

---

## 🎯 Prevention Best Practices

### Pre-Installation Checklist

1. **Verify Prerequisites**:
```bash
kubectl version --short
helm version --short
kubectl auth can-i create namespace
kubectl auth can-i create clusterrole
```

2. **Check Resource Availability**:
```bash
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

3. **Validate Network Configuration**:
```bash
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
nslookup tekton.${NODE_IP}.nip.io
```

### Post-Installation Verification

1. **Run Verification Script**:
```bash
./scripts/en/utils/verify-installation.sh --stage=all
```

2. **Test End-to-End Functionality**:
```bash
# Create test PipelineRun
kubectl create -f examples/pipelines/hello-world-pipeline-run.yaml

# Test webhook endpoint
curl -X POST http://tekton.${NODE_IP}.nip.io/webhook \
  -H "Content-Type: application/json" \
  -d '{"test":"verification"}'
```

### Monitoring and Alerting

1. **Setup Health Checks**:
```bash
# Monitor critical components
kubectl get pods -n tekton-pipelines --watch
kubectl get eventlistener -n tekton-pipelines --watch
```

2. **Configure Log Monitoring**:
```bash
# Monitor for error patterns
kubectl logs -f -l app.kubernetes.io/name=tekton-pipelines-controller -n tekton-pipelines | grep ERROR
```

---

## 📚 Additional Resources

- **Tekton Documentation**: https://tekton.dev/docs/
- **Kubernetes Troubleshooting**: https://kubernetes.io/docs/tasks/debug/
- **Ingress Nginx Troubleshooting**: https://kubernetes.github.io/ingress-nginx/troubleshooting/
- **Pod Security Standards**: https://kubernetes.io/docs/concepts/security/pod-security-standards/

For issues not covered in this guide, please check the official Tekton documentation or create an issue in the repository. 