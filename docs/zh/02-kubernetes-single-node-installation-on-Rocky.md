# Rocky Linux 10 单节点 Kubernetes 集群安装指南

本指南详细介绍如何在 Rocky Linux 10 系统上安装单节点 Kubernetes 集群，支持 GPU 工作负载。

## 📋 技术方案

- **Kubernetes**: kubeadm v1.31.12
- **容器运行时**: containerd v1.7.27
- **网络插件**: Calico v3.29.2
- **存储**: Local Path Provisioner v0.0.30
- **监控**: Metrics Server + NVIDIA DCGM Exporter
- **仪表板**: Kubernetes Dashboard v2.7.0
- **GPU支持**: NVIDIA GPU Operator
- **包管理**: Helm v3.18.5

## 🏁 步骤1：系统环境检查

```bash
# 检查操作系统版本
cat /etc/os-release
# 预期输出：Rocky Linux 10.0 (Red Quartz)

# 检查硬件资源
free -h
nproc
df -h /

# 检查网络和主机名
hostname
hostname -I

# 检查防火墙状态
systemctl status firewalld
# 预期状态：inactive (disabled)

# 检查SELinux状态
getenforce
# 预期输出：Disabled

# 检查swap状态
swapon --show
free -h
# 预期：Swap为0B (已关闭)
```

**验证结果**：
- ✅ Rocky Linux 10.0 系统
- ✅ 内存 502GB，CPU 32核，磁盘 3TB
- ✅ 防火墙已关闭
- ✅ SELinux已禁用
- ✅ Swap已关闭

## 🔧 步骤2：系统前置配置

### 配置内核模块

```bash
# 配置需要的内核模块
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# 加载内核模块
sudo modprobe overlay
sudo modprobe br_netfilter

# 验证模块加载
lsmod | grep -E "(overlay|br_netfilter)"
```

### 配置内核参数

```bash
# 配置网络参数
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 应用配置
sudo sysctl --system

# 验证关键参数
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

**验证结果**：
- ✅ overlay 和 br_netfilter 模块已加载
- ✅ 网络转发参数已启用

## 🐳 步骤3：安装containerd容器运行时

### 添加Docker仓库

```bash
# 添加Docker仓库（包含containerd）
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 更新缓存
sudo dnf makecache

# 搜索containerd
sudo dnf search containerd
```

### 安装containerd

```bash
# 安装containerd.io
sudo dnf install -y containerd.io

# 生成默认配置
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# 配置systemd cgroup驱动
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# 验证配置
grep -n "SystemdCgroup" /etc/containerd/config.toml
```

### 启动containerd服务

```bash
# 启动并启用服务
sudo systemctl enable --now containerd

# 验证状态
systemctl status containerd --no-pager
```

**验证结果**：
- ✅ containerd v1.7.27 安装成功
- ✅ systemd cgroup 驱动已配置
- ✅ 服务运行正常

## ⚙️ 步骤4：安装Kubernetes工具

### 添加Kubernetes仓库

```bash
# 添加Kubernetes官方仓库
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
```

### 安装Kubernetes组件

```bash
# 更新仓库缓存
sudo dnf makecache

# 安装kubeadm、kubelet、kubectl
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# 启用kubelet服务
sudo systemctl enable kubelet

# 验证版本
kubeadm version
kubelet --version
kubectl version --client
```

**验证结果**：
- ✅ kubeadm v1.31.12
- ✅ kubelet v1.31.12
- ✅ kubectl v1.31.12

## 🎯 步骤5：初始化Kubernetes集群

### 集群初始化

```bash
# 初始化集群
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/containerd/containerd.sock

# 配置kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 移除master节点污点（单节点集群）
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 验证集群状态
kubectl get nodes
kubectl get pods -A
```

**验证结果**：
- ✅ 集群初始化成功
- ✅ 节点状态为 NotReady（需要网络插件）
- ✅ 控制平面组件运行正常

## 🌐 步骤6：安装Calico网络插件

### 安装Tigera Operator

```bash
# 安装Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml
```

### 配置Calico安装

```bash
# 创建Calico安装配置
cat <<EOF | kubectl create -f -
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

# 等待安装完成
kubectl wait --for=condition=Ready --timeout=300s installation/default

# 验证安装
kubectl get pods -n calico-system
kubectl get nodes
```

**验证结果**：
- ✅ Calico网络插件安装成功
- ✅ 节点状态变为 Ready
- ✅ 网络连通性正常

## 💾 步骤7：安装Local Path Provisioner存储

### 安装存储provisioner

```bash
# 安装Local Path Provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# 设置为默认存储类
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 验证安装
kubectl get storageclass
kubectl get pods -n local-path-storage
```

**验证结果**：
- ✅ local-path 设为默认存储类
- ✅ provisioner 运行正常

## 📊 步骤8：安装Metrics Server监控

### 安装Metrics Server

```bash
# 安装Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 修复单节点集群TLS问题
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
'

# 验证功能
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl top nodes
```

**验证结果**：
- ✅ Metrics Server运行正常
- ✅ 能够获取节点资源指标

## 🖥️ 步骤9：安装Kubernetes Dashboard

### 安装Dashboard

```bash
# 安装Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# 创建管理员用户
cat <<EOF | kubectl apply -f -
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

# 验证安装
kubectl get pods -n kubernetes-dashboard
```

### 访问Dashboard

```bash
# 获取访问Token
kubectl -n kubernetes-dashboard create token admin-user

# 启动端口转发
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443
```

**访问信息**：
- **URL**: https://localhost:8443
- **Token**: 通过上述命令获取
- **用户**: admin-user

## 📦 步骤10：安装Helm包管理器

```bash
# 安装Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 验证版本
helm version
```

**验证结果**：
- ✅ Helm v3.18.5 安装成功

## 🎮 步骤11：安装NVIDIA GPU Operator

### 添加NVIDIA Helm仓库

```bash
# 添加NVIDIA仓库
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### 安装GPU Operator

```bash
# 安装GPU Operator（禁用驱动安装）
helm install --wait gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false

# 验证安装
kubectl get pods -n gpu-operator
```

### 验证GPU资源

```bash
# 检查GPU资源
kubectl describe node | grep -A 5 -B 5 nvidia.com/gpu

# 检查GPU分配
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
```

**验证结果**：
- ✅ 识别到4个GPU设备
- ✅ GPU Operator所有组件运行正常
- ✅ NVIDIA DCGM Exporter自动安装

## 📈 步骤12：验证DCGM监控指标

### 访问GPU指标

```bash
# 端口转发DCGM Exporter
kubectl port-forward -n gpu-operator service/nvidia-dcgm-exporter 9400:9400 &

# 测试指标获取
curl -s http://localhost:9400/metrics | grep -E "(DCGM_FI_DEV_GPU_UTIL|DCGM_FI_DEV_MEM_COPY_UTIL)" | head -5
```

**DCGM指标访问**：
- **URL**: http://localhost:9400/metrics
- **主要指标**: GPU利用率、内存使用、温度等

## ✅ 步骤13：完整系统验证

### 集群状态验证

```bash
echo "🔍 完整系统验证"
echo "========================="

# 1. 节点状态
echo "1. 节点状态："
kubectl get nodes

# 2. 所有Pod状态
echo "2. 关键Pod状态："
kubectl get pods -A --field-selector=status.phase!=Succeeded | grep -v Completed

# 3. GPU资源
echo "3. GPU资源分配："
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu

# 4. 存储类
echo "4. 存储类："
kubectl get storageclass

# 5. 网络插件
echo "5. 网络插件："
kubectl get pods -n calico-system

echo "========================="
echo "🎉 系统验证完成！"
```

## 🚀 访问信息汇总

### Dashboard和监控访问

#### 🌐 **通过nip.io域名访问（推荐）**

##### Dashboard访问
```bash
# 创建NodePort服务
cat <<EOF | kubectl apply -f -
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

# 安装nginx反向代理
sudo dnf install -y nginx

# 创建SSL证书
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/dashboard.key \
  -out /etc/nginx/ssl/dashboard.crt \
  -subj "/C=CN/ST=State/L=City/O=Organization/CN=dashboard.$(hostname -I | awk '{print $1}').nip.io"

# 配置nginx
sudo bash -c 'cat > /etc/nginx/conf.d/kubernetes-dashboard.conf << "EOF"
server {
    listen 443 ssl;
    server_name dashboard.$(hostname -I | awk "{print $1}").nip.io;

    ssl_certificate /etc/nginx/ssl/dashboard.crt;
    ssl_certificate_key /etc/nginx/ssl/dashboard.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass https://127.0.0.1:30443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }
}

server {
    listen 80;
    server_name dashboard.$(hostname -I | awk "{print $1}").nip.io;
    return 301 https://$server_name$request_uri;
}

# GPU监控服务
server {
    listen 80;
    server_name gpu-metrics.$(hostname -I | awk "{print $1}").nip.io;

    location / {
        proxy_pass http://127.0.0.1:30400;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF'

# 启动nginx
sudo systemctl enable --now nginx

# 获取访问Token
kubectl -n kubernetes-dashboard create token admin-user
```

##### GPU监控访问
```bash
# 创建DCGM Exporter NodePort服务
cat <<EOF | kubectl apply -f -
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
```

#### 📱 **访问链接**

- **Kubernetes Dashboard**: https://dashboard.10.78.14.61.nip.io
- **GPU监控指标**: http://gpu-metrics.10.78.14.61.nip.io/metrics  
- **Token获取**: `kubectl -n kubernetes-dashboard create token admin-user`

#### 🔧 **本地端口转发访问（备选）**
```bash
# Dashboard端口转发
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443 &

# GPU监控端口转发  
kubectl port-forward -n gpu-operator service/nvidia-dcgm-exporter 9400:9400 &
```

- **Dashboard URL**: https://localhost:8443
- **DCGM指标URL**: http://localhost:9400/metrics

## 📋 安装结果摘要

### ✅ 成功安装的组件
1. **Kubernetes集群**: v1.31.12 单节点集群
2. **容器运行时**: containerd v1.7.27
3. **网络插件**: Calico v3.29.2
4. **存储**: Local Path Provisioner（默认存储类）
5. **监控**: Metrics Server + NVIDIA DCGM Exporter
6. **仪表板**: Kubernetes Dashboard v2.7.0
7. **GPU支持**: NVIDIA GPU Operator
8. **包管理**: Helm v3.18.5

### 📊 集群规格
- **节点数量**: 1个（control-plane + worker）
- **GPU设备**: 4x NVIDIA Graphics Device
- **总显存**: 716GB（4x179GB）
- **计算能力**: 10.0（支持最新CUDA特性）
- **网络**: Calico VXLAN，Pod CIDR 192.168.0.0/16
- **存储**: 本地路径存储，支持动态分配

### 🎯 后续集成准备
该集群已为以下工作负载做好准备：
- **Tekton Pipeline**: GPU加速的CI/CD工作流
- **科学计算**: PyTorch、TensorFlow、RAPIDS等
- **机器学习**: 模型训练和推理工作负载
- **容器化应用**: 支持GPU的容器应用

## 🛠️ 一键安装脚本

### 快速安装
```bash
# 下载并运行安装脚本
curl -O https://raw.githubusercontent.com/your-repo/scripts/install-k8s-gpu.sh
chmod +x install-k8s-gpu.sh
./install-k8s-gpu.sh
```

### 完整卸载
```bash
# 下载并运行卸载脚本
curl -O https://raw.githubusercontent.com/your-repo/scripts/uninstall-k8s-gpu.sh
chmod +x uninstall-k8s-gpu.sh
./uninstall-k8s-gpu.sh
```

## 📚 下一步

集群安装完成后，您可以继续：
1. [Tekton 核心组件安装](04-tekton-installation.md)
2. [Tekton Triggers 配置](05-tekton-triggers-setup.md)
3. [GPU Pipeline 部署](07-gpu-pipeline-deployment.md)

## 🔧 故障排除

### 常见问题
1. **节点NotReady**: 检查网络插件安装状态
2. **Pod拉取镜像失败**: 检查网络连接和DNS配置
3. **GPU资源未识别**: 验证GPU Operator和驱动状态
4. **Dashboard无法访问**: 检查端口转发和Token有效性

### 诊断命令
```bash
# 节点诊断
kubectl describe nodes

# Pod诊断
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>

# GPU诊断
kubectl get pods -n gpu-operator
kubectl logs -n gpu-operator <gpu-operator-pod>

# 网络诊断
kubectl get pods -n calico-system
kubectl logs -n calico-system <calico-pod>
```

## 📖 参考资料

- [Kubernetes官方文档](https://kubernetes.io/docs/)
- [Calico网络插件](https://docs.tigera.io/calico/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
- [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/)
