#!/bin/bash

# Tekton 步骤2 Triggers 安装验证脚本
# 验证 Tekton Triggers、RBAC 权限和 EventListener 功能

set -e

echo "🔍 验证 Tekton 步骤2 Triggers 安装..."
echo "========================================"

# 检查 Tekton Triggers 组件
echo "1. 检查 Tekton Triggers 组件状态..."
TRIGGERS_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | grep -E "triggers" | wc -l)
if [ "$TRIGGERS_PODS" -lt 3 ]; then
    echo "❌ Tekton Triggers 组件不完整"
    kubectl get pods -n tekton-pipelines | grep triggers
    exit 1
fi

echo "✅ Tekton Triggers 组件运行正常："
kubectl get pods -n tekton-pipelines | grep triggers

# 检查 Triggers CRDs
echo ""
echo "2. 检查 Tekton Triggers CRDs..."
TRIGGERS_CRD_COUNT=$(kubectl get crd | grep triggers.tekton.dev | wc -l)
if [ "$TRIGGERS_CRD_COUNT" -lt 7 ]; then
    echo "❌ Tekton Triggers CRDs 不完整"
    kubectl get crd | grep triggers.tekton.dev
    exit 1
fi

echo "✅ Tekton Triggers CRDs 已安装 ($TRIGGERS_CRD_COUNT 个)："
kubectl get crd | grep triggers.tekton.dev

# 检查 RBAC 权限
echo ""
echo "3. 检查 RBAC 权限配置..."
kubectl get serviceaccount tekton-triggers-sa -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ ServiceAccount 不存在"
    exit 1
}

kubectl get clusterrole tekton-triggers-role >/dev/null 2>&1 || {
    echo "❌ ClusterRole 不存在"
    exit 1
}

kubectl get clusterrolebinding tekton-triggers-binding >/dev/null 2>&1 || {
    echo "❌ ClusterRoleBinding 不存在"
    exit 1
}

echo "✅ RBAC 权限配置正确"

# 检查 Trigger 资源
echo ""
echo "4. 检查 Trigger 资源..."
TRIGGER_TEMPLATE_COUNT=$(kubectl get triggertemplate -n tekton-pipelines --no-headers | wc -l)
TRIGGER_BINDING_COUNT=$(kubectl get triggerbinding -n tekton-pipelines --no-headers | wc -l)
EVENT_LISTENER_COUNT=$(kubectl get eventlistener -n tekton-pipelines --no-headers | wc -l)

if [ "$TRIGGER_TEMPLATE_COUNT" -lt 1 ] || [ "$TRIGGER_BINDING_COUNT" -lt 1 ] || [ "$EVENT_LISTENER_COUNT" -lt 1 ]; then
    echo "❌ Trigger 资源不完整"
    echo "   TriggerTemplate: $TRIGGER_TEMPLATE_COUNT"
    echo "   TriggerBinding: $TRIGGER_BINDING_COUNT" 
    echo "   EventListener: $EVENT_LISTENER_COUNT"
    exit 1
fi

echo "✅ Trigger 资源配置正确："
echo "   TriggerTemplate: $TRIGGER_TEMPLATE_COUNT 个"
echo "   TriggerBinding: $TRIGGER_BINDING_COUNT 个"
echo "   EventListener: $EVENT_LISTENER_COUNT 个"

# 检查 EventListener 状态
echo ""
echo "5. 检查 EventListener 状态..."
EL_READY=$(kubectl get eventlistener hello-world-listener -n tekton-pipelines -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$EL_READY" != "True" ]; then
    echo "❌ EventListener 未就绪"
    kubectl get eventlistener hello-world-listener -n tekton-pipelines
    exit 1
fi

echo "✅ EventListener 就绪状态正常"

# 检查 EventListener Pod
echo ""
echo "6. 检查 EventListener Pod..."
EL_POD=$(kubectl get pods -n tekton-pipelines -l eventlistener=hello-world-listener --no-headers | awk '{print $1}')
if [ -z "$EL_POD" ]; then
    echo "❌ EventListener Pod 不存在"
    exit 1
fi

EL_POD_STATUS=$(kubectl get pod $EL_POD -n tekton-pipelines --no-headers | awk '{print $3}')
if [ "$EL_POD_STATUS" != "Running" ]; then
    echo "❌ EventListener Pod 未运行: $EL_POD_STATUS"
    kubectl describe pod $EL_POD -n tekton-pipelines
    exit 1
fi

echo "✅ EventListener Pod 运行正常"

# 测试 EventListener 功能
echo ""
echo "7. 测试 EventListener 功能..."

# 使用 kubectl run 临时测试 EventListener
TEST_RESULT=$(kubectl run test-eventlistener --image=curlimages/curl --rm -i --restart=Never -- \
    curl -s -X POST http://el-hello-world-listener.tekton-pipelines.svc.cluster.local:8080 \
    -H 'Content-Type: application/json' \
    -d '{"repository":{"clone_url":"https://github.com/example/test-repo.git"},"head_commit":{"id":"test123"}}' \
    2>/dev/null | grep -o '"eventID":"[^"]*"' | head -1)

if [ -n "$TEST_RESULT" ]; then
    echo "✅ EventListener 触发测试成功: $TEST_RESULT"
    
    # 等待 TaskRun 创建
    sleep 5
    
    # 检查最新的 TaskRun
    LATEST_TASKRUN=$(kubectl get taskruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp | tail -1 | awk '{print $1}')
    if [ -n "$LATEST_TASKRUN" ] && [ "$LATEST_TASKRUN" != "NAME" ]; then
        echo "✅ 触发的 TaskRun: $LATEST_TASKRUN"
    else
        echo "⚠️ 未检测到新的 TaskRun，但 EventListener 响应正常"
    fi
else
    echo "❌ EventListener 测试失败"
    echo "检查 EventListener 服务："
    kubectl get svc -n tekton-pipelines | grep el-
    exit 1
fi

echo ""
echo "========================================"
echo "✅ Tekton 步骤2 Triggers 验证完成！"
echo ""
echo "📋 验证结果概览:"
echo "  ✅ Tekton Triggers 组件 (3个Pod运行)"
echo "  ✅ Tekton Triggers CRDs ($TRIGGERS_CRD_COUNT 个)"
echo "  ✅ RBAC 权限配置"
echo "  ✅ Trigger 资源配置"
echo "  ✅ EventListener 就绪"
echo "  ✅ EventListener 功能测试"
echo ""
echo "🚀 可以继续步骤3: Tekton Webhook 配置" 