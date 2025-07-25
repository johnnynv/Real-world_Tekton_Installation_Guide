# Tekton Getting Started Tutorial Guide

Welcome to the Tekton Getting Started Tutorials! This guide contains two main tutorials to help you master Tekton's core functionality from scratch.

## 📚 Tutorial Overview

### 1. [CLI Manual Operations Tutorial](01-tekton-cli-tutorial.md)
Learn Tekton's core concepts and basic operations:
- 🎯 **Goal**: Understand Task, Pipeline, PipelineRun concepts through `tkn` CLI tool
- 🛠️ **Content**: Manual creation and execution of Tekton resources
- 📊 **Monitoring**: View execution results using Dashboard UI and CLI
- ⏱️ **Learning Time**: Approximately 1-2 hours

### 2. [Webhook Triggers Tutorial](02-tekton-webhook-tutorial.md)
Learn automated CI/CD workflows:
- 🌐 **Goal**: Configure GitHub Webhook to automatically trigger Pipelines
- 🔧 **Content**: EventListener, TriggerBinding, TriggerTemplate configuration
- 🚀 **Practice**: Based on [johnnynv/tekton-poc](https://github.com/johnnynv/tekton-poc) project
- ⏱️ **Learning Time**: Approximately 2-3 hours

## 🚀 Quick Start

### Environment Requirements

- ✅ Kubernetes cluster with Tekton Pipelines deployed
- ✅ Tekton Dashboard installed
- ✅ `kubectl` command-line tool available
- ✅ Network access to GitHub (for Webhook tutorial)

### Learning Path

#### 📖 Recommended Learning Sequence

1. **Step 1**: Read [CLI Manual Operations Tutorial](01-tekton-cli-tutorial.md)
   - Understand Tekton basic concepts
   - Practice manual resource creation and execution
   - Familiarize with CLI tools and Dashboard

2. **Step 2**: Read [Webhook Triggers Tutorial](02-tekton-webhook-tutorial.md)
   - Learn automated trigger mechanisms
   - Configure GitHub integration
   - Implement complete CI/CD workflows

#### 🎯 Core Concept Learning Focus

| Concept | CLI Tutorial | Webhook Tutorial | Importance |
|---------|--------------|------------------|------------|
| Task | ⭐⭐⭐ | ⭐⭐ | Foundation |
| Pipeline | ⭐⭐⭐ | ⭐⭐⭐ | Core |
| PipelineRun | ⭐⭐⭐ | ⭐⭐⭐ | Core |
| EventListener | ⭐ | ⭐⭐⭐ | Advanced |
| TriggerBinding | - | ⭐⭐⭐ | Advanced |
| TriggerTemplate | - | ⭐⭐⭐ | Advanced |

## 🛠️ Preparation

### 1. Verify Environment

```bash
# Check Tekton installation
kubectl get namespaces | grep tekton

# Check component status
kubectl get pods -n tekton-pipelines

# Install tkn CLI
curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | \
  grep "browser_download_url.*Linux_x86_64" | \
  cut -d '"' -f 4 | xargs curl -LO
tar xzf tkn_*_Linux_x86_64.tar.gz
sudo mv tkn /usr/local/bin/
```

### 2. Clone Sample Project

```bash
# Clone this project (if not already done)
git clone <your-repo-url>
cd <your-repo-name>

# View example files
ls examples/
```

### 3. Access Dashboard

```bash
# Port forward to access Dashboard
kubectl port-forward service/tekton-dashboard -n tekton-pipelines 9097:9097

# Access in browser: http://localhost:9097
```

## 📝 Hands-on Exercises

### Basic Exercises (CLI Tutorial)

1. **Hello World Task**
   ```bash
   kubectl apply -f examples/tasks/hello-world-task.yaml
   tkn task start hello-world -n tekton-pipelines --showlog
   ```

2. **Simple Pipeline**
   ```bash
   kubectl apply -f examples/pipelines/hello-world-pipeline.yaml
   tkn pipeline start hello-world-pipeline -n tekton-pipelines --showlog
   ```

### Advanced Exercises (Webhook Tutorial)

1. **Configure Webhook**
   ```bash
   # Create webhook secret
   WEBHOOK_SECRET=$(openssl rand -hex 20)
   kubectl create secret generic github-webhook-secret \
     --from-literal=secretToken=$WEBHOOK_SECRET \
     -n tekton-pipelines
   ```

2. **Deploy Triggers**
   ```bash
   kubectl apply -f examples/triggers/github-trigger-binding.yaml
   kubectl apply -f examples/triggers/github-trigger-template.yaml
   kubectl apply -f examples/triggers/github-eventlistener.yaml
   ```

## 🔍 Monitoring and Debugging

### Dashboard Features

1. **Real-time Monitoring**
   - PipelineRuns execution status
   - TaskRuns detailed logs
   - Resource overview

2. **Historical Records**
   - Execution history queries
   - Failure analysis
   - Performance statistics

### CLI Debugging Commands

```bash
# View latest run
tkn pipelinerun logs --last -f

# View specific run
tkn pipelinerun describe <name>

# View events
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'
```

## 🚨 Common Issues

### 1. tkn command not found
```bash
# Reinstall tkn CLI
curl -LO https://github.com/tektoncd/cli/releases/latest/download/tkn_*_Linux_x86_64.tar.gz
```

### 2. Pipeline execution failure
```bash
# Check resource status
kubectl get pods -n tekton-pipelines
tkn pipelinerun describe <failed-run>
```

### 3. Webhook not triggering
```bash
# Check EventListener
kubectl logs -l app.kubernetes.io/name=eventlistener -n tekton-pipelines
```

## 📚 Extended Learning

After completing these tutorials, we recommend learning:

- 🔒 **Security Configuration**: ServiceAccount, RBAC, Secret management
- 🏗️ **Advanced Pipelines**: Conditional execution, parallel tasks, workspaces
- 🌐 **Multi-environment Deployment**: Development, testing, production configurations
- 🔧 **Custom Tasks**: Creating reusable task templates
- 📊 **Monitoring Integration**: Prometheus, Grafana integration

## 🤝 Contributing

If you find issues in the tutorials or have suggestions for improvement:

1. Submit Issues to report problems
2. Submit Pull Requests to improve content
3. Share your usage experience

## 📞 Getting Help

- 📖 [Tekton Official Documentation](https://tekton.dev/docs/)
- 💬 [Tekton Slack Community](https://tektoncd.slack.com/)
- 🐛 [GitHub Issues](https://github.com/tektoncd/pipeline/issues)

---

💡 **Tip**: We recommend completing the CLI tutorial first to establish basic concepts, then proceeding with the Webhook tutorial practice. Each tutorial has detailed step-by-step instructions and troubleshooting guides. 