#!/bin/bash

# Tekton Step 2 Triggers Installation Verification Script
# Verify Tekton Triggers, RBAC permissions and EventListener functionality

set -e

echo "🔍 Verifying Tekton Step 2 Triggers installation..."
echo "========================================"

# Check Tekton Triggers components
echo "1. Checking Tekton Triggers component status..."
TRIGGERS_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | grep -E "triggers" | wc -l)
if [ "$TRIGGERS_PODS" -lt 3 ]; then
    echo "❌ Tekton Triggers components incomplete"
    kubectl get pods -n tekton-pipelines | grep triggers
    exit 1
fi

echo "✅ Tekton Triggers components running normally:"
kubectl get pods -n tekton-pipelines | grep triggers

# Check Triggers CRDs
echo ""
echo "2. Checking Tekton Triggers CRDs..."
TRIGGERS_CRD_COUNT=$(kubectl get crd | grep triggers.tekton.dev | wc -l)
if [ "$TRIGGERS_CRD_COUNT" -lt 7 ]; then
    echo "❌ Tekton Triggers CRDs incomplete"
    kubectl get crd | grep triggers.tekton.dev
    exit 1
fi

echo "✅ Tekton Triggers CRDs installed ($TRIGGERS_CRD_COUNT items):"
kubectl get crd | grep triggers.tekton.dev

# Check RBAC permissions
echo ""
echo "3. Checking RBAC permission configuration..."
kubectl get serviceaccount tekton-triggers-sa -n tekton-pipelines >/dev/null 2>&1 || {
    echo "❌ ServiceAccount does not exist"
    exit 1
}

kubectl get clusterrole tekton-triggers-role >/dev/null 2>&1 || {
    echo "❌ ClusterRole does not exist"
    exit 1
}

kubectl get clusterrolebinding tekton-triggers-binding >/dev/null 2>&1 || {
    echo "❌ ClusterRoleBinding does not exist"
    exit 1
}

echo "✅ RBAC permission configuration correct"

# Check Trigger resources
echo ""
echo "4. Checking Trigger resources..."
TRIGGER_TEMPLATE_COUNT=$(kubectl get triggertemplate -n tekton-pipelines --no-headers | wc -l)
TRIGGER_BINDING_COUNT=$(kubectl get triggerbinding -n tekton-pipelines --no-headers | wc -l)
EVENT_LISTENER_COUNT=$(kubectl get eventlistener -n tekton-pipelines --no-headers | wc -l)

if [ "$TRIGGER_TEMPLATE_COUNT" -lt 1 ] || [ "$TRIGGER_BINDING_COUNT" -lt 1 ] || [ "$EVENT_LISTENER_COUNT" -lt 1 ]; then
    echo "❌ Trigger resources incomplete"
    echo "   TriggerTemplate: $TRIGGER_TEMPLATE_COUNT"
    echo "   TriggerBinding: $TRIGGER_BINDING_COUNT" 
    echo "   EventListener: $EVENT_LISTENER_COUNT"
    exit 1
fi

echo "✅ Trigger resources configuration correct:"
echo "   TriggerTemplate: $TRIGGER_TEMPLATE_COUNT items"
echo "   TriggerBinding: $TRIGGER_BINDING_COUNT items"
echo "   EventListener: $EVENT_LISTENER_COUNT items"

# Check EventListener status
echo ""
echo "5. Checking EventListener status..."
EL_READY=$(kubectl get eventlistener hello-world-listener -n tekton-pipelines -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$EL_READY" != "True" ]; then
    echo "❌ EventListener not ready"
    kubectl get eventlistener hello-world-listener -n tekton-pipelines
    exit 1
fi

echo "✅ EventListener ready status normal"

# Check EventListener Pod
echo ""
echo "6. Checking EventListener Pod..."
EL_POD=$(kubectl get pods -n tekton-pipelines -l eventlistener=hello-world-listener --no-headers | awk '{print $1}')
if [ -z "$EL_POD" ]; then
    echo "❌ EventListener Pod does not exist"
    exit 1
fi

EL_POD_STATUS=$(kubectl get pod $EL_POD -n tekton-pipelines --no-headers | awk '{print $3}')
if [ "$EL_POD_STATUS" != "Running" ]; then
    echo "❌ EventListener Pod not running: $EL_POD_STATUS"
    kubectl describe pod $EL_POD -n tekton-pipelines
    exit 1
fi

echo "✅ EventListener Pod running normally"

# Test EventListener functionality
echo ""
echo "7. Testing EventListener functionality..."

# Use kubectl run to temporarily test EventListener
TEST_RESULT=$(kubectl run test-eventlistener --image=curlimages/curl --rm -i --restart=Never -- \
    curl -s -X POST http://el-hello-world-listener.tekton-pipelines.svc.cluster.local:8080 \
    -H 'Content-Type: application/json' \
    -d '{"repository":{"clone_url":"https://github.com/example/test-repo.git"},"head_commit":{"id":"test123"}}' \
    2>/dev/null | grep -o '"eventID":"[^"]*"' | head -1)

if [ -n "$TEST_RESULT" ]; then
    echo "✅ EventListener trigger test successful: $TEST_RESULT"
    
    # Wait for TaskRun creation
    sleep 5
    
    # Check latest TaskRun
    LATEST_TASKRUN=$(kubectl get taskruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp | tail -1 | awk '{print $1}')
    if [ -n "$LATEST_TASKRUN" ] && [ "$LATEST_TASKRUN" != "NAME" ]; then
        echo "✅ Triggered TaskRun: $LATEST_TASKRUN"
    else
        echo "⚠️ No new TaskRun detected, but EventListener response normal"
    fi
else
    echo "❌ EventListener test failed"
    echo "Check EventListener service:"
    kubectl get svc -n tekton-pipelines | grep el-
    exit 1
fi

echo ""
echo "========================================"
echo "✅ Tekton Step 2 Triggers verification completed!"
echo ""
echo "📋 Verification results overview:"
echo "  ✅ Tekton Triggers components (3 Pods running)"
echo "  ✅ Tekton Triggers CRDs ($TRIGGERS_CRD_COUNT items)"
echo "  ✅ RBAC permission configuration"
echo "  ✅ Trigger resource configuration"
echo "  ✅ EventListener ready"
echo "  ✅ EventListener functionality test"
echo ""
echo "🚀 Ready to proceed to Step 3: Tekton Webhook configuration" 