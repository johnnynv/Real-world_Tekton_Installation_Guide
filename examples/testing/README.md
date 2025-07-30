# Tekton GPU Testing Examples

This directory contains various GPU testing configurations for validating the Tekton GPU pipeline functionality.

## Test Files Overview

### Basic GPU Tests

#### `gpu-test-pod.yaml`
- **Purpose**: Basic GPU access and CUDA functionality test
- **Duration**: ~5 minutes (includes 300s sleep for debugging)
- **Tests**:
  - GPU device detection (`/dev/nvidia*`)
  - `nvidia-smi` functionality
  - Basic CuPy import and GPU count
- **Use Case**: Quick validation that GPU is accessible and functional
- **Run**: `kubectl apply -f gpu-test-pod.yaml`

#### `gpu-env-test-fixed.yaml`
- **Purpose**: Lightweight environment validation
- **Duration**: ~1 minute
- **Use Case**: Quick environment check without GPU resource allocation

### Comprehensive Testing

#### `gpu-python-dependency-test.yaml`
- **Purpose**: Comprehensive Python environment and dependency testing
- **Duration**: ~10-15 minutes
- **Tests**:
  - Python path and version validation
  - Core scientific packages (CuPy, Pandas, NumPy)
  - Dynamic package installation (scanpy)
  - Package import validation
- **Use Case**: Thorough validation before running scientific computing pipelines
- **Run**: `kubectl apply -f gpu-python-dependency-test.yaml`

### Pipeline Testing

#### `gpu-papermill-notebook-test.yaml`
- **Purpose**: Test notebook execution with Papermill
- **Duration**: Variable (depends on notebook complexity)
- **Tests**: Complete notebook execution workflow
- **Use Case**: Validate end-to-end notebook processing

#### `gpu-papermill-debug-test.yaml`
- **Purpose**: Debug notebook execution issues
- **Duration**: ~5-10 minutes
- **Use Case**: Troubleshooting notebook execution problems

#### `gpu-pipeline-test-simple.yaml`
- **Purpose**: Simple pipeline validation
- **Duration**: ~2-5 minutes
- **Use Case**: Basic pipeline functionality test

## Testing Strategy

### 1. Quick Validation
```bash
# Start with basic GPU test
kubectl apply -f gpu-test-pod.yaml
kubectl logs gpu-test-pod -n tekton-pipelines -f
```

### 2. Environment Validation
```bash
# Test Python dependencies
kubectl apply -f gpu-python-dependency-test.yaml
kubectl logs gpu-python-dependency-test -n tekton-pipelines -f
```

### 3. Pipeline Testing
```bash
# Test notebook execution
kubectl apply -f gpu-papermill-notebook-test.yaml
kubectl get taskrun -n tekton-pipelines -w
```

## Resource Requirements

| Test File | GPU | Memory | CPU | Duration |
|-----------|-----|--------|-----|----------|
| `gpu-test-pod.yaml` | 1 | Default | Default | 5 min |
| `gpu-python-dependency-test.yaml` | 1 | 8Gi | 2 | 10-15 min |
| `gpu-papermill-*` | 1 | 16-32Gi | 4-8 | Variable |

## Troubleshooting

### Common Issues

1. **Pod Pending**: Check GPU resource availability
   ```bash
   kubectl describe nodes | grep nvidia.com/gpu
   ```

2. **Permission Denied**: Verify security context
   ```bash
   kubectl describe pod <pod-name> -n tekton-pipelines
   ```

3. **Image Pull Issues**: Check container registry access
   ```bash
   kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'
   ```

### Cleanup
```bash
# Clean up test pods
kubectl delete pod gpu-test-pod gpu-python-dependency-test -n tekton-pipelines --ignore-not-found=true

# Clean up task runs
kubectl delete taskrun -l test-type=gpu-validation -n tekton-pipelines
```

## Integration with Main Pipeline

These tests are designed to validate the environment before running the main GPU scientific computing pipelines:

1. **Pre-deployment**: Use `gpu-test-pod.yaml` to verify GPU setup
2. **Environment check**: Use `gpu-python-dependency-test.yaml` to validate dependencies
3. **Pipeline validation**: Use `gpu-papermill-*` tests to verify notebook execution

## Contributing

When adding new test files:
1. Follow the naming convention: `gpu-<purpose>-test.yaml`
2. Include appropriate resource limits
3. Add comprehensive logging for debugging
4. Update this README with the new test description 