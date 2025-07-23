# Tekton Production Installation Guide

This guide provides a complete production-grade Tekton installation solution for Kubernetes clusters, implemented in two clear stages.

## 📋 Deployment Architecture Overview

```
Stage 1: Core Infrastructure         Stage 2: CI/CD Automation
┌─────────────────────┐             ┌─────────────────────┐
│  Ingress Controller │             │   GitHub Webhook    │
│                     │             │                     │
│  Tekton Pipelines   │ ──▶         │  Event Listeners    │
│                     │             │                     │
│  Tekton Dashboard   │             │  Trigger Bindings   │
│                     │             │                     │
│  Production Network │             │  Automated Pipeline │
└─────────────────────┘             └─────────────────────┘
```

## 🎯 Deployment Objectives

- ✅ **Production Configuration**: Following Kubernetes best practices
- ✅ **Network Security**: Ingress and IngressClass configuration
- ✅ **High Availability**: Fault tolerance and monitoring setup
- ✅ **Automated CI/CD**: GitHub webhook integration
- ✅ **One-time Success**: Includes prevention and fixes for all known issues

## 📁 Project Structure

```
Real-world_Tekton_Installation_Guide/
├── README.md                               # Main documentation
├── README-zh.md                            # Chinese documentation
│
├── 📁 docs/
│   ├── en/                                 # English documentation
│   │   ├── 01-tekton-core-installation.md
│   │   ├── 02-tekton-triggers-setup.md
│   │   └── troubleshooting.md
│   └── zh/                                 # Chinese documentation
│       ├── 01-tekton-core-installation.md
│       ├── 02-tekton-triggers-setup.md
│       └── troubleshooting.md
│
├── 📁 scripts/
│   ├── en/                                 # English scripts
│   │   ├── install/
│   │   │   ├── 01-install-tekton-core.sh
│   │   │   └── 02-install-tekton-triggers.sh
│   │   ├── cleanup/
│   │   │   ├── 01-cleanup-tekton-core.sh
│   │   │   └── 02-cleanup-tekton-triggers.sh
│   │   └── utils/
│   │       ├── verify-installation.sh
│   │       └── k8s-cluster-info.sh
│   └── zh/                                 # Chinese scripts
│       ├── install/
│       ├── cleanup/
│       └── utils/
│
└── 📁 examples/
    ├── pipelines/                          # Example pipelines
    ├── tasks/                              # Example tasks
    └── triggers/                           # Example triggers
```

## 🚀 Quick Start

### Prerequisites

- ✅ Kubernetes cluster (v1.20+)
- ✅ kubectl command line tool
- ✅ Cluster administrator privileges
- ✅ Helm v3 (for Ingress Controller)
- ✅ External node access capability

### Stage 1: Core Infrastructure Deployment 📦

**Objective**: Install Tekton Pipelines + Dashboard with Web UI access

1. **Read Installation Guide**:
   ```bash
   cat docs/en/01-tekton-core-installation.md
   ```

2. **Clean Environment (if previously installed)**:
   ```bash
   chmod +x scripts/en/cleanup/01-cleanup-tekton-core.sh
   ./scripts/en/cleanup/01-cleanup-tekton-core.sh
   ```

3. **Automated Installation**:
   ```bash
   chmod +x scripts/en/install/01-install-tekton-core.sh
   ./scripts/en/install/01-install-tekton-core.sh
   ```

4. **Verify Installation**:
   ```bash
   chmod +x scripts/en/utils/verify-installation.sh
   ./scripts/en/utils/verify-installation.sh --stage=core
   ```

5. **Access Dashboard**:
   ```
   http://tekton.YOUR_NODE_IP.nip.io/
   ```

### Stage 2: CI/CD Automation Configuration 🚀

**Objective**: Configure GitHub Webhook to trigger automatic Pipeline execution

1. **Read Configuration Guide**:
   ```bash
   cat docs/en/02-tekton-triggers-setup.md
   ```

2. **Clean Environment (if previously configured)**:
   ```bash
   chmod +x scripts/en/cleanup/02-cleanup-tekton-triggers.sh
   ./scripts/en/cleanup/02-cleanup-tekton-triggers.sh
   ```

3. **Automated Configuration**:
   ```bash
   chmod +x scripts/en/install/02-install-tekton-triggers.sh
   ./scripts/en/install/02-install-tekton-triggers.sh
   ```

4. **Verify Configuration**:
   ```bash
   ./scripts/en/utils/verify-installation.sh --stage=triggers
   ```

5. **Test Automated Triggering**:
   - Configure GitHub Webhook
   - Push code to test automatic execution

## 🏗️ Production Environment Features

### Network and Security
- ✅ **Ingress Controller**: Nginx production-grade configuration
- ✅ **IngressClass**: Standardized routing rules
- ✅ **Host Network**: Optimized network performance
- ✅ **SSL Ready**: HTTPS configuration support
- ✅ **External IPs**: Explicit external access configuration

### High Availability
- ✅ **Resource Limits**: CPU/Memory limit configuration
- ✅ **Health Checks**: Pod readiness and liveness probes
- ✅ **Monitoring Ready**: Log and metrics integration
- ✅ **Fault Recovery**: Automatic restart and recovery mechanisms

### Permission Management
- ✅ **RBAC**: Principle of least privilege
- ✅ **Service Account**: Dedicated service accounts
- ✅ **Pod Security**: Compliance with security standards
- ✅ **Secret Management**: Secure sensitive information storage

## 📊 Environment Information

| Component | Version/Configuration | Access URL |
|-----------|----------------------|------------|
| **Kubernetes** | v1.20+ | - |
| **Tekton Pipelines** | latest | - |
| **Tekton Dashboard** | latest | http://tekton.YOUR_NODE_IP.nip.io/ |
| **Tekton Triggers** | latest | http://tekton.YOUR_NODE_IP.nip.io/webhook |
| **Nginx Ingress** | latest | - |
| **Namespace** | tekton-pipelines | - |

## 🔧 Operations and Monitoring

### Daily Monitoring Commands

```bash
# Check all component status
kubectl get pods -n tekton-pipelines

# View Dashboard
kubectl get ingress -n tekton-pipelines

# Monitor Pipeline execution
kubectl get pipelinerun -n tekton-pipelines --watch

# View component logs
kubectl logs -l app=tekton-dashboard -n tekton-pipelines -f
```

### Troubleshooting

When encountering issues, troubleshoot in the following order:

1. **Run Verification Script**:
   ```bash
   ./scripts/en/utils/verify-installation.sh --stage=all
   ```

2. **View Detailed Troubleshooting Guide**:
   ```bash
   cat docs/en/troubleshooting.md
   ```

3. **View Real-time Logs**:
   ```bash
   kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f
   ```

## 🧹 Complete Cleanup

To completely uninstall all components:

```bash
# Clean Stage 2 components
./scripts/en/cleanup/02-cleanup-tekton-triggers.sh

# Clean Stage 1 components  
./scripts/en/cleanup/01-cleanup-tekton-core.sh

# Verify cleanup completion
kubectl get all -n tekton-pipelines
kubectl get ns tekton-pipelines
```

## 📖 Detailed Documentation

- **[Stage 1: Core Infrastructure Installation](./docs/en/01-tekton-core-installation.md)** - Pipeline + Dashboard installation
- **[Stage 2: CI/CD Automation Configuration](./docs/en/02-tekton-triggers-setup.md)** - Triggers + GitHub Webhook
- **[Troubleshooting Guide](./docs/en/troubleshooting.md)** - Common issues and solutions

## 🌐 Language Support

- **English**: [README.md](./README.md) | [Documentation](./docs/en/) | [Scripts](./scripts/en/)
- **中文**: [README-zh.md](./README-zh.md) | [文档](./docs/zh/) | [脚本](./scripts/zh/)

## 🤝 Support

- 📧 **Issue Reports**: GitHub Issues
- 📚 **Official Documentation**: [Tekton Documentation](https://tekton.dev/docs/)
- 🔧 **Troubleshooting**: [Troubleshooting Guide](./docs/en/troubleshooting.md)

## 📄 License

This project is licensed under the MIT License.

---

## ⚡ Important Notes

- 🚨 **Production Environment**: This configuration is designed for production environments with security and performance optimizations
- 🔄 **One-time Success**: Scripts include automatic fixes for all known issues
- 📊 **Monitoring Integration**: Supports Prometheus/Grafana integration (optional configuration)
- 🔐 **Security Hardening**: Follows Kubernetes security best practices

**🎯 Start your production-grade Tekton deployment journey!** 