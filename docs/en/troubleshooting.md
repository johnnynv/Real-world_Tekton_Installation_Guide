# Tekton GPU Pipeline Deployment Troubleshooting

This document records issues discovered during deployment and their solutions.

## 📋 Common Issues

### 1. kubectl Command Issues

#### Issue: `kubectl version --short` not supported
**Error Message**:
```
error: unknown flag: --short
See 'kubectl version --help' for usage.
```

**Cause**: Recent kubectl versions have removed the `--short` parameter

**Solution**:
```bash
# Incorrect command
kubectl version --short

# Correct command
kubectl version
```

**Status**: Documentation fixed

---

### 2. Git Clone Safety Handling Issues

#### Issue: Git clone fails on repeated pipeline runs
**Error Message**:
```
fatal: destination path 'source' already exists and is not an empty directory.
```

**Cause**: Residual files from previous pipeline runs exist in workspace

**Solution**: Automatic backup and safety handling mechanism

Our safe git clone implementation includes:
- **Automatic directory backup**: Creates timestamped backup when existing directory detected
- **Retry mechanism**: Auto-retry on clone failure (up to 3 attempts)
- **Rollback capability**: Can automatically restore backup on failure
- **Detailed logging**: Timestamped detailed operation logs

**Safety handling process**:
```bash
# 1. Check if directory exists
if [ -d "${TARGET_DIR}" ]; then
  # 2. Create timestamped backup
  TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
  BACKUP_DIR="${TARGET_DIR}_backup_${TIMESTAMP}"
  mv "${TARGET_DIR}" "${BACKUP_DIR}"
fi

# 3. Execute git clone (with retry)
for attempt in $(seq 1 ${MAX_RETRIES}); do
  if git clone "${REPO_URL}" "${TARGET_DIR}"; then
    break
  fi
  # Clean up failed partial clone
  rm -rf "${TARGET_DIR}"
  sleep $((attempt * 5))  # Exponential backoff
done
```

**Updated Task components**:
1. **gpu-env-preparation-task-fixed.yaml** - Added automatic backup mechanism
2. **pytest-execution-task.yaml** - Safe handling for test repository clone
3. **safe-git-clone-task.yaml** (new) - Independent safe git clone task

**Cleaning backup directories**:
```bash
# Clean backups older than 7 days
find /workspace -name "*_backup_*" -type d -mtime +7 -exec rm -rf {} +
```

**Status**: Fixed and enhanced with safety measures

---

### 3. Environment Cleanup Issues

#### Issue: Existing Tekton components cause deployment conflicts
**Symptoms**:
- Resource already exists errors during installation
- EventListener in CrashLoopBackOff state
- Cannot create new Pipeline resources

**Solution**:
```bash
# Execute complete environment cleanup
chmod +x scripts/cleanup/clean-tekton-environment.sh
./scripts/cleanup/clean-tekton-environment.sh
```

**Verify cleanup completion**:
```bash
# Should have no output
kubectl get namespaces | grep tekton
kubectl get pods --all-namespaces | grep tekton
```

---

### 4. Tekton API Version Issues

#### Issue: resources field position error in Task definition
**Error Message**:
```
error when creating: Task in version "v1" cannot be handled as a Task: strict decoding error: unknown field "spec.steps[0].resources"
```

**Cause**: In Tekton v1 API, resource definitions should use `computeResources`

**Solution**:
```yaml
# Incorrect configuration
spec:
  steps:
  - name: step
    resources:
      limits:
        nvidia.com/gpu: "1"

# Correct configuration
spec:
  steps:
  - name: step
    computeResources:
      limits:
        nvidia.com/gpu: "1"
```

---

### 5. Dynamic Parameter Issues

#### Issue: Resource quantities must match regular expression
**Error Message**:
```
quantities must match the regular expression '^([+-]?[0-9.]+)([eEinumkKMGTP]*[-+]?[0-9]*)$'
```

**Cause**: Tekton doesn't accept dynamic parameters as resource quantity values

**Solution**:
```yaml
# Incorrect configuration
computeResources:
  limits:
    nvidia.com/gpu: $(params.gpu-count)

# Correct configuration
computeResources:
  limits:
    nvidia.com/gpu: "1"
```

---

### 6. YAML Format Issues

#### Issue: Complex multi-line scripts cause YAML parsing errors
**Error Message**:
```
error converting YAML to JSON: yaml: line X: could not find expected ':'
```

**Cause**: Python script block indentation issues

**Solution**:
Simplify complex Python scripts, use simpler shell commands:

```yaml
# Complex Python script (error-prone)
script: |
  python3 << 'EOF'
  import json
  # Complex logic
  EOF

# Simplified shell commands (recommended)
script: |
  #!/bin/bash
  echo "Simple validation"
  grep -q "pattern" file || echo "Not found"
```

---

### 7. Dashboard Access Issues

#### Issue: Dashboard login succeeds but content keeps loading
**Symptoms**:
- Can enter username/password and login
- After login, page is blank or shows continuous loading
- Network requests show 401/403 errors

**Cause**: Dashboard read-only mode or insufficient permissions

**Solution**:
```bash
# Fix dashboard read-only mode
bash scripts/utils/fix-dashboard-readonly.sh

# Verify dashboard status
kubectl get pods -n tekton-pipelines | grep dashboard
kubectl logs -n tekton-pipelines deployment/tekton-dashboard
```

---

### 8. GPU Memory Management Issues

#### Issue: RAPIDS Memory Manager (RMM) initialization failures
**Error Message**:
```
RuntimeError: RMM has not been initialized
```

**Cause**: GPU tasks don't properly initialize RMM before using RAPIDS libraries

**Solution**:
Use init containers with proper RMM initialization:

```yaml
initContainers:
- name: init-rmm
  image: rapidsai/rapidsai:22.12-cuda11.5-runtime-ubuntu20.04-py3.9
  script: |
    #!/bin/bash
    python3 -c "
    import rmm
    rmm.reinitialize(pool_allocator=True, initial_pool_size=1024**3)
    print('RMM initialized successfully')
    "
```

---

### 9. Pipeline Run ID Issues

#### Issue: Pipeline artifacts use generic names instead of run-specific IDs
**Problem**: Artifacts from different pipeline runs overwrite each other

**Solution**: Extract proper pipeline run ID for directory structure:

```bash
# Get Pipeline Run ID using multiple methods for reliability
PIPELINE_RUN_NAME=""
if [ -f "/tekton/run/name" ]; then
  PIPELINE_RUN_NAME=$(cat /tekton/run/name)
elif [ -n "${TEKTON_PIPELINERUN_NAME:-}" ]; then
  PIPELINE_RUN_NAME="$TEKTON_PIPELINERUN_NAME"
fi

# Extract short ID (last 5 characters)
PIPELINE_RUN_ID=$(echo $PIPELINE_RUN_NAME | sed 's/.*-\([a-z0-9]\{5\}\)$/\1/')

# Create dedicated directory structure
RUN_DIR="pipeline-runs/run-${PIPELINE_RUN_ID}"
```

---

### 10. Test Framework Integration Issues

#### Issue: pytest execution fails with missing dependencies
**Error Message**:
```
pytest: error: unrecognized arguments: --cov=./ --cov-report=xml
```

**Cause**: Missing pytest plugins in Poetry environment

**Solution**:
```bash
# Install Poetry and dependencies
poetry install
poetry run pip install pytest-cov pytest-html

# Execute tests with proper plugins
poetry run pytest -m fast --cov=./ --cov-report=xml --junitxml=results.xml
```

---

## 🔧 Verification Commands

### Check Tekton Installation
```bash
# Verify all components
kubectl get pods -n tekton-pipelines
kubectl get pods -n tekton-pipelines-resolvers

# Check dashboard access
curl -k https://tekton.<NODE_IP>.nip.io
```

### Monitor Pipeline Execution
```bash
# Watch pipeline runs
kubectl get pipelinerun -n tekton-pipelines -w

# Check pipeline logs
tkn pipelinerun logs <pipeline-run-name> -f
```

### Validate GPU Access
```bash
# Test GPU availability in cluster
kubectl run gpu-test --rm -it --restart=Never --image=nvidia/cuda:11.5-runtime-ubuntu20.04 -- nvidia-smi
```

## 🚀 Performance Optimization

### Dashboard Performance
- **Resource Limits**: Increase dashboard memory to 512Mi
- **Log Retention**: Limit log retention to reduce storage
- **History Cleanup**: Regularly clean old pipeline runs

### Pipeline Optimization
- **Parallel Execution**: Use `runAfter` dependencies efficiently
- **Resource Sharing**: Reuse workspaces between tasks
- **Image Caching**: Use consistent base images for faster startup

## 📞 Getting Help

1. **Check Logs**: Always start with `kubectl logs` and `tkn pipelinerun logs`
2. **Verify Resources**: Use `kubectl describe` for detailed resource status
3. **Network Issues**: Test connectivity to required external services
4. **GPU Issues**: Verify GPU drivers and NVIDIA runtime installation

---

### 11. Tekton Dashboard Restricted User Permission Configuration Issues (Important Case)

#### Issue: Dashboard login succeeds but permissions not effective
**Symptoms**:
- Can successfully login with user/user123 to Dashboard
- After login, can still see "Create" button and all menu items
- Permission restrictions seem not to be effective

### Complete Diagnosis and Resolution Process

#### Problem 1: Dashboard inaccessible (HTTP 503)
**Error Message**:
```
HTTP 503 Service Temporarily Unavailable
```

**Root Cause**: Basic authentication Secret configuration error
- Secret uses key name `users.htpasswd` 
- Nginx Ingress expects key name `auth`

**Solution**:
```bash
# 1. Extract existing htpasswd content
HTPASSWD_CONTENT=$(kubectl get secret tekton-dashboard-auth -n tekton-pipelines -o jsonpath='{.data.users\.htpasswd}' | base64 -d)

# 2. Delete incorrect Secret
kubectl delete secret tekton-dashboard-auth -n tekton-pipelines

# 3. Recreate correct Secret
kubectl create secret generic tekton-dashboard-auth \
  --from-literal=auth="$HTPASSWD_CONTENT" \
  -n tekton-pipelines

# 4. Verify fix
curl -k -u "user:user123" https://tekton.10.34.2.129.nip.io/
```

#### Problem 2: Dashboard permission configuration error
**Symptoms**: Login succeeds but can see Create button

**Root Cause**: Dashboard ServiceAccount has excessive permissions
- `tekton-dashboard` ServiceAccount bound to high-privilege ClusterRoles
- These ClusterRoles have `[*]` full permissions, not restricted read-only permissions

**Solution**:
```bash
# 1. Delete high-privilege bindings
kubectl delete clusterrolebinding tekton-dashboard-backend-edit
kubectl delete clusterrolebinding tekton-dashboard-pipelines-view  
kubectl delete clusterrolebinding tekton-dashboard-tenant-view
kubectl delete clusterrolebinding tekton-dashboard-triggers-view

# 2. Create restricted permission binding
kubectl create clusterrolebinding tekton-dashboard-restricted \
  --clusterrole=tekton-restricted-viewer \
  --serviceaccount=tekton-pipelines:tekton-dashboard

# 3. Restart Dashboard to apply permissions
kubectl rollout restart deployment tekton-dashboard -n tekton-pipelines
kubectl rollout status deployment tekton-dashboard -n tekton-pipelines
```

#### Problem 3: Dashboard still shows unauthorized menu items
**Symptoms**: Although Create button disappears, can still see "other menus"

**Root Cause Analysis**:
1. **Dashboard read-only mode not enabled**: `--read-only=false` allows UI to display edit functions
2. **ClusterRole permissions too broad**: `tekton-restricted-viewer` still includes permissions for Triggers-related resources

**Complete Solution**:
```bash
# 1. Enable Dashboard read-only mode
kubectl patch deployment tekton-dashboard -n tekton-pipelines --type='json' -p='[
  {
    "op": "replace", 
    "path": "/spec/template/spec/containers/0/args",
    "value": [
      "--default-namespace=",
      "--external-logs=", 
      "--log-format=json",
      "--log-level=info",
      "--logout-url=",
      "--namespaces=",
      "--pipelines-namespace=tekton-pipelines",
      "--port=9097",
      "--read-only=true",
      "--stream-logs=true", 
      "--triggers-namespace=tekton-pipelines"
    ]
  }
]'

# 2. Update ClusterRole to more strict permissions
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-restricted-viewer
  labels:
    app.kubernetes.io/component: dashboard
    app.kubernetes.io/part-of: tekton-dashboard
rules:
# Only allow access to basic Tekton resources
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "pipelineruns", "tasks", "taskruns", "eventlisteners"]
  verbs: ["get", "list", "watch"]
# Basic Kubernetes resources
- apiGroups: [""]
  resources: ["configmaps", "namespaces", "pods", "pods/log"]
  verbs: ["get", "list", "watch"]
EOF

# 3. Restart Dashboard
kubectl rollout restart deployment tekton-dashboard -n tekton-pipelines
kubectl rollout status deployment tekton-dashboard -n tekton-pipelines
```

### Verify Permission Restrictions

**Permission test commands**:
```bash
# Test Dashboard ServiceAccount permissions
kubectl auth can-i list triggers.triggers.tekton.dev --as=system:serviceaccount:tekton-pipelines:tekton-dashboard
# Should return: no

kubectl auth can-i list clustertasks.tekton.dev --as=system:serviceaccount:tekton-pipelines:tekton-dashboard  
# Should return: no
```

### Important Behavior Notes

**✅ Normal Dashboard Behavior**:
- **Static menu display**: All menu items are displayed, this is Tekton Dashboard's design
- **Permission verification on click**: Shows permission errors or empty lists when accessing restricted resources
- **Read-only mode effective**: Does not display Create, Edit, Delete operation buttons

**🧪 User verification steps**:
1. **Refresh browser page** (Ctrl+F5)
2. **Click restricted menu items** to verify permissions:
   - Triggers → Should show permission error
   - ClusterTasks → Should show permission error  
   - CustomRuns → Should show permission error
3. **Confirm allowed menu items** display normally:
   - Pipelines ✅
   - PipelineRuns ✅  
   - Tasks ✅
   - TaskRuns ✅
   - EventListeners ✅

### Key Configuration Files

**Restricted user RBAC configuration** (`examples/config/rbac/rbac-step5-tekton-restricted-user.yaml`):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-restricted-viewer
rules:
- apiGroups: ["tekton.dev"]
  resources: ["pipelines", "pipelineruns", "tasks", "taskruns", "eventlisteners"]
  verbs: ["get", "list", "watch"]
```

**Basic authentication configuration**:
```bash
# Correct Secret format
kubectl create secret generic tekton-dashboard-auth \
  --from-literal=auth="user:$2y$10$..." \
  -n tekton-pipelines
```

### Status

- ✅ **HTTP 503 issue**: Resolved (Secret key correction)
- ✅ **Excessive permissions issue**: Resolved (ClusterRole restriction)  
- ✅ **Menu display issue**: Resolved (read-only mode + permission refinement)
- ✅ **Access verification**: Confirmed permissions work as expected

**Important conclusion**: Tekton Dashboard's menu is statically displayed, permission restrictions take effect at the API access level. This is normal design behavior that ensures UI consistency while implementing effective access control.

---

**Note**: This troubleshooting guide covers real-world issues encountered during production deployments. Each solution has been tested and validated.