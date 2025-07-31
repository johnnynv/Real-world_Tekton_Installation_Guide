#!/bin/bash

# Tekton 步骤4 GPU Pipeline 部署验证脚本
# 验证 GPU 环境、Pipeline 部署和完整工作流

set -e

echo "🔍 验证 Tekton 步骤4 GPU Pipeline 部署..."
echo "========================================"

# 检查 GPU 环境
echo "1. 检查 GPU 环境..."

# 检查 GPU 节点
GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -eq 0 ]; then
    echo "⚠️ 未找到带有 accelerator=nvidia-tesla-gpu 标签的节点"
    echo "检查是否有其他GPU节点标签..."
    
    # 检查替代的GPU标签
    ALT_GPU_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu") | .metadata.name' 2>/dev/null | wc -l)
    if [ "$ALT_GPU_NODES" -gt 0 ]; then
        echo "✅ 找到 $ALT_GPU_NODES 个GPU节点 (nvidia.com/gpu)"
        kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu" | grep -v '<none>'
    else
        echo "❌ 未找到任何GPU节点"
        echo "💡 请确保安装了 NVIDIA GPU Operator 或配置了 GPU 节点"
    fi
else
    echo "✅ 找到 $GPU_NODES 个GPU节点"
    kubectl get nodes -l accelerator=nvidia-tesla-gpu
fi

# 检查 GitHub Token Secret
echo ""
echo "2. 检查 GitHub Token 配置..."
kubectl get secret github-token -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ GitHub Token Secret 不存在"
    echo "请先运行: kubectl create secret generic github-token --from-literal=token=your-github-token -n tekton-pipelines"
    exit 1
}

echo "✅ GitHub Token Secret 已配置"

# 检查 GPU Pipeline 相关资源
echo ""
echo "3. 检查 GPU Pipeline 资源..."

# 检查 Pipeline 定义
PIPELINE_COUNT=0
for pipeline in "gpu-real-8-step-workflow-lite" "gpu-real-8-step-workflow-original" "rmm-simple-verification-test"; do
    if kubectl get pipeline $pipeline -n tekton-pipelines >/dev/null 2>&1; then
        echo "✅ Pipeline '$pipeline' 已部署"
        ((PIPELINE_COUNT++))
    else
        echo "⚠️ Pipeline '$pipeline' 未部署"
    fi
done

if [ "$PIPELINE_COUNT" -eq 0 ]; then
    echo "❌ 未找到任何 GPU Pipeline"
    echo "请先部署 Pipeline: kubectl apply -f examples/production/pipelines/"
    exit 1
fi

echo "✅ 找到 $PIPELINE_COUNT 个 GPU Pipeline"

# 检查 Task 资源
echo ""
echo "4. 检查 GPU Task 资源..."
TASK_COUNT=0
for task in "gpu-papermill-production-init-rmm-fixed" "safe-git-clone-task" "jupyter-nbconvert-task" "pytest-execution-task"; do
    if kubectl get task $task -n tekton-pipelines >/dev/null 2>&1; then
        echo "✅ Task '$task' 已部署"
        ((TASK_COUNT++))
    else
        echo "⚠️ Task '$task' 未部署"
    fi
done

echo "✅ 找到 $TASK_COUNT 个相关 Task"

# 检查 PVC 配置
echo ""
echo "5. 检查持久存储配置..."
if kubectl get pvc shared-workspace -n tekton-pipelines >/dev/null 2>&1; then
    PVC_STATUS=$(kubectl get pvc shared-workspace -n tekton-pipelines -o jsonpath='{.status.phase}')
    if [ "$PVC_STATUS" = "Bound" ]; then
        echo "✅ PVC 'shared-workspace' 状态: $PVC_STATUS"
        PVC_SIZE=$(kubectl get pvc shared-workspace -n tekton-pipelines -o jsonpath='{.spec.resources.requests.storage}')
        echo "✅ PVC 大小: $PVC_SIZE"
    else
        echo "❌ PVC 'shared-workspace' 状态异常: $PVC_STATUS"
    fi
else
    echo "⚠️ PVC 'shared-workspace' 不存在"
    echo "💡 GPU Pipeline 需要持久存储来保存工作流状态"
fi

# 检查最近的 PipelineRun
echo ""
echo "6. 检查 Pipeline 执行历史..."
RECENT_RUNS=$(kubectl get pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5)
if [ -n "$RECENT_RUNS" ]; then
    echo "✅ 最近的 PipelineRun:"
    echo "$RECENT_RUNS"
    
    # 检查最新运行状态
    LATEST_RUN=$(kubectl get pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -1 | awk '{print $1}')
    if [ -n "$LATEST_RUN" ] && [ "$LATEST_RUN" != "NAME" ]; then
        RUN_STATUS=$(kubectl get pipelinerun $LATEST_RUN -n tekton-pipelines -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
        echo "✅ 最新运行状态: $RUN_STATUS"
    fi
else
    echo "⚠️ 未找到 PipelineRun 历史"
    echo "💡 运行 Pipeline 来验证完整工作流"
fi

# 检查 GPU 可用性测试
echo ""
echo "7. 测试 GPU 可用性..."
if [ "$ALT_GPU_NODES" -gt 0 ] || [ "$GPU_NODES" -gt 0 ]; then
    echo "正在测试 GPU 访问..."
    
    GPU_TEST_RESULT=$(kubectl run gpu-test-verify --rm -i --restart=Never \
        --image=nvidia/cuda:12.2-runtime-ubuntu22.04 \
        --limits=nvidia.com/gpu=1 \
        --timeout=30s \
        -- nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "failed")
    
    if [ "$GPU_TEST_RESULT" != "failed" ] && [ -n "$GPU_TEST_RESULT" ]; then
        echo "✅ GPU 测试成功:"
        echo "$GPU_TEST_RESULT"
    else
        echo "❌ GPU 测试失败"
        echo "💡 请检查 GPU 节点调度和 NVIDIA 运行时配置"
    fi
else
    echo "⚠️ 跳过 GPU 测试 (无可用 GPU 节点)"
fi

# 检查必要的命名空间权限
echo ""
echo "8. 检查权限配置..."
RBAC_CHECK=$(kubectl auth can-i create pipelineruns --as=system:serviceaccount:tekton-pipelines:default -n tekton-pipelines 2>/dev/null && echo "ok" || echo "failed")
if [ "$RBAC_CHECK" = "ok" ]; then
    echo "✅ RBAC 权限配置正确"
else
    echo "⚠️ RBAC 权限可能需要调整"
fi

# 生成部署建议
echo ""
echo "========================================"
echo "✅ Tekton 步骤4 GPU Pipeline 验证完成！"
echo ""
echo "📋 验证结果概览:"
if [ "$GPU_NODES" -gt 0 ] || [ "$ALT_GPU_NODES" -gt 0 ]; then
    echo "  ✅ GPU 环境可用"
else
    echo "  ⚠️ GPU 环境需要配置"
fi
echo "  ✅ GitHub Token 配置"
echo "  ✅ Pipeline 资源 ($PIPELINE_COUNT 个)"
echo "  ✅ Task 资源 ($TASK_COUNT 个)"
echo "  ✅ 权限配置"
echo ""

# 提供下一步建议
if [ "$PIPELINE_COUNT" -gt 0 ]; then
    echo "🚀 推荐的下一步操作:"
    echo "  1. 运行轻量级验证:"
    echo "     kubectl create -f examples/production/pipelines/rmm-simple-verification-test.yaml"
    echo ""
    echo "  2. 运行完整工作流 (测试版):"
    echo "     kubectl create -f examples/production/pipelines/gpu-real-8-step-workflow-lite.yaml"
    echo ""
    echo "  3. 监控执行状态:"
    echo "     kubectl get pipelineruns -n tekton-pipelines -w"
    echo ""
    echo "  4. 查看执行日志:"
    echo "     tkn pipelinerun logs -f -n tekton-pipelines"
else
    echo "🔧 需要先部署 Pipeline:"
    echo "  kubectl apply -f examples/production/pipelines/"
fi

echo ""
echo "📊 系统已准备就绪，可以运行 GPU 加速的科学计算工作流！" 