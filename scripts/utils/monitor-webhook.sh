#!/bin/bash

echo "🔍 Webhook 监控脚本"
echo "=================="

echo -e "\n📊 当前时间: $(date)"

echo -e "\n🔧 检查EventListener状态:"
kubectl get eventlistener github-webhook-production -n tekton-pipelines

echo -e "\n📝 最新EventListener日志 (最后10行):"
kubectl logs -l eventlistener=github-webhook-production -n tekton-pipelines --tail=10

echo -e "\n🚀 检查PipelineRuns:"
kubectl get pipelineruns -n tekton-pipelines | grep webhook || echo "暂无webhook相关的PipelineRun"

echo -e "\n📅 最新事件 (最后5个):"
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp' | tail -5

echo -e "\n✅ 监控完成"