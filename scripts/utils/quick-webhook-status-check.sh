#!/bin/bash

# Tekton Webhook 快速状态检查脚本
# 用于验证03阶段配置的完整性和功能状态

echo "🔍 Tekton Webhook 快速状态检查"
echo "================================"
echo "验证时间: $(date)"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_component() {
    local name=$1
    local command=$2
    local expected=$3
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "✅ ${GREEN}$name${NC}"
        return 0
    else
        echo -e "❌ ${RED}$name${NC}"
        return 1
    fi
}

check_component_with_output() {
    local name=$1
    local command=$2
    
    result=$(eval "$command" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo -e "✅ ${GREEN}$name${NC}: $result"
        return 0
    else
        echo -e "❌ ${RED}$name${NC}"
        return 1
    fi
}

# 1. 核心组件检查
echo "1. 🔧 核心组件状态："
check_component "Webhook Secret" "kubectl get secret github-webhook-secret -n tekton-pipelines"
check_component "EventListener" "kubectl get eventlistener github-webhook-production -n tekton-pipelines"
check_component "Pipeline" "kubectl get pipeline webhook-pipeline -n tekton-pipelines"
check_component "TriggerBinding" "kubectl get triggerbinding github-webhook-triggerbinding -n tekton-pipelines"
check_component "TriggerTemplate" "kubectl get triggertemplate github-webhook-triggertemplate -n tekton-pipelines"

echo ""

# 2. Pod和服务状态
echo "2. 🚀 运行时状态："
EL_POD=$(kubectl get pods -n tekton-pipelines -l eventlistener=github-webhook-production --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$EL_POD" ]; then
    POD_STATUS=$(kubectl get pod $EL_POD -n tekton-pipelines --no-headers 2>/dev/null | awk '{print $3}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "✅ ${GREEN}EventListener Pod${NC}: $EL_POD ($POD_STATUS)"
    else
        echo -e "⚠️ ${YELLOW}EventListener Pod${NC}: $EL_POD ($POD_STATUS)"
    fi
else
    echo -e "❌ ${RED}EventListener Pod${NC}: 未找到"
fi

check_component "EventListener Service" "kubectl get svc el-github-webhook-production -n tekton-pipelines"

echo ""

# 3. 网络配置检查
echo "3. 🌐 网络配置："
if [ -f "webhook-url.txt" ]; then
    WEBHOOK_URL=$(cat webhook-url.txt)
    echo -e "✅ ${GREEN}Webhook URL文件${NC}: $WEBHOOK_URL"
    
    # 测试连接
    if curl -I "$WEBHOOK_URL" --max-time 5 >/dev/null 2>&1; then
        echo -e "✅ ${GREEN}Webhook URL连接${NC}: 可访问"
    else
        echo -e "⚠️ ${YELLOW}Webhook URL连接${NC}: 超时或无法访问（可能是外网限制）"
    fi
else
    echo -e "❌ ${RED}Webhook URL文件${NC}: webhook-url.txt 不存在"
fi

if [ -f "webhook-secret.txt" ]; then
    SECRET_LENGTH=$(cat webhook-secret.txt | wc -c)
    echo -e "✅ ${GREEN}Webhook Secret文件${NC}: 存在 (${SECRET_LENGTH}字符)"
else
    echo -e "❌ ${RED}Webhook Secret文件${NC}: webhook-secret.txt 不存在"
fi

echo ""

# 4. Ingress Controller状态
echo "4. 📡 Ingress Controller："
NGINX_POD=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$NGINX_POD" ]; then
    NGINX_STATUS=$(kubectl get pod $NGINX_POD -n ingress-nginx --no-headers 2>/dev/null | awk '{print $3}')
    echo -e "✅ ${GREEN}Nginx Controller${NC}: $NGINX_POD ($NGINX_STATUS)"
else
    echo -e "❌ ${RED}Nginx Controller${NC}: 未找到"
fi

HTTP_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
if [ -n "$HTTP_PORT" ]; then
    echo -e "✅ ${GREEN}HTTP NodePort${NC}: $HTTP_PORT"
else
    echo -e "❌ ${RED}HTTP NodePort${NC}: 未找到"
fi

echo ""

# 5. 最近的PipelineRuns
echo "5. 📊 Pipeline活动："
PIPELINE_COUNT=$(kubectl get pipelineruns -n tekton-pipelines --no-headers 2>/dev/null | wc -l)
if [ "$PIPELINE_COUNT" -gt 0 ]; then
    echo -e "✅ ${GREEN}PipelineRuns总数${NC}: $PIPELINE_COUNT"
    echo "最近的PipelineRuns："
    kubectl get pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp | tail -3
else
    echo -e "⚠️ ${YELLOW}PipelineRuns${NC}: 暂无执行记录"
fi

echo ""

# 6. 配置文件完整性
echo "6. 📁 配置文件："
for file in "webhook-url.txt" "webhook-secret.txt" "webhook-config.txt" "real-github-payload.json"; do
    if [ -f "$file" ]; then
        echo -e "✅ ${GREEN}$file${NC}: 存在"
    else
        echo -e "⚠️ ${YELLOW}$file${NC}: 不存在"
    fi
done

echo ""

# 总结
echo "================================"
echo "🎯 快速检查完成"
echo ""
echo "📋 下一步操作建议："
echo "   • 如果所有组件都正常，可以进入04阶段"
echo "   • 如果有问题，请参考 troubleshooting.md"
echo "   • 完整验证请运行: ./scripts/utils/verify-step3-webhook-configuration.sh"
echo ""
echo "📚 相关文档："
echo "   • 详细配置: docs/zh/03-tekton-webhook-configuration.md"
echo "   • 故障排除: docs/zh/troubleshooting.md"
echo "   • 验证报告: 03-verification-report.md"