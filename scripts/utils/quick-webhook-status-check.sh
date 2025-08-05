#!/bin/bash

# Tekton Webhook Quick Status Check Script
# Used to verify the completeness and functional status of step 03 configuration

echo "🔍 Tekton Webhook Quick Status Check"
echo "==================================="
echo "Verification time: $(date)"
echo ""

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check functions
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

# 1. Core component check
echo "1. 🔧 Core component status:"
check_component "Webhook Secret" "kubectl get secret github-webhook-secret -n tekton-pipelines"
check_component "EventListener" "kubectl get eventlistener github-webhook-production -n tekton-pipelines"
check_component "Pipeline" "kubectl get pipeline webhook-pipeline -n tekton-pipelines"
check_component "TriggerBinding" "kubectl get triggerbinding github-webhook-triggerbinding -n tekton-pipelines"
check_component "TriggerTemplate" "kubectl get triggertemplate github-webhook-triggertemplate -n tekton-pipelines"

echo ""

# 2. Pod and service status
echo "2. 🚀 Runtime status:"
EL_POD=$(kubectl get pods -n tekton-pipelines -l eventlistener=github-webhook-production --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$EL_POD" ]; then
    POD_STATUS=$(kubectl get pod $EL_POD -n tekton-pipelines --no-headers 2>/dev/null | awk '{print $3}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "✅ ${GREEN}EventListener Pod${NC}: $EL_POD ($POD_STATUS)"
    else
        echo -e "⚠️ ${YELLOW}EventListener Pod${NC}: $EL_POD ($POD_STATUS)"
    fi
else
    echo -e "❌ ${RED}EventListener Pod${NC}: Not found"
fi

check_component "EventListener Service" "kubectl get svc el-github-webhook-production -n tekton-pipelines"

echo ""

# 3. Network configuration check
echo "3. 🌐 Network configuration:"
if [ -f "webhook-url.txt" ]; then
    WEBHOOK_URL=$(cat webhook-url.txt)
    echo -e "✅ ${GREEN}Webhook URL file${NC}: $WEBHOOK_URL"
    
    # Test connection
    if curl -I "$WEBHOOK_URL" --max-time 5 >/dev/null 2>&1; then
        echo -e "✅ ${GREEN}Webhook URL connection${NC}: Accessible"
    else
        echo -e "⚠️ ${YELLOW}Webhook URL connection${NC}: Timeout or inaccessible (may be external network restriction)"
    fi
else
    echo -e "❌ ${RED}Webhook URL file${NC}: webhook-url.txt does not exist"
fi

if [ -f "webhook-secret.txt" ]; then
    SECRET_LENGTH=$(cat webhook-secret.txt | wc -c)
    echo -e "✅ ${GREEN}Webhook Secret file${NC}: Exists (${SECRET_LENGTH} characters)"
else
    echo -e "❌ ${RED}Webhook Secret file${NC}: webhook-secret.txt does not exist"
fi

echo ""

# 4. Ingress Controller status
echo "4. 📡 Ingress Controller:"
NGINX_POD=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$NGINX_POD" ]; then
    NGINX_STATUS=$(kubectl get pod $NGINX_POD -n ingress-nginx --no-headers 2>/dev/null | awk '{print $3}')
    echo -e "✅ ${GREEN}Nginx Controller${NC}: $NGINX_POD ($NGINX_STATUS)"
else
    echo -e "❌ ${RED}Nginx Controller${NC}: Not found"
fi

HTTP_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
if [ -n "$HTTP_PORT" ]; then
    echo -e "✅ ${GREEN}HTTP NodePort${NC}: $HTTP_PORT"
else
    echo -e "❌ ${RED}HTTP NodePort${NC}: Not found"
fi

echo ""

# 5. Recent PipelineRuns
echo "5. 📊 Pipeline activity:"
PIPELINE_COUNT=$(kubectl get pipelineruns -n tekton-pipelines --no-headers 2>/dev/null | wc -l)
if [ "$PIPELINE_COUNT" -gt 0 ]; then
    echo -e "✅ ${GREEN}Total PipelineRuns${NC}: $PIPELINE_COUNT"
    echo "Recent PipelineRuns:"
    kubectl get pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp | tail -3
else
    echo -e "⚠️ ${YELLOW}PipelineRuns${NC}: No execution records"
fi

echo ""

# 6. Configuration file completeness
echo "6. 📁 Configuration files:"
for file in "webhook-url.txt" "webhook-secret.txt" "webhook-config.txt" "real-github-payload.json"; do
    if [ -f "$file" ]; then
        echo -e "✅ ${GREEN}$file${NC}: Exists"
    else
        echo -e "⚠️ ${YELLOW}$file${NC}: Does not exist"
    fi
done

echo ""

# Summary
echo "================================"
echo "🎯 Quick check completed"
echo ""
echo "📋 Next step recommendations:"
echo "   • If all components are normal, you can proceed to step 04"
echo "   • If there are issues, please refer to troubleshooting.md"
echo "   • For complete verification run: ./scripts/utils/verify-step3-webhook-configuration.sh"
echo ""
echo "📚 Related documentation:"
echo "   • Detailed configuration: docs/en/03-tekton-webhook-configuration.md"
echo "   • Troubleshooting: docs/en/troubleshooting.md"
echo "   • Verification report: 03-verification-report.md"