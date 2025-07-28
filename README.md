# Tekton GPU Scientific Computing Pipeline

Complete migration guide and implementation for moving GitHub Actions GPU scientific computing workflows to Tekton.

## 🎯 Project Overview

This project provides a complete solution for migrating GPU-accelerated scientific computing workflows from GitHub Actions to Tekton on Kubernetes. It includes all necessary configurations, documentation, and automation scripts for a seamless transition.

### Original GitHub Actions Workflow
- Docker Compose GPU container startup
- Papermill Jupyter Notebook execution
- HTML conversion with jupyter nbconvert
- PyTest execution with test repository
- Artifact generation (coverage.xml, pytest_results.xml, pytest_report.html)

### New Tekton Pipeline
- GPU-accelerated Tekton Tasks
- Kubernetes-native workflow orchestration
- GitHub Webhook integration
- Identical output artifacts

## 📁 Project Structure

```
Real-world_Tekton_Installation_Guide/
├── docs/                                    # Documentation
│   ├── zh/                                  # Chinese documentation
│   │   ├── 01-tekton-installation.md        # Tekton installation
│   │   ├── 02-tekton-triggers-setup.md      # Triggers configuration
│   │   ├── 03-tekton-webhook-configuration.md # Webhook setup
│   │   └── 04-gpu-pipeline-deployment.md    # GPU pipeline deployment
│   └── en/                                  # English documentation
│       ├── 01-tekton-installation.md
│       ├── 02-tekton-triggers-setup.md
│       ├── 03-tekton-webhook-configuration.md
│       └── 04-gpu-pipeline-deployment.md
├── examples/                                # Tekton configurations
│   ├── tasks/                              # Task definitions
│   │   ├── gpu-env-preparation-task.yaml
│   │   ├── gpu-env-preparation-task-fixed.yaml    # Fixed version for workspace issues
│   │   ├── gpu-papermill-execution-task.yaml
│   │   ├── jupyter-nbconvert-task.yaml
│   │   └── pytest-execution-task.yaml
│   ├── pipelines/                          # Pipeline definitions
│   │   ├── gpu-scientific-computing-pipeline.yaml
│   │   └── gpu-complete-pipeline-fixed.yaml       # Fixed version of complete pipeline
│   ├── triggers/                           # Trigger configurations
│   │   ├── gpu-pipeline-rbac.yaml
│   │   └── gpu-pipeline-trigger-template.yaml
│   ├── dashboard/                          # Dashboard configurations
│   │   └── tekton-dashboard-ingress-production.yaml
│   ├── workspaces/                         # Workspace configurations
│   │   └── gpu-pipeline-workspaces.yaml   # PVC workspace configurations
│   ├── runs/                               # Manual run examples
│   │   └── gpu-pipeline-manual-run.yaml   # Manual pipeline run example
│   ├── debug/                              # Debug utilities
│   │   ├── debug-workspace-test.yaml       # Workspace functionality test
│   │   └── debug-git-clone-test.yaml       # Git clone functionality test
│   └── testing/                            # Testing utilities
│       ├── gpu-test-pod.yaml               # GPU hardware access test
│       ├── gpu-env-test-fixed.yaml         # Environment preparation task test
│       ├── gpu-papermill-debug-test.yaml   # GPU papermill debug test
│       ├── gpu-papermill-notebook-test.yaml # Papermill notebook execution test
│       └── gpu-pipeline-test-simple.yaml   # Simplified pipeline test
├── scripts/                                # Deployment scripts
│   ├── deploy-complete-pipeline.sh         # One-click deployment
│   ├── execute-gpu-pipeline.sh             # Manual execution script
│   ├── validate-gpu-pipeline.sh            # End-to-end validation script
│   ├── verify-deployment.sh               # Deployment verification
│   ├── install/                           # Installation scripts
│   ├── cleanup/                           # Cleanup scripts
│   └── utils/                             # Utility scripts
├── notebooks/                              # Sample notebooks
│   └── 01_scRNA_analysis_preprocessing.ipynb
└── docker-compose/                        # Original Docker setup
    └── docker-compose-nb-2504.yaml
```

## 🚀 Quick Start

### Prerequisites
- Kubernetes cluster with GPU support
- kubectl configured and connected
- NVIDIA GPU Operator installed
- GitHub repository with Jupyter notebooks

### One-Click Deployment

```bash
chmod +x scripts/deploy-complete-pipeline.sh
./scripts/deploy-complete-pipeline.sh
```

### Verify Deployment

```bash
chmod +x scripts/verify-deployment.sh
./scripts/verify-deployment.sh
```

### Step-by-Step Deployment

1. **Install Tekton Core Components**
   - Follow: `docs/en/01-tekton-installation.md` or `docs/zh/01-tekton-installation.md`

2. **Configure Tekton Triggers**
   - Follow: `docs/en/02-tekton-triggers-setup.md` or `docs/zh/02-tekton-triggers-setup.md`

3. **Setup GitHub Webhooks**
   - Follow: `docs/en/03-tekton-webhook-configuration.md` or `docs/zh/03-tekton-webhook-configuration.md`

4. **Deploy GPU Pipeline**
   - Follow: `docs/en/04-gpu-pipeline-deployment.md` or `docs/zh/04-gpu-pipeline-deployment.md`

## 🔧 Pipeline Components

### Tasks
- **gpu-env-preparation**: Environment setup and code checkout
- **gpu-papermill-execution**: GPU-accelerated notebook execution
- **jupyter-nbconvert**: Notebook to HTML conversion
- **pytest-execution**: Test execution and reporting

### Pipeline Flow
1. Environment preparation → 2. GPU notebook execution → 3. HTML conversion → 4. Test execution

### Triggers
- GitHub push events to main/develop branches
- Commit messages containing [gpu] or [notebook] tags
- File changes in notebooks/ directory

## 📊 Dashboard Access

After deployment, access the Tekton Dashboard:
```bash
# Get Dashboard URL
kubectl get svc tekton-dashboard -n tekton-pipelines
```

View your Pipeline executions, Tasks, and real-time logs through the web interface.

## 🔗 GitHub Webhook Configuration

The deployment script will provide webhook configuration details:
- **Payload URL**: Your EventListener service endpoint
- **Content Type**: application/json
- **Secret**: Generated automatically and saved to webhook-secret.txt
- **Events**: Push events

## 📋 Generated Artifacts

The pipeline generates the same artifacts as the original GitHub Actions:
- `executed_notebook.ipynb` - Executed notebook
- `executed_notebook.html` - HTML report
- `coverage.xml` - Code coverage report
- `pytest_results.xml` - JUnit test results
- `pytest_report.html` - HTML test report

## 🔍 Monitoring and Verification

### Check Pipeline Status
```bash
# List all pipeline runs
kubectl get pipelineruns -n tekton-pipelines

# View specific run details
kubectl describe pipelinerun <name> -n tekton-pipelines

# View logs
kubectl logs -f <pod-name> -n tekton-pipelines
```

### GPU Resource Monitoring
```bash
# Check GPU nodes
kubectl get nodes -l accelerator=nvidia-tesla-gpu

# Monitor GPU usage during execution
kubectl exec -it <gpu-pod> -n tekton-pipelines -- nvidia-smi
```

## 🔧 Troubleshooting

### Common Issues
1. **GPU Scheduling**: Ensure nodes are labeled with GPU accelerator
2. **Webhook Failures**: Check EventListener logs and GitHub webhook delivery
3. **Task Failures**: Review individual task logs for specific errors

### Log Collection
```bash
# EventListener logs
kubectl logs -l app.kubernetes.io/component=eventlistener -n tekton-pipelines

# Pipeline execution logs
kubectl logs -l tekton.dev/pipeline=gpu-scientific-computing-pipeline -n tekton-pipelines
```

## 📚 Documentation

- **Installation Guide**: Complete Tekton setup instructions
- **Configuration Guide**: Triggers and webhook configuration
- **Deployment Guide**: GPU pipeline deployment steps
- **Troubleshooting**: Common issues and solutions

All documentation is available in both English (`docs/en/`) and Chinese (`docs/zh/`).

## 🤝 Contributing

This project provides a complete reference implementation. Customize the Tasks, Pipeline, and configurations according to your specific requirements.

## 📄 License

See LICENSE file for details.

---

## 🎉 Success Metrics

After successful deployment:
- ✅ Tekton Dashboard accessible
- ✅ GPU pipeline visible in Dashboard
- ✅ GitHub webhooks triggering pipeline runs
- ✅ Notebook execution on GPU resources
- ✅ Test artifacts generated successfully
- ✅ Complete CI/CD automation achieved
