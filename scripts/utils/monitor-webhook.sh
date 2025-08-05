#!/bin/bash

echo "🔍 Webhook Monitoring Script"
echo "============================"

echo -e "\n📊 Current Time: $(date)"

echo -e "\n🔧 Check EventListener Status:"
kubectl get eventlistener github-webhook-production -n tekton-pipelines

echo -e "\n📝 Latest EventListener Logs (last 10 lines):"
kubectl logs -l eventlistener=github-webhook-production -n tekton-pipelines --tail=10

echo -e "\n🚀 Check PipelineRuns:"
kubectl get pipelineruns -n tekton-pipelines | grep webhook || echo "No webhook-related PipelineRuns found"

echo -e "\n📅 Latest Events (last 5):"
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp' | tail -5

echo -e "\n✅ Monitoring Complete"