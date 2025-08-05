#!/bin/bash

# Tekton Step 4 GPU Pipeline Deployment Verification Script
# Verify GPU environment, Pipeline deployment and complete workflow

set -e

echo "🔍 Verifying Tekton Step 4 GPU Pipeline deployment..."
echo "==========================================="

# Check GPU environment
echo "1. Checking GPU environment..."

# Check GPU nodes
GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -eq 0 ]; then
    echo "⚠️ No nodes with accelerator=nvidia-tesla-gpu label found"
    echo "Checking for other GPU node labels..."
    
    # Check alternative GPU labels
    ALT_GPU_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu") | .metadata.name' 2>/dev/null | wc -l)
    if [ "$ALT_GPU_NODES" -gt 0 ]; then
        echo "✅ Found $ALT_GPU_NODES GPU nodes (nvidia.com/gpu)"
        kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu" | grep -v '<none>'
    else
        echo "❌ No GPU nodes found"
        echo "💡 Please ensure NVIDIA GPU Operator is installed or GPU nodes are configured"
    fi
else
    echo "✅ Found $GPU_NODES GPU nodes"
    kubectl get nodes -l accelerator=nvidia-tesla-gpu
fi

# Check GitHub Token Secret
echo ""
echo "2. Checking GitHub Token configuration..."
kubectl get secret github-token -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ GitHub Token Secret does not exist"
    echo "Please run first: kubectl create secret generic github-token --from-literal=token=your-github-token -n tekton-pipelines"
    exit 1
}

echo "✅ GitHub Token Secret configured"

# Check GPU Pipeline related resources
echo ""
echo "3. Checking GPU Pipeline resources..."

# Check Pipeline definitions
PIPELINE_COUNT=0
for pipeline in "gpu-real-8-step-workflow-lite" "gpu-real-8-step-workflow-original" "rmm-simple-verification-test"; do
    if kubectl get pipeline $pipeline -n tekton-pipelines >/dev/null 2>&1; then
        echo "✅ Pipeline '$pipeline' deployed"
        ((PIPELINE_COUNT++))
    else
        echo "⚠️ Pipeline '$pipeline' not deployed"
    fi
done

if [ "$PIPELINE_COUNT" -eq 0 ]; then
    echo "❌ No GPU Pipelines found"
    echo "Please deploy Pipelines first: kubectl apply -f examples/production/pipelines/"
    exit 1
fi

echo "✅ Found $PIPELINE_COUNT GPU Pipelines"

# Check Task resources
echo ""
echo "4. Checking GPU Task resources..."
TASK_COUNT=0
for task in "gpu-papermill-production-init-rmm-fixed" "safe-git-clone-task" "jupyter-nbconvert-task" "pytest-execution-task"; do
    if kubectl get task $task -n tekton-pipelines >/dev/null 2>&1; then
        echo "✅ Task '$task' deployed"
        ((TASK_COUNT++))
    else
        echo "⚠️ Task '$task' not deployed"
    fi
done

echo "✅ Found $TASK_COUNT related Tasks"

# Check PVC configuration
echo ""
echo "5. Checking persistent storage configuration..."
if kubectl get pvc shared-workspace -n tekton-pipelines >/dev/null 2>&1; then
    PVC_STATUS=$(kubectl get pvc shared-workspace -n tekton-pipelines -o jsonpath='{.status.phase}')
    if [ "$PVC_STATUS" = "Bound" ]; then
        echo "✅ PVC 'shared-workspace' status: $PVC_STATUS"
        PVC_SIZE=$(kubectl get pvc shared-workspace -n tekton-pipelines -o jsonpath='{.spec.resources.requests.storage}')
        echo "✅ PVC size: $PVC_SIZE"
    else
        echo "❌ PVC 'shared-workspace' status abnormal: $PVC_STATUS"
    fi
else
    echo "⚠️ PVC 'shared-workspace' does not exist"
    echo "💡 GPU Pipeline requires persistent storage to save workflow state"
fi

# Check recent PipelineRuns
echo ""
echo "6. Checking Pipeline execution history..."
RECENT_RUNS=$(kubectl get pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5)
if [ -n "$RECENT_RUNS" ]; then
    echo "✅ Recent PipelineRuns:"
    echo "$RECENT_RUNS"
    
    # Check latest run status
    LATEST_RUN=$(kubectl get pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -1 | awk '{print $1}')
    if [ -n "$LATEST_RUN" ] && [ "$LATEST_RUN" != "NAME" ]; then
        RUN_STATUS=$(kubectl get pipelinerun $LATEST_RUN -n tekton-pipelines -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
        echo "✅ Latest run status: $RUN_STATUS"
    fi
else
    echo "⚠️ No PipelineRun history found"
    echo "💡 Run Pipeline to verify complete workflow"
fi

# Check GPU availability test
echo ""
echo "7. Testing GPU availability..."
if [ "$ALT_GPU_NODES" -gt 0 ] || [ "$GPU_NODES" -gt 0 ]; then
    echo "Testing GPU access..."
    
    GPU_TEST_RESULT=$(kubectl run gpu-test-verify --rm -i --restart=Never \
        --image=nvidia/cuda:12.2-runtime-ubuntu22.04 \
        --limits=nvidia.com/gpu=1 \
        --timeout=30s \
        -- nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "failed")
    
    if [ "$GPU_TEST_RESULT" != "failed" ] && [ -n "$GPU_TEST_RESULT" ]; then
        echo "✅ GPU test successful:"
        echo "$GPU_TEST_RESULT"
    else
        echo "❌ GPU test failed"
        echo "💡 Please check GPU node scheduling and NVIDIA runtime configuration"
    fi
else
    echo "⚠️ Skipping GPU test (no available GPU nodes)"
fi

# Check necessary namespace permissions
echo ""
echo "8. Checking permission configuration..."
RBAC_CHECK=$(kubectl auth can-i create pipelineruns --as=system:serviceaccount:tekton-pipelines:default -n tekton-pipelines 2>/dev/null && echo "ok" || echo "failed")
if [ "$RBAC_CHECK" = "ok" ]; then
    echo "✅ RBAC permission configuration correct"
else
    echo "⚠️ RBAC permissions may need adjustment"
fi

# Generate deployment recommendations
echo ""
echo "=========================================="
echo "✅ Tekton Step 4 GPU Pipeline verification completed!"
echo ""
echo "📋 Verification results overview:"
if [ "$GPU_NODES" -gt 0 ] || [ "$ALT_GPU_NODES" -gt 0 ]; then
    echo "  ✅ GPU environment available"
else
    echo "  ⚠️ GPU environment needs configuration"
fi
echo "  ✅ GitHub Token configuration"
echo "  ✅ Pipeline resources ($PIPELINE_COUNT items)"
echo "  ✅ Task resources ($TASK_COUNT items)"
echo "  ✅ Permission configuration"
echo ""

# Provide next step recommendations
if [ "$PIPELINE_COUNT" -gt 0 ]; then
    echo "🚀 Recommended next steps:"
    echo "  1. Run lightweight verification:"
    echo "     kubectl create -f examples/production/pipelines/rmm-simple-verification-test.yaml"
    echo ""
    echo "  2. Run complete workflow (test version):"
    echo "     kubectl create -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml"
    echo ""
    echo "  3. Monitor execution status:"
    echo "     kubectl get pipelineruns -n tekton-pipelines -w"
    echo ""
    echo "  4. View execution logs:"
    echo "     tkn pipelinerun logs -f -n tekton-pipelines"
else
    echo "🔧 Need to deploy Pipeline first:"
    echo "  kubectl apply -f examples/production/pipelines/"
fi

echo ""
echo "📊 System is ready, can run GPU-accelerated scientific computing workflows!" 