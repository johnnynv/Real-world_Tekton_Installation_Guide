# Tekton 生产环境安装指南

本指南提供了在 Kubernetes 集群上安装 Tekton 的完整生产级配置方案，分为两个清晰的阶段实施。

## 📋 部署架构概览

```
阶段一：核心基础设施           阶段二：CI/CD 自动化
┌─────────────────────┐      ┌─────────────────────┐
│  Ingress Controller │      │   GitHub Webhook    │
│                     │      │                     │
│  Tekton Pipelines   │ ──▶  │  Event Listeners    │
│                     │      │                     │
│  Tekton Dashboard   │      │  Trigger Bindings   │
│                     │      │                     │
│  生产级网络配置       │      │  Pipeline 自动触发    │
└─────────────────────┘      └─────────────────────┘
```

## 🎯 部署目标

- ✅ **生产环境配置**：遵循 Kubernetes 最佳实践
- ✅ **网络安全**：使用 Ingress 和 IngressClass 配置
- ✅ **高可用性**：容错和监控配置
- ✅ **自动化 CI/CD**：GitHub webhook 集成
- ✅ **一次性成功**：包含所有问题的预防和修复

## 📁 项目结构

```
Real-world_Tekton_Installation_Guide/
├── README.md                          # 本文档 - 总体指南
├── TROUBLESHOOTING.md                 # 问题排查指南
│
├── 阶段一：核心基础设施部署 📦
│   ├── 01-tekton-core-installation.md    # 核心组件安装指南
│   ├── 01-install-tekton-core.sh         # 自动化安装脚本
│   └── 01-cleanup-tekton-core.sh         # 环境清理脚本
│
├── 阶段二：CI/CD 自动化配置 🚀  
│   ├── 02-tekton-triggers-setup.md       # Triggers 配置指南
│   ├── 02-install-tekton-triggers.sh     # 自动化安装脚本
│   └── 02-cleanup-tekton-triggers.sh     # 环境清理脚本
│
└── 工具脚本 🛠️
    ├── verify-installation.sh            # 统一验证脚本
    └── k8s_cluster_info.sh              # 集群信息脚本
```

## 🚀 快速开始

### 前提条件

- ✅ Kubernetes 集群 (v1.20+)
- ✅ kubectl 命令行工具
- ✅ 集群管理员权限
- ✅ Helm v3 (用于 Ingress Controller)
- ✅ 节点外部访问能力

### 阶段一：核心基础设施部署 📦

**目标**: 安装 Tekton Pipelines + Dashboard，实现 Web UI 访问

1. **阅读安装指南**：
   ```bash
   cat 01-tekton-core-installation.md
   ```

2. **清理环境（如果之前安装过）**：
   ```bash
   chmod +x 01-cleanup-tekton-core.sh
   ./01-cleanup-tekton-core.sh
   ```

3. **自动化安装**：
   ```bash
   chmod +x 01-install-tekton-core.sh
   ./01-install-tekton-core.sh
   ```

4. **验证安装**：
   ```bash
   chmod +x verify-installation.sh
   ./verify-installation.sh --stage=core
   ```

5. **访问 Dashboard**：
   ```
   http://tekton.10.117.8.154.nip.io/
   ```

### 阶段二：CI/CD 自动化配置 🚀

**目标**: 配置 GitHub Webhook 触发 Pipeline 自动执行

1. **阅读配置指南**：
   ```bash
   cat 02-tekton-triggers-setup.md
   ```

2. **清理环境（如果之前配置过）**：
   ```bash
   chmod +x 02-cleanup-tekton-triggers.sh
   ./02-cleanup-tekton-triggers.sh
   ```

3. **自动化配置**：
   ```bash
   chmod +x 02-install-tekton-triggers.sh
   ./02-install-tekton-triggers.sh
   ```

4. **验证配置**：
   ```bash
   ./verify-installation.sh --stage=triggers
   ```

5. **测试自动触发**：
   - 配置 GitHub Webhook
   - 推送代码测试自动执行

## 🏗️ 生产环境配置特性

### 网络和安全
- ✅ **Ingress Controller**: Nginx 生产级配置
- ✅ **IngressClass**: 标准化路由规则
- ✅ **Host Network**: 优化网络性能
- ✅ **SSL 就绪**: 支持 HTTPS 配置
- ✅ **External IPs**: 明确的外部访问配置

### 高可用性
- ✅ **资源限制**: CPU/Memory 限制配置
- ✅ **健康检查**: Pod 就绪和存活探针
- ✅ **监控就绪**: 日志和指标集成
- ✅ **故障恢复**: 自动重启和恢复机制

### 权限管理
- ✅ **RBAC**: 最小权限原则
- ✅ **Service Account**: 专用服务账户
- ✅ **Pod Security**: 符合安全标准
- ✅ **Secret 管理**: 安全的敏感信息存储

## 📊 环境信息

| 组件 | 版本/配置 | 访问地址 |
|------|----------|----------|
| **Kubernetes** | v1.31.6 | - |
| **Tekton Pipelines** | latest | - |
| **Tekton Dashboard** | latest | http://tekton.10.117.8.154.nip.io/ |
| **Tekton Triggers** | latest | http://tekton.10.117.8.154.nip.io/webhook |
| **Nginx Ingress** | latest | - |
| **命名空间** | tekton-pipelines | - |

## 🔧 运维和监控

### 日常监控命令

```bash
# 检查所有组件状态
kubectl get pods -n tekton-pipelines

# 查看 Dashboard
kubectl get ingress -n tekton-pipelines

# 监控 Pipeline 执行
kubectl get pipelinerun -n tekton-pipelines --watch

# 查看组件日志
kubectl logs -l app=tekton-dashboard -n tekton-pipelines -f
```

### 故障排查

如遇到问题，请按以下顺序排查：

1. **运行验证脚本**：
   ```bash
   ./verify-installation.sh --stage=all
   ```

2. **查看详细排查指南**：
   ```bash
   cat TROUBLESHOOTING.md
   ```

3. **查看实时日志**：
   ```bash
   kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f
   ```

## 🧹 完全清理

如需完全卸载所有组件：

```bash
# 清理阶段二组件
./02-cleanup-tekton-triggers.sh

# 清理阶段一组件  
./01-cleanup-tekton-core.sh

# 验证清理完成
kubectl get all -n tekton-pipelines
kubectl get ns tekton-pipelines
```

## 📖 详细文档

- **[阶段一：核心基础设施安装](./01-tekton-core-installation.md)** - Pipeline + Dashboard 安装
- **[阶段二：CI/CD 自动化配置](./02-tekton-triggers-setup.md)** - Triggers + GitHub Webhook
- **[问题排查指南](./TROUBLESHOOTING.md)** - 常见问题和解决方案

## 🤝 支持

- 📧 **问题反馈**: GitHub Issues
- 📚 **官方文档**: [Tekton Documentation](https://tekton.dev/docs/)
- 🔧 **故障排查**: [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

## 📄 许可证

本项目采用 MIT 许可证。

---

## ⚡ 重要提示

- 🚨 **生产环境**: 本配置专为生产环境设计，包含安全和性能优化
- 🔄 **一次性成功**: 脚本包含所有已知问题的自动修复
- 📊 **监控集成**: 支持 Prometheus/Grafana 集成（可选配置）
- 🔐 **安全加固**: 遵循 Kubernetes 安全最佳实践

**🎯 开始您的 Tekton 生产级部署之旅！** 