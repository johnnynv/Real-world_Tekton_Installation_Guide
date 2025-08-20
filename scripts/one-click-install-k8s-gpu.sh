#!/bin/bash

# Kubernetes GPU Single Node Installation Script
# Rocky Linux 10 + kubeadm + containerd + Calico + GPU Operator
# Author: AI Assistant
# Date: 2025-08-20

set -e

echo "🚀 开始安装 Kubernetes GPU 单节点集群"
echo "========================================"

# 检查是否为root用户
if [[ $EUID -eq 0 ]]; then
   echo "❌ 请不要以root用户运行此脚本"
   exit 1
fi

# 检查系统版本
echo "📋 检查系统环境..."
if ! grep -q "Rocky Linux" /etc/os-release; then
    echo "❌ 此脚本仅支持Rocky Linux系统"
    exit 1
fi

echo "✅ 系统环境检查通过"

# 1. 系统前置配置
echo "🔧 配置系统环境..."

# 配置内核模块
sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 配置内核参数
sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system > /dev/null 2>&1

echo "✅ 系统环境配置完成"

# 2. 安装containerd
echo "🐳 安装containerd容器运行时..."

sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf makecache > /dev/null 2>&1
sudo dnf install -y containerd.io > /dev/null 2>&1

# 配置containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl enable --now containerd > /dev/null 2>&1

echo "✅ containerd安装完成"

# 3. 安装Kubernetes工具
echo "⚙️ 安装Kubernetes工具..."

sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

sudo dnf makecache > /dev/null 2>&1
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes > /dev/null 2>&1
sudo systemctl enable kubelet > /dev/null 2>&1

echo "✅ Kubernetes工具安装完成"

# 4. 初始化集群
echo "🎯 初始化Kubernetes集群..."

sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/containerd/containerd.sock > /tmp/kubeadm-init.log 2>&1

# 配置kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 移除master污点
kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>&1

echo "✅ Kubernetes集群初始化完成"

# 5. 安装Calico网络插件
echo "🌐 安装Calico网络插件..."

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml > /dev/null 2>&1

cat <<EOF | kubectl create -f - > /dev/null 2>&1
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

kubectl wait --for=condition=Ready --timeout=300s installation/default > /dev/null 2>&1

echo "✅ Calico网络插件安装完成"

# 6. 安装Local Path Provisioner
echo "💾 安装Local Path Provisioner存储..."

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml > /dev/null 2>&1
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' > /dev/null 2>&1

echo "✅ Local Path Provisioner安装完成"

# 7. 安装Metrics Server
echo "📊 安装Metrics Server..."

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml > /dev/null 2>&1

kubectl patch deployment metrics-server -n kube-system --patch='
spec:
  template:
    spec:
      containers:
      - name: metrics-server
        args:
        - --cert-dir=/tmp
        - --secure-port=10250
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
        - --kubelet-insecure-tls
' > /dev/null 2>&1

echo "✅ Metrics Server安装完成"

# 8. 安装Kubernetes Dashboard
echo "🖥️ 安装Kubernetes Dashboard..."

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml > /dev/null 2>&1

# 创建管理员用户
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

echo "✅ Kubernetes Dashboard安装完成"

# 9. 安装Helm
echo "📦 安装Helm..."

curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1

echo "✅ Helm安装完成"

# 10. 安装GPU Operator
echo "🎮 安装NVIDIA GPU Operator..."

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia > /dev/null 2>&1
helm repo update > /dev/null 2>&1

helm install --wait gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false > /dev/null 2>&1

echo "✅ NVIDIA GPU Operator安装完成"

# 等待所有组件启动
echo "⏳ 等待所有组件启动完成..."
sleep 60

# 验证安装
echo "🔍 验证安装结果..."

echo "📋 集群状态："
kubectl get nodes

echo
echo "🎮 GPU资源："
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu

echo
echo "🚀 安装完成！"
echo "========================================"
echo "📊 Web访问信息："
echo "• Kubernetes Dashboard: https://dashboard.${NODE_IP}.nip.io"
echo "• GPU监控指标: http://gpu-metrics.${NODE_IP}.nip.io/metrics"
echo "• 获取访问Token: kubectl -n kubernetes-dashboard create token admin-user"
echo
echo "🔧 本地端口转发（备选）："
echo "• Dashboard: kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443"
echo "• GPU监控: kubectl port-forward -n gpu-operator service/nvidia-dcgm-exporter 9400:9400"
echo
echo "📝 重要文件："
echo "• kubeconfig: ~/.kube/config"
echo "• 安装日志: /tmp/kubeadm-init.log"
echo "• nginx配置: /etc/nginx/conf.d/kubernetes-dashboard.conf"
echo
# 配置Web访问
echo "🌐 配置Web访问..."

# 创建Dashboard NodePort服务
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-nodeport
  namespace: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
spec:
  type: NodePort
  ports:
  - port: 443
    targetPort: 8443
    nodePort: 30443
    protocol: TCP
    name: https
  selector:
    k8s-app: kubernetes-dashboard
EOF

# 创建DCGM Exporter NodePort服务
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: nvidia-dcgm-exporter-nodeport
  namespace: gpu-operator
  labels:
    app: nvidia-dcgm-exporter
spec:
  type: NodePort
  ports:
  - port: 9400
    targetPort: 9400
    nodePort: 30400
    protocol: TCP
    name: metrics
  selector:
    app: nvidia-dcgm-exporter
EOF

# 安装和配置nginx
sudo dnf install -y nginx > /dev/null 2>&1

# 创建SSL证书
NODE_IP=$(hostname -I | awk '{print $1}')
sudo mkdir -p /etc/nginx/ssl > /dev/null 2>&1
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/dashboard.key \
  -out /etc/nginx/ssl/dashboard.crt \
  -subj "/C=CN/ST=State/L=City/O=Organization/CN=dashboard.${NODE_IP}.nip.io" > /dev/null 2>&1

# 配置nginx
sudo bash -c "cat > /etc/nginx/conf.d/kubernetes-dashboard.conf << 'EOF'
server {
    listen 443 ssl;
    server_name dashboard.${NODE_IP}.nip.io;

    ssl_certificate /etc/nginx/ssl/dashboard.crt;
    ssl_certificate_key /etc/nginx/ssl/dashboard.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass https://127.0.0.1:30443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify off;
    }
}

server {
    listen 80;
    server_name dashboard.${NODE_IP}.nip.io;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 80;
    server_name gpu-metrics.${NODE_IP}.nip.io;

    location / {
        proxy_pass http://127.0.0.1:30400;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF"

# 启动nginx
sudo systemctl enable --now nginx > /dev/null 2>&1

echo "✅ Web访问配置完成"

echo "🎉 Kubernetes GPU集群安装成功！"
