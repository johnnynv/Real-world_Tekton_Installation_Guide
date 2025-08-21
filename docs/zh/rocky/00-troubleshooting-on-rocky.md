# Rocky Linux 环境 Tekton 故障排除指南

本指南记录了在Rocky Linux + Kubernetes环境中安装和配置Tekton时遇到的常见问题及其解决方案。

## 🚨 常见问题及解决方案

### 问题1: Dashboard访问出现Forbidden错误

**症状描述**:
- 访问Tekton Dashboard时某些菜单显示"Forbidden"错误
- API调用返回403状态码
- 错误信息: "User 'system:anonymous' cannot list resource"

**问题分析**:
1. Dashboard配置中`--read-only=true`参数限制了写操作
2. Ingress配置中缺少HTTP Basic Auth认证
3. RBAC权限配置不完整

**解决步骤**:

#### 步骤1: 修复Dashboard配置
```bash
# 移除read-only限制
kubectl patch deployment tekton-dashboard -n tekton-pipelines \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/6", "value": "--read-only=false"}]'

# 等待部署完成
kubectl rollout status deployment/tekton-dashboard -n tekton-pipelines
```

#### 步骤2: 配置HTTP Basic Auth
```bash
# 为Dashboard Ingress添加认证配置
kubectl patch ingress tekton-dashboard-ingress -n tekton-pipelines \
  --type='merge' -p='{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/auth-type":"basic","nginx.ingress.kubernetes.io/auth-secret":"tekton-basic-auth","nginx.ingress.kubernetes.io/auth-realm":"Tekton Dashboard Authentication"}}}'
```

#### 步骤3: 验证修复结果
```bash
# 测试Dashboard API访问
curl -H "Host: tekton.10.78.14.61.nip.io" \
  -u admin:admin123 \
  https://localhost:30443/api/v1/namespaces -k

# 测试Tekton API访问
curl -H "Host: tekton.10.78.14.61.nip.io" \
  -u admin:admin123 \
  https://localhost:30443/apis/tekton.dev/v1/namespaces/tekton-pipelines/pipelines -k
```

**预期结果**:
- ✅ Dashboard API返回200状态码
- ✅ 可以正常访问namespaces列表
- ✅ Tekton资源API正常工作
- ✅ 不再出现Forbidden错误

### 问题2: Webhook域名访问配置

**症状描述**:
- Webhook只能通过NodePort端口访问
- 无法通过*.nip.io域名访问
- 外部系统无法触发Pipeline

**解决方案**:
Webhook已经配置了正确的ingress，可以通过以下域名访问：
```
http://webhook.10.78.14.61.nip.io
```

**验证方法**:
```bash
# 测试webhook端点访问
curl -H "Host: webhook.10.78.14.61.nip.io" \
  http://localhost:30080/ -I

# 预期返回400状态码（正常，因为缺少webhook payload）
```

## 🔧 系统配置检查清单

### Dashboard配置检查
- [ ] `--read-only=false` 参数已设置
- [ ] HTTP Basic Auth已配置
- [ ] RBAC权限已正确绑定
- [ ] Ingress配置完整

### Webhook配置检查
- [ ] EventListener正常运行
- [ ] Ingress配置正确
- [ ] 域名解析正常
- [ ] 端口映射正确

### 网络配置检查
- [ ] Nginx Ingress Controller运行正常
- [ ] TLS证书配置正确
- [ ] 端口映射配置正确
- [ ] 防火墙规则允许访问

## 📋 访问信息汇总

### Dashboard访问
- **URL**: https://tekton.10.78.14.61.nip.io
- **认证**: admin / admin123
- **端口**: 30443 (HTTPS)

### Webhook访问
- **URL**: http://webhook.10.78.14.61.nip.io
- **端口**: 30080 (HTTP)
- **用途**: Git平台webhook集成

## 🚀 预防措施

1. **定期检查配置**: 每月检查一次Dashboard和Webhook配置
2. **监控日志**: 关注Dashboard和Ingress的日志输出
3. **权限审计**: 定期检查RBAC配置是否正确
4. **备份配置**: 备份重要的配置文件

## 📞 技术支持

如果遇到其他问题，请检查：
1. Kubernetes集群状态
2. Tekton组件日志
3. Ingress Controller状态
4. 网络连接性

---

**最后更新**: 2025-08-21
**版本**: v1.0
**状态**: 已解决
