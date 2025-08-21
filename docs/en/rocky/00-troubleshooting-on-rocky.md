# Tekton Troubleshooting Guide for Rocky Linux Environment

This guide documents common issues encountered during Tekton installation and configuration in Rocky Linux + Kubernetes environments and their solutions.

## 🚨 Common Issues and Solutions

### Issue 1: Dashboard Access Forbidden Errors

**Symptoms**:
- Some menus in Tekton Dashboard show "Forbidden" errors
- API calls return 403 status codes
- Error message: "User 'system:anonymous' cannot list resource"

**Problem Analysis**:
1. Dashboard configuration has `--read-only=true` parameter limiting write operations
2. Ingress configuration missing HTTP Basic Auth authentication
3. Incomplete RBAC permission configuration

**Solution Steps**:

#### Step 1: Fix Dashboard Configuration
```bash
# Remove read-only restriction
kubectl patch deployment tekton-dashboard -n tekton-pipelines \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/6", "value": "--read-only=false"}]'

# Wait for deployment to complete
kubectl rollout status deployment/tekton-dashboard -n tekton-pipelines
```

#### Step 2: Configure HTTP Basic Auth
```bash
# Add authentication configuration to Dashboard Ingress
kubectl patch ingress tekton-dashboard-ingress -n tekton-pipelines \
  --type='merge' -p='{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/auth-type":"basic","nginx.ingress.kubernetes.io/auth-secret":"tekton-basic-auth","nginx.ingress.kubernetes.io/auth-realm":"Tekton Dashboard Authentication"}}}'
```

#### Step 3: Verify Fix Results
```bash
# Test Dashboard API access
curl -H "Host: tekton.10.78.14.61.nip.io" \
  -u admin:admin123 \
  https://localhost:30443/api/v1/namespaces -k

# Test Tekton API access
curl -H "Host: tekton.10.78.14.61.nip.io" \
  -u admin:admin123 \
  https://localhost:30443/apis/tekton.dev/v1/namespaces/tekton-pipelines/pipelines -k
```

**Expected Results**:
- ✅ Dashboard API returns 200 status code
- ✅ Can normally access namespaces list
- ✅ Tekton resource APIs work normally
- ✅ No more Forbidden errors

### Issue 2: Webhook Domain Access Configuration

**Symptoms**:
- Webhook only accessible via NodePort ports
- Cannot access via *.nip.io domain
- External systems cannot trigger Pipelines

**Solution**:
Webhook has been configured with correct ingress and can be accessed via:
```
http://webhook.10.78.14.61.nip.io
```

**Verification Method**:
```bash
# Test webhook endpoint access
curl -H "Host: webhook.10.78.14.61.nip.io" \
  http://localhost:30080/ -I

# Expected to return 400 status code (normal, missing webhook payload)
```

## 🔧 System Configuration Checklist

### Dashboard Configuration Check
- [ ] `--read-only=false` parameter is set
- [ ] HTTP Basic Auth is configured
- [ ] RBAC permissions are correctly bound
- [ ] Ingress configuration is complete

### Webhook Configuration Check
- [ ] EventListener is running normally
- [ ] Ingress configuration is correct
- [ ] Domain resolution is normal
- [ ] Port mapping is correct

### Network Configuration Check
- [ ] Nginx Ingress Controller is running normally
- [ ] TLS certificate configuration is correct
- [ ] Port mapping configuration is correct
- [ ] Firewall rules allow access

## 📋 Access Information Summary

### Dashboard Access
- **URL**: https://tekton.10.78.14.61.nip.io
- **Authentication**: admin / admin123
- **Port**: 30443 (HTTPS)

### Webhook Access
- **URL**: http://webhook.10.78.14.61.nip.io
- **Port**: 30080 (HTTP)
- **Purpose**: Git platform webhook integration

## 🚀 Preventive Measures

1. **Regular Configuration Checks**: Check Dashboard and Webhook configuration monthly
2. **Log Monitoring**: Monitor Dashboard and Ingress log output
3. **Permission Auditing**: Regularly check if RBAC configuration is correct
4. **Configuration Backup**: Backup important configuration files

## 📞 Technical Support

If encountering other issues, please check:
1. Kubernetes cluster status
2. Tekton component logs
3. Ingress Controller status
4. Network connectivity

---

**Last Updated**: 2025-08-21
**Version**: v1.0
**Status**: Resolved