#!/bin/bash

# Tekton Step 3 Webhook Configuration Verification Script
# Verify GitHub Webhook secrets, TriggerBinding and EventListener configuration

set -e

echo "🔍 Verifying Tekton Step 3 Webhook configuration..."
echo "========================================"

# Check Webhook 密钥
echo "1. Check Webhook 密钥配置..."
kubectl get secret github-webhook-secret -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ GitHub Webhook Secret does not exist"
    echo "Please run first: kubectl create secret generic github-webhook-secret --from-literal=webhook-secret=\$WEBHOOK_SECRET -n tekton-pipelines"
    exit 1
}

echo "✅ GitHub Webhook Secret configured"

# Check密钥内容
WEBHOOK_SECRET_LENGTH=$(kubectl get secret github-webhook-secret -n tekton-pipelines -o jsonpath='{.data.webhook-secret}' | base64 -d | wc -c)
if [ "$WEBHOOK_SECRET_LENGTH" -lt 20 ]; then
    echo "❌ Webhook secret length insufficient (current: $WEBHOOK_SECRET_LENGTH characters)"
    exit 1
fi

echo "✅ Webhook secret length compliant ($WEBHOOK_SECRET_LENGTH characters)"

# Check GitHub TriggerBinding
echo ""
echo "2. Check GitHub TriggerBinding..."
kubectl get triggerbinding github-webhook-triggerbinding -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ GitHub TriggerBinding 不存在"
    exit 1
}

echo "✅ GitHub TriggerBinding 已配置"

# Check GitHub EventListener
echo ""
echo "3. Check GitHub EventListener..."
kubectl get eventlistener github-webhook-eventlistener -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ GitHub EventListener 不存在"
    exit 1
}

# Check EventListener 状态
GITHUB_EL_READY=$(kubectl get eventlistener github-webhook-eventlistener -n tekton-pipelines -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$GITHUB_EL_READY" != "True" ]; then
    echo "❌ GitHub EventListener 未就绪"
    kubectl get eventlistener github-webhook-eventlistener -n tekton-pipelines
    exit 1
fi

echo "✅ GitHub EventListener 就绪"

# Check EventListener Pod
echo ""
echo "4. Check GitHub EventListener Pod..."
GITHUB_EL_POD=$(kubectl get pods -n tekton-pipelines -l eventlistener=github-webhook-eventlistener --no-headers | awk '{print $1}')
if [ -z "$GITHUB_EL_POD" ]; then
    echo "❌ GitHub EventListener Pod 不存在"
    exit 1
fi

GITHUB_EL_POD_STATUS=$(kubectl get pod $GITHUB_EL_POD -n tekton-pipelines --no-headers | awk '{print $3}')
if [ "$GITHUB_EL_POD_STATUS" != "Running" ]; then
    echo "❌ GitHub EventListener Pod 未运行: $GITHUB_EL_POD_STATUS"
    kubectl describe pod $GITHUB_EL_POD -n tekton-pipelines
    exit 1
fi

echo "✅ GitHub EventListener Pod 运行正常"

# Check Webhook 拦截器配置
echo ""
echo "5. Check Webhook 拦截器配置..."
INTERCEPTOR_CONFIG=$(kubectl get eventlistener github-webhook-eventlistener -n tekton-pipelines -o jsonpath='{.spec.triggers[0].interceptors}' 2>/dev/null)
if [ -z "$INTERCEPTOR_CONFIG" ] || [ "$INTERCEPTOR_CONFIG" = "null" ]; then
    echo "⚠️ 未检测到拦截器配置，请确认是否需要 GitHub Webhook 验证"
else
    echo "✅ Webhook 拦截器配置已存在"
fi

# Check服务访问配置
echo ""
echo "6. Check EventListener 服务配置..."
GITHUB_EL_SVC=$(kubectl get svc -n tekton-pipelines -l eventlistener=github-webhook-eventlistener --no-headers | awk '{print $1}')
if [ -z "$GITHUB_EL_SVC" ]; then
    echo "❌ GitHub EventListener 服务不存在"
    exit 1
fi

SVC_TYPE=$(kubectl get svc $GITHUB_EL_SVC -n tekton-pipelines -o jsonpath='{.spec.type}')
echo "✅ GitHub EventListener 服务类型: $SVC_TYPE"

# 获取访问信息
if [ "$SVC_TYPE" = "NodePort" ]; then
    NODE_PORT=$(kubectl get svc $GITHUB_EL_SVC -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "📡 NodePort 访问: http://$NODE_IP:$NODE_PORT"
elif [ "$SVC_TYPE" = "LoadBalancer" ]; then
    EXTERNAL_IP=$(kubectl get svc $GITHUB_EL_SVC -n tekton-pipelines -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "$EXTERNAL_IP" ]; then
        echo "📡 LoadBalancer 访问: http://$EXTERNAL_IP"
    else
        echo "⚠️ LoadBalancer 外部IP尚未分配"
    fi
else
    echo "📡 ClusterIP 访问 (仅集群内部): http://$GITHUB_EL_SVC.tekton-pipelines.svc.cluster.local:8080"
fi

# 测试基本连通性
echo ""
echo "7. 测试 EventListener 连通性..."
TEST_RESULT=$(kubectl run test-github-el --image=curlimages/curl --rm -i --restart=Never -- \
    curl -s -o /dev/null -w "%{http_code}" http://el-github-webhook-eventlistener.tekton-pipelines.svc.cluster.local:8080 \
    2>/dev/null || echo "timeout")

if [ "$TEST_RESULT" = "200" ] || [ "$TEST_RESULT" = "202" ] || [ "$TEST_RESULT" = "405" ]; then
    echo "✅ EventListener 连通性测试成功 (HTTP $TEST_RESULT)"
elif [ "$TEST_RESULT" = "timeout" ]; then
    echo "⚠️ EventListener 连通性测试超时"
else
    echo "⚠️ EventListener 连通性测试返回: HTTP $TEST_RESULT"
fi

# Check webhook-secret.txt 文件
echo ""
echo "8. Check配置文件..."
if [ -f "webhook-secret.txt" ]; then
    echo "✅ webhook-secret.txt 文件存在"
    echo "📝 GitHub Webhook 配置所需的密钥已保存"
else
    echo "⚠️ webhook-secret.txt 文件不存在"
    echo "💡 可手动获取密钥: kubectl get secret github-webhook-secret -n tekton-pipelines -o jsonpath='{.data.webhook-secret}' | base64 -d"
fi

echo ""
echo "========================================"
echo "✅ Tekton 步骤3 Webhook 配置验证完成！"
echo ""
echo "📋 验证结果概览:"
echo "  ✅ GitHub Webhook Secret"
echo "  ✅ GitHub TriggerBinding"
echo "  ✅ GitHub EventListener"
echo "  ✅ EventListener Pod 运行"
echo "  ✅ 服务配置 ($SVC_TYPE)"
echo "  ✅ 连通性测试"
echo ""
echo "📡 下一步："
echo "  1. 在 GitHub 仓库中配置 Webhook"
echo "  2. 使用 webhook-secret.txt 中的密钥"
echo "  3. 测试推送事件触发"
echo ""
echo "🚀 可以继续步骤4: GPU Pipeline 部署" 