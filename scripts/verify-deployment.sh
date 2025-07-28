#!/bin/bash

# Deployment Verification Script
# Verify complete Tekton GPU pipeline deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Tekton GPU Pipeline Deployment Verification${NC}"
echo "=================================================="

# Check Tekton Pipelines
echo -e "\n${BLUE}1. Checking Tekton Pipelines...${NC}"
if kubectl get pods -n tekton-pipelines | grep -q "tekton-pipelines-controller"; then
    echo -e "${GREEN}✅ Tekton Pipelines controller running${NC}"
else
    echo -e "${RED}❌ Tekton Pipelines controller not found${NC}"
fi

# Check Tekton Dashboard
echo -e "\n${BLUE}2. Checking Tekton Dashboard...${NC}"
if kubectl get pods -n tekton-pipelines | grep -q "tekton-dashboard"; then
    echo -e "${GREEN}✅ Tekton Dashboard running${NC}"
    
    # Get Dashboard URL
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    DASHBOARD_PORT=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "pending")
    
    if [ "$DASHBOARD_PORT" != "pending" ]; then
        echo -e "${BLUE}📊 Dashboard URL: http://${NODE_IP}:${DASHBOARD_PORT}${NC}"
    fi
else
    echo -e "${RED}❌ Tekton Dashboard not found${NC}"
fi

# Check Tekton Triggers
echo -e "\n${BLUE}3. Checking Tekton Triggers...${NC}"
if kubectl get pods -n tekton-pipelines | grep -q "tekton-triggers"; then
    echo -e "${GREEN}✅ Tekton Triggers running${NC}"
else
    echo -e "${RED}❌ Tekton Triggers not found${NC}"
fi

# Check GPU Tasks
echo -e "\n${BLUE}4. Checking GPU Tasks...${NC}"
TASK_COUNT=$(kubectl get tasks -n tekton-pipelines | grep -c "gpu-\|jupyter-\|pytest-" || echo "0")
if [ "$TASK_COUNT" -ge 4 ]; then
    echo -e "${GREEN}✅ All GPU Tasks deployed (${TASK_COUNT}/4)${NC}"
    kubectl get tasks -n tekton-pipelines | grep -E "gpu-|jupyter-|pytest-" | awk '{print "   - " $1}'
else
    echo -e "${YELLOW}⚠️  Some GPU Tasks missing (${TASK_COUNT}/4)${NC}"
fi

# Check GPU Pipeline
echo -e "\n${BLUE}5. Checking GPU Pipeline...${NC}"
if kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines &>/dev/null; then
    echo -e "${GREEN}✅ GPU Scientific Computing Pipeline deployed${NC}"
else
    echo -e "${RED}❌ GPU Pipeline not found${NC}"
fi

# Check EventListener
echo -e "\n${BLUE}6. Checking EventListener...${NC}"
if kubectl get eventlistener -n tekton-pipelines | grep -q "gpu-scientific-computing-eventlistener"; then
    echo -e "${GREEN}✅ GPU EventListener deployed${NC}"
    
    # Get EventListener URL
    EVENTLISTENER_SVC=$(kubectl get svc -n tekton-pipelines | grep gpu-scientific-computing-eventlistener | awk '{print $5}')
    if [ -n "$EVENTLISTENER_SVC" ]; then
        WEBHOOK_PORT=$(echo $EVENTLISTENER_SVC | cut -d: -f2 | cut -d/ -f1)
        echo -e "${BLUE}🔗 Webhook URL: http://${NODE_IP}:${WEBHOOK_PORT}${NC}"
    fi
else
    echo -e "${RED}❌ GPU EventListener not found${NC}"
fi

# Check Webhook Secret
echo -e "\n${BLUE}7. Checking Webhook Secret...${NC}"
if kubectl get secret github-webhook-secret -n tekton-pipelines &>/dev/null; then
    echo -e "${GREEN}✅ GitHub Webhook Secret exists${NC}"
    if [ -f "webhook-secret.txt" ]; then
        echo -e "${BLUE}🔑 Secret saved in: webhook-secret.txt${NC}"
    fi
else
    echo -e "${RED}❌ GitHub Webhook Secret not found${NC}"
fi

# Check GPU nodes
echo -e "\n${BLUE}8. Checking GPU Nodes...${NC}"
GPU_NODES=$(kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -gt 0 ]; then
    echo -e "${GREEN}✅ GPU nodes available (${GPU_NODES} nodes)${NC}"
    kubectl get nodes -l accelerator=nvidia-tesla-gpu --no-headers | awk '{print "   - " $1 " (" $2 ")"}'
else
    echo -e "${YELLOW}⚠️  No GPU nodes labeled. Run: kubectl label nodes <node-name> accelerator=nvidia-tesla-gpu${NC}"
fi

# Summary
echo -e "\n${BLUE}=== Deployment Summary ===${NC}"

# Count successful checks
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Pipeline controller
if kubectl get pods -n tekton-pipelines | grep -q "tekton-pipelines-controller"; then
    ((PASSED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Dashboard
if kubectl get pods -n tekton-pipelines | grep -q "tekton-dashboard"; then
    ((PASSED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Triggers
if kubectl get pods -n tekton-pipelines | grep -q "tekton-triggers"; then
    ((PASSED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Tasks
if [ "$TASK_COUNT" -ge 4 ]; then
    ((PASSED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Pipeline
if kubectl get pipeline gpu-scientific-computing-pipeline -n tekton-pipelines &>/dev/null; then
    ((PASSED_CHECKS++))
fi
((TOTAL_CHECKS++))

# EventListener
if kubectl get eventlistener -n tekton-pipelines | grep -q "gpu-scientific-computing-eventlistener"; then
    ((PASSED_CHECKS++))
fi
((TOTAL_CHECKS++))

echo "📊 Status: ${PASSED_CHECKS}/${TOTAL_CHECKS} components verified"

if [ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]; then
    echo -e "${GREEN}🎉 Deployment verification PASSED!${NC}"
    echo -e "${GREEN}Ready for GitHub Webhook configuration and testing.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Deployment verification completed with warnings.${NC}"
    echo -e "${YELLOW}Please review the failed checks above.${NC}"
    exit 1
fi 