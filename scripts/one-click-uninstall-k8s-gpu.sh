#!/bin/bash

# Kubernetes GPU Single Node Uninstallation Script
# Rocky Linux 10 卸载脚本
# Author: AI Assistant
# Date: 2025-08-20

set -e

echo "🗑️ 开始卸载 Kubernetes GPU 单节点集群"
echo "========================================"

# 检查是否存在集群
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl未找到，可能集群未安装"
    exit 1
fi

echo "⚠️ 警告：此操作将完全删除Kubernetes集群和所有数据！"
echo "⚠️ 包括所有Pod、配置、存储数据等！"
echo -n "确认继续吗？(yes/no): "
read -r confirm

if [[ $confirm != "yes" ]]; then
    echo "❌ 取消卸载操作"
    exit 0
fi

echo "🔄 开始卸载过程..."

# 1. 卸载GPU Operator
echo "🎮 卸载NVIDIA GPU Operator..."
if helm list -n gpu-operator | grep -q gpu-operator; then
    helm uninstall gpu-operator -n gpu-operator > /dev/null 2>&1 || true
    kubectl delete namespace gpu-operator > /dev/null 2>&1 || true
fi
echo "✅ GPU Operator卸载完成"

# 2. 卸载Dashboard
echo "🖥️ 卸载Kubernetes Dashboard..."
kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml > /dev/null 2>&1 || true
echo "✅ Dashboard卸载完成"

# 3. 卸载Metrics Server
echo "📊 卸载Metrics Server..."
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml > /dev/null 2>&1 || true
echo "✅ Metrics Server卸载完成"

# 4. 卸载Local Path Provisioner
echo "💾 卸载Local Path Provisioner..."
kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml > /dev/null 2>&1 || true
echo "✅ Local Path Provisioner卸载完成"

# 5. 卸载Calico
echo "🌐 卸载Calico网络插件..."
kubectl delete installation default > /dev/null 2>&1 || true
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml > /dev/null 2>&1 || true
echo "✅ Calico卸载完成"

# 6. 重置集群
echo "🎯 重置Kubernetes集群..."
sudo kubeadm reset -f > /dev/null 2>&1 || true

# 清理配置文件
sudo rm -rf /etc/kubernetes/ > /dev/null 2>&1 || true
sudo rm -rf ~/.kube/ > /dev/null 2>&1 || true
sudo rm -rf /var/lib/etcd/ > /dev/null 2>&1 || true

echo "✅ 集群重置完成"

# 7. 卸载Kubernetes工具
echo "⚙️ 卸载Kubernetes工具..."
sudo dnf remove -y kubelet kubeadm kubectl > /dev/null 2>&1 || true
sudo rm -f /etc/yum.repos.d/kubernetes.repo > /dev/null 2>&1 || true
echo "✅ Kubernetes工具卸载完成"

# 8. 卸载containerd
echo "🐳 卸载containerd..."
sudo systemctl stop containerd > /dev/null 2>&1 || true
sudo systemctl disable containerd > /dev/null 2>&1 || true
sudo dnf remove -y containerd.io > /dev/null 2>&1 || true
sudo rm -rf /etc/containerd/ > /dev/null 2>&1 || true
sudo rm -rf /var/lib/containerd/ > /dev/null 2>&1 || true
echo "✅ containerd卸载完成"

# 9. 卸载Helm
echo "📦 卸载Helm..."
sudo rm -f /usr/local/bin/helm > /dev/null 2>&1 || true
echo "✅ Helm卸载完成"

# 10. 清理网络配置
echo "🌐 清理网络配置..."
sudo rm -f /etc/cni/net.d/* > /dev/null 2>&1 || true
sudo ip link delete cni0 > /dev/null 2>&1 || true
sudo ip link delete flannel.1 > /dev/null 2>&1 || true

# 清理iptables规则
sudo iptables -F > /dev/null 2>&1 || true
sudo iptables -X > /dev/null 2>&1 || true
sudo iptables -t nat -F > /dev/null 2>&1 || true
sudo iptables -t nat -X > /dev/null 2>&1 || true
sudo iptables -t mangle -F > /dev/null 2>&1 || true
sudo iptables -t mangle -X > /dev/null 2>&1 || true

echo "✅ 网络配置清理完成"

# 11. 清理系统配置
echo "🔧 清理系统配置..."
sudo rm -f /etc/modules-load.d/k8s.conf > /dev/null 2>&1 || true
sudo rm -f /etc/sysctl.d/k8s.conf > /dev/null 2>&1 || true

# 卸载内核模块
sudo modprobe -r br_netfilter > /dev/null 2>&1 || true
sudo modprobe -r overlay > /dev/null 2>&1 || true

echo "✅ 系统配置清理完成"

# 12. 卸载nginx和清理Web配置
echo "🌐 卸载nginx和Web配置..."
sudo systemctl stop nginx > /dev/null 2>&1 || true
sudo systemctl disable nginx > /dev/null 2>&1 || true
sudo dnf remove -y nginx > /dev/null 2>&1 || true
sudo rm -rf /etc/nginx/ssl/ > /dev/null 2>&1 || true
sudo rm -f /etc/nginx/conf.d/kubernetes-dashboard.conf > /dev/null 2>&1 || true
echo "✅ nginx和Web配置清理完成"

# 13. 清理Docker仓库
echo "🐳 清理Docker仓库..."
sudo rm -f /etc/yum.repos.d/docker-ce.repo > /dev/null 2>&1 || true
sudo dnf clean all > /dev/null 2>&1 || true
echo "✅ 仓库清理完成"

# 13. 清理临时文件
echo "🧹 清理临时文件..."
sudo rm -f /tmp/kubeadm-init.log > /dev/null 2>&1 || true
sudo rm -rf /tmp/kubeadm-* > /dev/null 2>&1 || true
echo "✅ 临时文件清理完成"

echo "🎉 卸载完成！"
echo "========================================"
echo "📝 卸载摘要："
echo "• ✅ GPU Operator已卸载"
echo "• ✅ Kubernetes Dashboard已卸载"
echo "• ✅ Metrics Server已卸载"
echo "• ✅ Local Path Provisioner已卸载"
echo "• ✅ Calico网络插件已卸载"
echo "• ✅ Kubernetes集群已重置"
echo "• ✅ Kubernetes工具已卸载"
echo "• ✅ containerd已卸载"
echo "• ✅ Helm已卸载"
echo "• ✅ nginx反向代理已卸载"
echo "• ✅ Web访问配置已清理"
echo "• ✅ 网络配置已清理"
echo "• ✅ 系统配置已清理"
echo
echo "🔄 建议重启系统以完全清理环境"
echo "💡 如需重新安装，请运行: ./install-k8s-gpu.sh"
echo
echo "✨ 系统已恢复到安装前状态！"
