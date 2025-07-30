# Production GPU Pipeline Files

This directory contains the finalized, production-ready GPU pipeline configurations for Tekton.

## Main Pipeline Files

### 📦 `pipelines/`

#### Primary Workflows
- **`gpu-real-8-step-workflow-original.yaml`** - Complete 8-step GPU workflow for full-scale datasets
- **`gpu-real-8-step-workflow-lite.yaml`** - Lightweight 8-step GPU workflow with dataset subsampling for memory efficiency
- **`rmm-simple-verification-test.yaml`** - RMM (RAPIDS Memory Manager) verification and validation test

#### Workflow Features
- ✅ **GPU Memory Management**: Proper RMM initialization and error handling
- ✅ **Container Security**: Init containers with appropriate permissions
- ✅ **GitHub Integration**: Private repository access with token authentication
- ✅ **Testing Framework**: Complete pytest execution with coverage and HTML reports
- ✅ **Artifact Collection**: Automated collection of notebooks, logs, and test results
- ✅ **Error Resilience**: Smart error handling and graceful degradation

### 🔧 `tasks/`

#### Core Tasks
- **`gpu-papermill-production-init-rmm-fixed.yaml`** - Main GPU notebook execution task with RMM support
- **`gpu-papermill-execution-production-init-rmm-fixed.yaml`** - Enhanced papermill execution with init containers

#### Utility Tasks
- **`safe-git-clone-task.yaml`** - Secure git repository cloning
- **`jupyter-nbconvert-task.yaml`** - Notebook to HTML conversion
- **`pytest-execution-task.yaml`** - Python testing execution
- **`results-validation-cleanup-task.yaml`** - Result validation and cleanup
- **`large-dataset-download-task.yaml`** - Large dataset handling

## Usage Instructions

### 1. Deploy RMM Verification Test
```bash
kubectl apply -f examples/production/pipelines/rmm-simple-verification-test.yaml
```

### 2. Deploy Lite Workflow (Recommended for Testing)
```bash
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml
```

### 3. Deploy Original Workflow (Full Dataset)
```bash
kubectl apply -f examples/production/pipelines/gpu-real-8-step-workflow-original.yaml
```

## Prerequisites

- Kubernetes cluster with GPU nodes
- Tekton Pipelines installed
- Persistent Volume Claims configured
- GitHub token for private repository access (stored as Kubernetes secret)

## Differences Between Versions

| Feature | Lite Version | Original Version |
|---------|-------------|------------------|
| **Dataset Size** | Subsampled (50k cells, 10k genes) | Full dataset |
| **Memory Usage** | Low (~2-4GB GPU) | High (8GB+ GPU) |
| **Execution Time** | Fast (~10-15 min) | Slower (~30-60 min) |
| **Use Case** | Testing, CI/CD | Production analysis |
| **Error Prone** | Low | Medium (memory issues) |

## Architecture

```
8-Step GPU Workflow:
1. Container Environment Setup
2. Git Clone Blueprint Repository  
3. Papermill Notebook Execution (with RMM)
4. Jupyter NBConvert to HTML
5. Download Test Repository
6. Pytest Execution (with coverage)
7. Results Collection and Artifacts
8. Final Summary and Validation
```

## Troubleshooting

For debugging files and iterative development versions, see the `examples/troubleshooting/` directory. 