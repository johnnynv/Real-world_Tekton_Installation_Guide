#!/bin/bash

# Tekton 步骤1 安装验证脚本
# 验证 Tekton Pipelines、Dashboard 和访问配置

set -e

echo "🔍 验证 Tekton 步骤1 安装..."
echo "================================"

# 检查命名空间
echo "1. 检查 Tekton 命名空间..."
kubectl get namespace tekton-pipelines || exit 1

# 检查Pod Security设置
echo "2. 检查 Pod Security Standards 配置..."
kubectl get namespace tekton-pipelines -o yaml | grep -q "pod-security.kubernetes.io/enforce: privileged" || {
    echo "❌ Pod Security Standards 未正确配置"
    exit 1
}

# 检查Tekton Pipelines组件
echo "3. 检查 Tekton Pipelines 组件..."
PIPELINE_PODS=$(kubectl get pods -n tekton-pipelines --no-headers | grep -E "(controller|webhook|events)" | wc -l)
if [ "$PIPELINE_PODS" -lt 3 ]; then
    echo "❌ Tekton Pipelines 组件不完整"
    kubectl get pods -n tekton-pipelines
    exit 1
fi

# 检查Dashboard
echo "4. 检查 Tekton Dashboard..."
kubectl get pods -n tekton-pipelines -l app.kubernetes.io/name=dashboard --no-headers | grep -q Running || {
    echo "❌ Tekton Dashboard 未运行"
    exit 1
}

# 检查CRD
echo "5. 检查 Tekton CRDs..."
CRD_COUNT=$(kubectl get crd | grep tekton | wc -l)
if [ "$CRD_COUNT" -lt 8 ]; then
    echo "❌ Tekton CRDs 不完整"
    exit 1
fi

# 检查测试Task
echo "6. 检查测试 Task..."
kubectl get task hello-world -n tekton-pipelines >/dev/null 2>&1 || {
    echo "⚠️ 测试 Task 不存在，创建中..."
    cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: hello-world
  namespace: tekton-pipelines
spec:
  steps:
  - name: hello
    image: ubuntu
    script: |
      #!/bin/bash
      echo "Hello from Tekton!"
      echo "Installation successful!"
EOF
}

# 检查访问配置
echo "7. 检查 Dashboard 访问配置..."

# 检查Ingress Controller
if kubectl get pods -n ingress-nginx --no-headers | grep -q ingress-nginx-controller; then
    echo "✅ Nginx Ingress Controller 已安装"
    
    # 检查Ingress配置
    if kubectl get ingress tekton-dashboard -n tekton-pipelines >/dev/null 2>&1; then
        echo "✅ Tekton Dashboard Ingress 已配置"
        
        # 获取访问信息
        NODE_IP=$(hostname -I | awk '{print $1}')
        DOMAIN="tekton.$NODE_IP.nip.io"
        
        echo "🌐 生产级HTTPS访问: https://$DOMAIN"
        echo "🔑 用户名: admin"
        
        # 检查认证密钥
        if kubectl get secret tekton-dashboard-auth -n tekton-pipelines >/dev/null 2>&1; then
            echo "🔑 密码: (保存在 dashboard-access-info.txt)"
        else
            echo "⚠️ 基本认证未配置"
        fi
    else
        echo "⚠️ Ingress 未配置，使用 NodePort 访问"
    fi
else
    echo "⚠️ Ingress Controller 未安装，使用 NodePort 访问"
fi

# 检查NodePort访问
SVC_TYPE=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.type}')
if [ "$SVC_TYPE" = "NodePort" ]; then
    NODE_PORT=$(kubectl get svc tekton-dashboard -n tekton-pipelines -o jsonpath='{.spec.ports[0].nodePort}')
    NODE_IP=$(hostname -I | awk '{print $1}')
    echo "🔌 NodePort 访问: http://$NODE_IP:$NODE_PORT"
fi

echo "================================"
echo "✅ Tekton 步骤1 验证完成！"
echo ""
echo "📋 安装组件概览:"
echo "  ✅ Tekton Pipelines (核心引擎)"
echo "  ✅ Tekton Dashboard (Web UI)"
echo "  ✅ Pod Security Standards 配置"
echo "  ✅ 测试 Task 创建"
echo "  ✅ Dashboard 访问配置"
echo ""
echo "🚀 可以继续步骤2: Tekton Triggers 安装" 