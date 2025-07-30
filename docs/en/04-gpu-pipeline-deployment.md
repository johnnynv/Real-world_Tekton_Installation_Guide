# GPU Scientific Computing Pipeline Deployment Guide

This guide provides detailed instructions for deploying battle-tested GPU-accelerated scientific computing Pipelines on Tekton, including RMM (RAPIDS Memory Manager) integration, error handling, and complete GitHub Actions-style workflows.

## 📋 Deployment Goals

- ✅ Deploy production-ready GPU Pipelines
- ✅ Configure RMM memory management and error handling
- ✅ Implement complete 8-step GitHub Actions-style workflow
- ✅ Support lightweight and full dataset versions
- ✅ Integrate GitHub private repository access
- ✅ Generate comprehensive test reports and artifacts

## 🔧 Prerequisites

### System Requirements
- ✅ Completed [Tekton Webhook Configuration](03-tekton-webhook-configuration.md)
- ✅ Kubernetes cluster with GPU support (Recommended: 8GB+ GPU memory)
- ✅ NVIDIA GPU Operator installed
- ✅ Persistent storage support (at least 50GB)
- ✅ GitHub Personal Access Token (for private repositories)

### GPU Environment Verification
```bash
# Check GPU nodes
kubectl get nodes -l accelerator=nvidia-tesla-gpu

# Check GPU resources
kubectl describe node <gpu-node-name> | grep nvidia.com/gpu

# Verify GPU availability
kubectl run gpu-test --rm -i --tty --restart=Never \
  --image=nvidia/cuda:12.8-runtime-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi
```

## 🚀 Step 1: Configure GitHub Access Token

### Create GitHub Token Secret
```bash
# Create secret for private repository access
kubectl create secret generic github-token \
  --from-literal=token=your-github-token-here \
  -n tekton-pipelines
```

### Verify Secret
```bash
kubectl get secret github-token -n tekton-pipelines -o yaml
```

## 📦 Step 2: Deploy Production Pipeline Files

The project has been organized into a clear directory structure:

```
examples/
├── production/          # Production-ready files
│   ├── pipelines/       # Main workflows
│   ├── tasks/          # Core task definitions
│   └── README.md       # Detailed usage instructions
└── troubleshooting/    # Debug and development history
    ├── pipelines/      # Various iteration versions
    └── tasks/          # Debug tasks
```

### Deploy Core Tasks
```bash
# Deploy main RMM-fixed task
kubectl apply -f examples/production/tasks/gpu-papermill-production-init-rmm-fixed.yaml

# Deploy other core tasks
kubectl apply -f examples/production/tasks/
```

### Deploy RMM Verification Test
```bash
# First deploy simple RMM verification test
kubectl apply -f examples/production/pipelines/rmm-simple-verification-test.yaml

# Monitor test execution
kubectl get pipelinerun -n tekton-pipelines -w
```

## 🎯 Step 3: Deploy Main GPU Workflows

### 3.1 Deploy Lightweight Version (Recommended for Testing)
```bash
# Deploy lite version - uses subsampled dataset, memory-friendly
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml

# Monitor execution
kubectl get pipelinerun gpu-real-8-step-workflow-lite -n tekton-pipelines -w
```

### 3.2 Deploy Full Version (Production Environment)
```bash
# Deploy original version - uses full dataset, requires more memory
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-original.yaml

# Monitor execution  
kubectl get pipelinerun gpu-real-8-step-workflow-original -n tekton-pipelines -w
```

## 📋 Version Comparison

| Feature | Lite Version | Original Version |
|---------|-------------|------------------|
| **Dataset Size** | Subsampled (50k cells, 10k genes) | Full dataset |
| **GPU Memory** | 2-4GB | 8GB+ |
| **Execution Time** | Fast (~10-15 minutes) | Slower (~30-60 minutes) |
| **Use Case** | Testing, CI/CD, Demo | Production analysis |
| **Success Rate** | High (memory safe) | Medium (may hit memory issues) |
| **Generated Files** | Complete artifact set | Complete artifact set |

## 🔧 Complete 8-Step Workflow Architecture

Both versions implement the same 8-step GitHub Actions-style workflow:

```
🔄 Complete 8-Step GPU Workflow:

1. 📋 Container Environment Setup
   - Set environment variables
   - Initialize workspaces
   - Verify GPU availability

2. 📂 Git Clone Blueprint Repository  
   - Clone single-cell-analysis-blueprint repository
   - Verify notebooks directory
   - Prepare analysis files

3. 🧬 Papermill Notebook Execution (with RMM)
   - Init Container: Permission setup + RMM initialization
   - GPU memory management configuration
   - Jupyter notebook execution (lite: data subsampling)
   - Error handling and logging

4. 🌐 Jupyter NBConvert to HTML
   - Convert executed notebook to HTML
   - Generate visual reports
   - Prepare test inputs

5. 📥 Download Test Repository  
   - Clone blueprint-github-test private repository
   - Use GitHub token authentication
   - Prepare test environment

6. 🧪 Pytest Execution (with Coverage)
   - Poetry environment setup
   - Install test dependencies (pytest-cov, pytest-html)
   - Execute test suite
   - Generate coverage and HTML reports

7. 📦 Results Collection and Artifacts
   - Collect all generated files
   - Organize artifact structure
   - Verify file integrity

8. 📊 Final Summary and Validation
   - Generate execution summary
   - Create GitHub Actions-style summary
   - List all artifacts
```

## 🔍 Monitoring and Log Viewing

### Real-time Monitoring
```bash
# View pipeline status
kubectl get pipelinerun -n tekton-pipelines

# View specific steps
kubectl get pods -n tekton-pipelines | grep gpu-real-8-step-workflow

# View specific step logs
kubectl logs <pod-name> -n tekton-pipelines -f
```

### View Generated Artifacts
```bash
# Access shared storage to view files
kubectl run temp-pod --rm -i --tty --restart=Never \
  --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"temp-pod","image":"busybox","command":["sh"],"volumeMounts":[{"mountPath":"/data","name":"shared-storage"}]}],"volumes":[{"name":"shared-storage","persistentVolumeClaim":{"claimName":"shared-pvc"}}]}}' \
  -n tekton-pipelines

# Inside pod, view files
ls -la /data/
cat /data/STEP_SUMMARY_LITE.md  # or STEP_SUMMARY_ORIGINAL.md
```

## 📁 Generated Artifact Files

After successful execution, the following files are generated:

### Lite Version Artifacts
- **`output_analysis_lite.ipynb`** (4.3M) - Executed analysis notebook
- **`output_analysis_lite.html`** (4.6M) - HTML format analysis report  
- **`coverage_lite.xml`** - pytest code coverage report
- **`pytest_results_lite.xml`** - JUnit format test results
- **`pytest_report_lite.html`** - HTML format test report
- **`papermill.log`** (20K) - Papermill execution log
- **`jupyter_nbconvert.log`** - HTML conversion log
- **`pytest_output.log`** - pytest execution log
- **`STEP_SUMMARY_LITE.md`** - Complete workflow summary

### Original Version Artifacts  
Similar to lite version, but all filenames without the `_lite` suffix.

## 🔗 GitHub Webhook Integration (Optional)

For automatic triggering, configure GitHub webhooks:

### Create TriggerTemplate
```bash
cat <<EOF | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: gpu-pipeline-trigger-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-repo-url
  - name: git-revision
  - name: pipeline-version
    default: "lite"
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: gpu-pipeline-run-
    spec:
      pipelineRef:
        name: gpu-real-8-step-workflow-\$(tt.params.pipeline-version)
      workspaces:
      - name: shared-storage
        volumeClaimTemplate:
          spec:
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 50Gi
EOF
```

## 🐛 Troubleshooting

### Common Issues and Solutions

#### 1. RMM Initialization Failure
```bash
# Check RMM verification test
kubectl logs <rmm-test-pod> -n tekton-pipelines

# Common solution: ensure GPU node has sufficient memory
```

#### 2. GPU Memory Exhaustion
```bash
# Recommend using lite version
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml

# Or check GPU memory usage
kubectl exec -it <gpu-pod> -n tekton-pipelines -- nvidia-smi
```

#### 3. GitHub Repository Access Failure
```bash
# Verify GitHub token
kubectl get secret github-token -n tekton-pipelines

# Recreate token
kubectl delete secret github-token -n tekton-pipelines
kubectl create secret generic github-token --from-literal=token=new-token -n tekton-pipelines
```

#### 4. Poetry/Dependency Installation Failure
The workflow includes intelligent error handling:
- Automatically installs curl and necessary tools
- Falls back to pip if Poetry installation fails
- Includes complete dependency verification

### Debug Resources
Detailed troubleshooting files and debug versions are located at:
- `examples/troubleshooting/` - Contains development history and issue reproduction files
- `examples/troubleshooting/README.md` - Detailed issue categorization and solutions

## ✅ Verify Successful Deployment

### 1. Check Component Status
```bash
# Check main pipelines
kubectl get pipeline -n tekton-pipelines | grep gpu-real-8-step-workflow

# Check recent executions
kubectl get pipelinerun -n tekton-pipelines --sort-by=.metadata.creationTimestamp
```

### 2. View Execution Summary
```bash
# View lite version summary
kubectl logs <final-summary-pod> -n tekton-pipelines | grep "🎉 ENTIRE 8-STEP"

# Confirm all steps completed
kubectl logs <final-summary-pod> -n tekton-pipelines | grep "✅"
```

## 🎊 Deployment Complete

Congratulations! You have successfully deployed battle-tested GPU scientific computing workflows:

### ✅ Completed Deployment
1. **🔐 GitHub Access Configuration** - Private repository access and authentication
2. **🧠 RMM Memory Management** - GPU memory optimization and error handling
3. **🔄 Dual Version Support** - Lite (testing) and Original (production) versions
4. **📋 Complete Workflow** - 8-step GitHub Actions-style process
5. **🛡️ Error Recovery** - Intelligent error handling and graceful degradation
6. **📊 Complete Artifacts** - All analysis results and test reports

### 🚀 Next Steps
1. **Test Lite Version** - Verify complete workflow
2. **Production Deployment** - Use Original version for actual analysis
3. **Performance Optimization** - Adjust resource configuration as needed
4. **CI/CD Integration** - Configure automatic triggering

### 📚 Additional Resources
- **Production Files**: `examples/production/README.md`
- **Troubleshooting**: `examples/troubleshooting/README.md`  
- **Development History**: Iteration files in `examples/troubleshooting/`

You now have a fully functional, battle-tested GPU scientific computing Pipeline! 🎉 