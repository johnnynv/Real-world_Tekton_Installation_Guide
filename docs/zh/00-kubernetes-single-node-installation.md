# 00 - Kubernetes 单节点集群安装指南

## 概述

本文档提供在 Ubuntu 24.04 LTS 系统上安装单节点 Kubernetes 集群的完整指南。该安装方案采用生产级配置，包含完整的监控、存储、网络和 GPU 支持，适合开发、测试和小规模生产环境使用。

## 技术栈选择

经过技术评估，本安装采用以下技术栈：

- **容器运行时**: containerd (CNCF 毕业项目，官方推荐)
- **Kubernetes 版本**: v1.30.x (稳定版本，生产就绪)
- **网络插件**: Flannel (简单可靠，适合单节点)
- **存储**: local-path-provisioner (单节点存储解决方案)
- **入口控制器**: NGINX Ingress Controller (行业标准)
- **监控方案**: Prometheus + Grafana (完整监控生态)
- **仪表板**: Kubernetes Dashboard (官方仪表板)
- **GPU 支持**: NVIDIA GPU Operator (官方 GPU 管理方案)

## 系统要求

### 硬件要求
- **CPU**: 最少 4 核心（推荐 8 核心）
- **内存**: 最少 8GB RAM（推荐 16GB 或以上）
- **存储**: 最少 50GB 可用磁盘空间（推荐 100GB）
- **网络**: 稳定的网络连接
- **GPU**: NVIDIA GPU（可选，本环境有 4x NVIDIA A16）

### 软件要求
- Ubuntu 24.04 LTS (Noble Numbat)
- Root 或 sudo 权限
- 互联网连接

## 第一部分：系统前置条件准备

### 1.1 系统信息验证

首先验证当前系统配置：

```bash
# 检查系统版本
lsb_release -a

# 检查内核版本
uname -r

# 检查系统资源
free -h
df -h

# 检查 GPU 信息（如果有）
nvidia-smi
```

**验证方法**：
- 确认输出显示 Ubuntu 24.04
- 内核版本应为 6.x 系列
- 可用内存至少 8GB
- 根分区至少有 50GB 可用空间
- GPU 信息正常显示

### 1.2 更新系统包

```bash
# 更新包索引
sudo apt update

# 升级所有包到最新版本
sudo apt upgrade -y

# 安装必要的工具包
sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release
```

**验证方法**：
```bash
# 检查关键工具是否安装成功
which curl wget gnupg2
curl --version
```

### 1.3 配置系统参数

#### 1.3.1 禁用 Swap

Kubernetes 要求禁用 swap 以确保性能：

```bash
# 临时禁用 swap
sudo swapoff -a

# 永久禁用 swap
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

**验证方法**：
```bash
# 检查 swap 是否已禁用
free -h
# Swap 行应显示全部为 0

# 检查 fstab 配置
grep swap /etc/fstab
# swap 行应被注释掉
```

#### 1.3.2 加载必要的内核模块

```bash
# 创建内核模块配置文件
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# 立即加载模块
sudo modprobe overlay
sudo modprobe br_netfilter
```

**验证方法**：
```bash
# 检查模块是否加载成功
lsmod | grep overlay
lsmod | grep br_netfilter
```

#### 1.3.3 配置系统内核参数

```bash
# 创建 sysctl 配置文件
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 应用配置
sudo sysctl --system
```

**验证方法**：
```bash
# 检查参数是否正确设置
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables  
sysctl net.ipv4.ip_forward
# 所有值都应该为 1
```

### 1.4 配置防火墙

为 Kubernetes 组件开放必要的端口：

```bash
# 如果使用 ufw（Ubuntu 默认防火墙）
sudo ufw allow 6443/tcp    # Kubernetes API server
sudo ufw allow 2379:2380/tcp # etcd server client API
sudo ufw allow 10250/tcp   # Kubelet API
sudo ufw allow 10251/tcp   # kube-scheduler
sudo ufw allow 10252/tcp   # kube-controller-manager
sudo ufw allow 10255/tcp   # Read-only Kubelet API
sudo ufw allow 30000:32767/tcp # NodePort Services

# 允许容器网络通信
sudo ufw allow from 10.244.0.0/16  # Pod 网络（Flannel）
sudo ufw allow from 10.96.0.0/12   # Service 网络
```

**验证方法**：
```bash
# 检查防火墙规则
sudo ufw status numbered
```

## 第二部分：容器运行时安装配置

### 2.1 安装 containerd

#### 2.1.1 添加 Docker 官方仓库

```bash
# 创建 keyrings 目录
sudo mkdir -p /etc/apt/keyrings

# 添加 Docker 的官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 设置仓库
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

#### 2.1.2 安装 containerd

```bash
# 更新包索引
sudo apt update

# 安装 containerd
sudo apt install -y containerd.io

# 启动并启用 containerd 服务
sudo systemctl enable containerd
sudo systemctl start containerd
```

**验证方法**：
```bash
# 检查 containerd 版本和状态
containerd --version
sudo systemctl status containerd
```

### 2.2 配置 containerd

#### 2.2.1 生成默认配置

```bash
# 创建配置目录
sudo mkdir -p /etc/containerd

# 生成默认配置
containerd config default | sudo tee /etc/containerd/config.toml

# 备份配置文件
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
```

#### 2.2.2 配置 systemd cgroup 驱动

```bash
# 修改 systemd cgroup 配置
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

**验证方法**：
```bash
# 检查配置是否正确修改
grep -A 5 -B 5 "SystemdCgroup" /etc/containerd/config.toml
```

#### 2.2.3 重启 containerd

```bash
# 重启服务以应用新配置
sudo systemctl restart containerd

# 检查服务状态
sudo systemctl status containerd
```

**重要提示**: 如果 kubeadm init 时遇到 CRI 错误，需要重启 containerd 服务：
```bash
# 如果遇到 "container runtime is not running" 错误
sudo systemctl restart containerd

# 验证 CRI 接口是否正常
sudo crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock version
```

### 2.3 安装 CNI 插件

```bash
# 创建 CNI 目录
sudo mkdir -p /opt/cni/bin

# 下载 CNI 插件
CNI_VERSION="v1.3.0"
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz
```

**验证方法**：
```bash
# 检查 CNI 插件是否安装成功
ls -la /opt/cni/bin/
```

## 第三部分：Kubernetes 工具安装

### 3.1 安装 kubeadm, kubelet, kubectl

#### 3.1.1 添加 Kubernetes 仓库

```bash
# 添加 Kubernetes 签名密钥
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 添加 Kubernetes 仓库
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

#### 3.1.2 安装 Kubernetes 工具

```bash
# 更新包索引
sudo apt update

# 安装 Kubernetes 工具
sudo apt install -y kubelet kubeadm kubectl

# 防止自动更新
sudo apt-mark hold kubelet kubeadm kubectl
```

**验证方法**：
```bash
# 检查版本
kubeadm version
kubelet --version
kubectl version --client
```

### 3.2 配置 kubelet

```bash
# 启用 kubelet 服务
sudo systemctl enable kubelet
```

## 第四部分：初始化 Kubernetes 集群

### 4.1 创建集群配置文件

创建 kubeadm 配置文件以自定义集群参数：

```bash
cat <<EOF | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.30.0
controlPlaneEndpoint: "$(hostname -I | awk '{print $1}'):6443"
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "10.244.0.0/16"
  dnsDomain: "cluster.local"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$(hostname -I | awk '{print $1}')"
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: "systemd"
    container-runtime-endpoint: "unix:///var/run/containerd/containerd.sock"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
EOF
```

### 4.2 初始化集群

```bash
# 初始化 Kubernetes 集群
sudo kubeadm init --config=/tmp/kubeadm-config.yaml

# 记录输出的 join 命令（虽然是单节点，但建议保存）
```

**重要**: 保存输出中的 kubeadm join 命令，以备将来添加节点使用。

### 4.3 配置 kubectl

```bash
# 为当前用户配置 kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**验证方法**：
```bash
# 检查集群状态
kubectl cluster-info
kubectl get nodes
```

### 4.4 移除 master 节点污点（单节点配置）

```bash
# 允许在 master 节点上调度 Pod
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

**验证方法**：
```bash
# 检查节点状态
kubectl get nodes
# 状态应该为 Ready，但网络插件安装前可能显示 NotReady
```

## 第五部分：网络插件安装（Flannel）

### 5.1 安装 Flannel

```bash
# 下载并安装 Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**验证方法**：
```bash
# 检查 Flannel Pod 状态
kubectl get pods -n kube-flannel

# 检查节点状态（应该变为 Ready）
kubectl get nodes

# 检查所有系统 Pod 状态
kubectl get pods -A
```

### 5.2 验证网络连通性

```bash
# 创建测试 Pod
kubectl run test-pod --image=busybox --restart=Never --rm -it -- /bin/sh

# 在 Pod 内测试（在 Pod shell 中执行）
nslookup kubernetes.default.svc.cluster.local
ping -c 3 8.8.8.8
exit
```

## 第六部分：存储配置（local-path-provisioner）

### 6.1 安装 local-path-provisioner

```bash
# 安装 local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
```

**验证方法**：
```bash
# 检查存储类
kubectl get storageclass

# 检查 local-path-provisioner Pod
kubectl get pods -n local-path-storage
```

### 6.2 设置默认存储类

```bash
# 设置 local-path 为默认存储类
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**验证方法**：
```bash
# 检查默认存储类（应该看到 local-path (default)）
kubectl get storageclass
```

### 6.3 测试存储功能

```bash
# 创建测试 PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 创建使用 PVC 的测试 Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-storage-pod
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sh', '-c', 'echo "Hello Storage" > /data/test.txt && sleep 3600']
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF
```

**验证方法**：
```bash
# 检查 PVC 状态
kubectl get pvc

# 检查 Pod 状态
kubectl get pods

# 验证数据写入
kubectl exec test-storage-pod -- cat /data/test.txt

# 清理测试资源
kubectl delete pod test-storage-pod
kubectl delete pvc test-pvc
```

## 第七部分：NGINX Ingress Controller 安装

### 7.1 安装 NGINX Ingress Controller

```bash
# 安装 NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
```

**验证方法**：
```bash
# 检查 Ingress Controller Pod 状态
kubectl get pods -n ingress-nginx

# 检查服务状态
kubectl get svc -n ingress-nginx
```

### 7.2 配置 Ingress Controller 为 NodePort

```bash
# 检查 NodePort 端口
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 记录 HTTP 和 HTTPS 端口（通常是 30000+ 范围）
```

### 7.3 生成自签名证书

```bash
# 创建证书目录
mkdir -p ~/k8s-certs
cd ~/k8s-certs

# 生成私钥
openssl genrsa -out tls.key 2048

# 生成证书签名请求
openssl req -new -key tls.key -out tls.csr -subj "/CN=k8s.local/O=kubernetes"

# 生成自签名证书
openssl x509 -req -in tls.csr -signkey tls.key -out tls.crt -days 365

# 创建 TLS Secret
kubectl create secret tls k8s-local-tls --cert=tls.crt --key=tls.key -n default
```

### 7.4 测试 Ingress

```bash
# 创建测试应用
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test-app
        image: nginx:1.21
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-app-service
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
  - hosts:
    - k8s.local
    secretName: k8s-local-tls
  rules:
  - host: k8s.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app-service
            port:
              number: 80
EOF
```

**验证方法**：
```bash
# 检查 Ingress 状态
kubectl get ingress

# 添加本地 hosts 条目
echo "127.0.0.1 k8s.local" | sudo tee -a /etc/hosts

# 获取 NodePort 端口
HTTPS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

# 测试访问（忽略证书警告）
curl -k https://k8s.local:$HTTPS_PORT

# 清理测试资源
kubectl delete deployment test-app
kubectl delete service test-app-service
kubectl delete ingress test-app-ingress
```

## 第八部分：监控系统安装（Prometheus + Grafana）

### 8.1 安装 kube-prometheus-stack

```bash
# 添加 Prometheus Helm 仓库
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 添加 Prometheus 社区 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 8.2 创建监控命名空间

```bash
# 创建监控命名空间
kubectl create namespace monitoring
```

### 8.3 安装 Prometheus 和 Grafana

```bash
# 创建配置文件目录
mkdir -p configs/monitoring

# 创建 values 配置文件
cat <<EOF > configs/monitoring/prometheus-values.yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

grafana:
  adminPassword: "admin123"
  persistence:
    enabled: true
    size: 5Gi
  service:
    type: NodePort
    nodePort: 32000

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
EOF

# 安装 kube-prometheus-stack (设置 Grafana 密码为 admin123)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values configs/monitoring/prometheus-values.yaml \
  --set grafana.adminPassword=admin123
```

**验证方法**：
```bash
# 检查所有监控组件状态
kubectl get pods -n monitoring

# 检查服务
kubectl get svc -n monitoring

# 获取 Grafana 访问端口
kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}'
```

### 8.4 配置 Grafana 访问

```bash
# 获取 Grafana NodePort
GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')

echo "Grafana 访问地址: http://$(hostname -I | awk '{print $1}'):$GRAFANA_PORT"
echo "用户名: admin"
echo "密码: admin123"
```

### 8.5 验证监控数据

```bash
# 获取 Prometheus 访问端口
PROMETHEUS_PORT=$(kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.spec.ports[0].nodePort}')

echo "Prometheus 访问地址: http://$(hostname -I | awk '{print $1}'):$PROMETHEUS_PORT"
```

## 第九部分：Kubernetes Dashboard 安装

### 9.1 安装 Kubernetes Dashboard

```bash
# 安装 Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### 9.2 创建管理员用户

```bash
# 创建服务账户
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard-admin
  namespace: kubernetes-dashboard
EOF
```

### 9.3 配置 Dashboard 访问

```bash
# 修改服务类型为 NodePort
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'

# 获取访问端口
DASHBOARD_PORT=$(kubectl get svc -n kubernetes-dashboard kubernetes-dashboard -o jsonpath='{.spec.ports[0].nodePort}')

echo "Dashboard 访问地址: https://$(hostname -I | awk '{print $1}'):$DASHBOARD_PORT"
```

### 9.4 获取访问令牌

```bash
# 创建长期有效的访问令牌 (1年有效期)
kubectl create token dashboard-admin -n kubernetes-dashboard --duration=8760h

# 保存令牌到文件 (可选)
kubectl create token dashboard-admin -n kubernetes-dashboard --duration=8760h > dashboard-token.txt
```

**验证方法**：
- 使用浏览器访问 Dashboard URL
- 选择 "Token" 登录方式
- 输入获取的令牌
- 成功登录并看到集群概览

## 第十部分：GPU 支持配置（NVIDIA GPU Operator）

### 10.1 验证 GPU 驱动

```bash
# 检查 NVIDIA 驱动状态
nvidia-smi

# 检查 NVIDIA 容器工具包（如果需要安装）
which nvidia-container-runtime || echo "需要安装 nvidia-container-toolkit"
```

### 10.2 安装 NVIDIA Container Toolkit

```bash
# 添加 NVIDIA 仓库 GPG 密钥
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# 添加 NVIDIA 仓库
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 安装 nvidia-container-toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# 配置 containerd
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart containerd
```

### 10.3 安装 NVIDIA GPU Operator

```bash
# 添加 NVIDIA Helm 仓库
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 创建 GPU Operator 命名空间
kubectl create namespace gpu-operator

# 安装 GPU Operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=false \
  --set toolkit.enabled=true
```

**验证方法**：
```bash
# 检查 GPU Operator 组件状态
kubectl get pods -n gpu-operator

# 等待所有 Pod 就绪（可能需要几分钟）
kubectl wait --for=condition=Ready pod --all -n gpu-operator --timeout=600s
```

### 10.4 验证 GPU 功能

```bash
# 创建 GPU 测试 Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:11.8-base-ubuntu20.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  restartPolicy: Never
EOF

# 等待 Pod 完成
kubectl wait --for=condition=Ready pod/gpu-test --timeout=300s

# 查看 GPU 测试结果
kubectl logs gpu-test

# 清理测试 Pod
kubectl delete pod gpu-test
```

### 10.5 部署 GPU 监控

```bash
# GPU Operator 会自动部署 DCGM Exporter 用于 GPU 监控
# 检查 DCGM Exporter 状态
kubectl get pods -n gpu-operator | grep dcgm

# 检查 GPU 指标
kubectl get --raw /api/v1/nodes/$(kubectl get nodes -o name | cut -d/ -f2)/proxy/metrics | grep DCGM
```

## 第十一部分：系统验证和测试

### 11.1 全面集群状态检查

```bash
# 检查所有节点状态
kubectl get nodes -o wide

# 检查所有命名空间的 Pod 状态
kubectl get pods -A

# 检查所有服务状态
kubectl get svc -A

# 检查存储类
kubectl get storageclass

# 检查 Ingress 状态
kubectl get ingress -A
```

### 11.2 网络连通性测试

```bash
# 创建网络测试 Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: network-test
spec:
  containers:
  - name: network-test
    image: busybox
    command: ['sleep', '3600']
EOF

# 等待 Pod 就绪
kubectl wait --for=condition=Ready pod/network-test --timeout=300s

# 测试内部 DNS 解析
kubectl exec network-test -- nslookup kubernetes.default.svc.cluster.local

# 测试外部网络
kubectl exec network-test -- wget -q --spider http://www.google.com && echo "外网连通正常"

# 清理测试 Pod
kubectl delete pod network-test
```

### 11.3 存储功能测试

```bash
# 创建存储测试
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: storage-test
spec:
  containers:
  - name: storage-test
    image: busybox
    command: ['sh', '-c', 'echo "存储测试数据" > /data/test.txt && cat /data/test.txt && sleep 300']
    volumeMounts:
    - name: storage-volume
      mountPath: /data
  volumes:
  - name: storage-volume
    persistentVolumeClaim:
      claimName: storage-test-pvc
EOF

# 检查测试结果
kubectl logs storage-test

# 清理测试资源
kubectl delete pod storage-test
kubectl delete pvc storage-test-pvc
```

### 11.4 GPU 负载测试

```bash
# 创建 GPU 负载测试
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-benchmark
spec:
  template:
    spec:
      containers:
      - name: gpu-benchmark
        image: nvidia/cuda:11.8-devel-ubuntu20.04
        command: ["sh", "-c"]
        args:
        - |
          nvidia-smi
          echo "运行 GPU 基准测试..."
          # 简单的 GPU 计算测试
          echo 'import numpy as np; print("GPU 测试完成")' > test.py
          python3 test.py || echo "Python3 not available, test completed with nvidia-smi"
        resources:
          limits:
            nvidia.com/gpu: 1
      restartPolicy: Never
EOF

# 等待任务完成
kubectl wait --for=condition=Complete job/gpu-benchmark --timeout=600s

# 查看测试结果
kubectl logs job/gpu-benchmark

# 清理测试任务
kubectl delete job gpu-benchmark
```

### 11.5 监控系统验证

```bash
# 检查 Prometheus 目标状态
PROMETHEUS_PORT=$(kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.spec.ports[0].nodePort}')
echo "访问 Prometheus targets: http://$(hostname -I | awk '{print $1}'):$PROMETHEUS_PORT/targets"

# 检查 Grafana 仪表板
GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')
echo "访问 Grafana: http://$(hostname -I | awk '{print $1}'):$GRAFANA_PORT"
echo "用户名: admin, 密码: admin123"
```

## 第十二部分：性能优化和安全配置

### 12.1 系统性能优化

```bash
# 配置系统限制
cat <<EOF | sudo tee /etc/security/limits.d/k8s.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# 配置内核参数优化
cat <<EOF | sudo tee /etc/sysctl.d/k8s-performance.conf
# 网络优化
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# 内存优化
vm.max_map_count = 262144
vm.swappiness = 1
EOF

# 应用配置
sudo sysctl --system
```

### 12.2 安全配置

```bash
# 配置 RBAC 最小权限原则
# （在实际生产中，建议为不同应用创建专用的 ServiceAccount）

# 配置网络策略（示例）
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

### 12.3 日志配置

```bash
# 配置 containerd 日志轮转
sudo tee /etc/logrotate.d/containerd > /dev/null <<EOF
/var/log/containerd.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0644 root root
    postrotate
        systemctl reload containerd > /dev/null 2>&1 || true
    endscript
}
EOF
```

## 故障排除

### 常见问题和解决方案

#### 问题 1: NodePort 服务无法访问
**症状**: 浏览器访问 NodePort 服务时显示 "连接被重置" 或 "无法访问"
**诊断**:
```bash
# 检查 NodePort 监听状态
sudo ss -tlnp | grep -E ":30816|:32000"

# 检查 kube-proxy 状态
kubectl get pods -n kube-system | grep kube-proxy
kubectl logs -n kube-system $(kubectl get pods -n kube-system | grep kube-proxy | awk '{print $1}')
```
**解决方案**:
```bash
# 方案 1 (推荐): 使用 Ingress 访问服务
NODE_IP=$(hostname -I | awk '{print $1}')

# 为 Grafana 创建 Ingress (修复版本 - 移除有问题的 rewrite-target)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: grafana.$NODE_IP.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-grafana
            port:
              number: 80
EOF

# 如果 Grafana 仍显示 "Page not found"，需要更新 Grafana 配置
cat > /tmp/grafana-values.yaml << 'GRAFANA_EOF'
grafana:
  grafana.ini:
    server:
      domain: grafana.$NODE_IP.nip.io
      root_url: http://grafana.$NODE_IP.nip.io:$INGRESS_HTTP_PORT
      serve_from_sub_path: false
  ingress:
    enabled: false
GRAFANA_EOF

# 通过 Helm 升级 Grafana 配置
helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring -f /tmp/grafana-values.yaml

# 配置 NGINX Ingress Controller 使用标准端口 (无需端口号访问)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx -p '{"spec":{"template":{"spec":{"hostNetwork":true,"dnsPolicy":"ClusterFirstWithHostNet"}}}}'

# 等待重启完成
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s

# 为 Dashboard 创建 Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - dashboard.$NODE_IP.nip.io
  rules:
  - host: dashboard.$NODE_IP.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF

# 最终访问地址 (无端口号，使用标准 80/443 端口):
echo "✅ 无端口号访问地址:"
echo "• Grafana: http://grafana.$NODE_IP.nip.io"
echo "• Dashboard: https://dashboard.$NODE_IP.nip.io"

# 获取登录凭据:
echo ""
echo "🔑 登录信息:"
echo "• Grafana 用户名: admin"
echo "• Grafana 密码: admin123"
echo ""
echo "• Dashboard 令牌:"
kubectl create token dashboard-admin -n kubernetes-dashboard --duration=8760h
echo ""

# 方案 1 备选: 如果 NodePort 有问题，使用 kubectl proxy (最可靠)
cat > ~/kubectl-proxy-services.sh << 'EOF'
#!/bin/bash
echo "=== 启动 kubectl proxy 服务 ==="
pkill -f "kubectl proxy" 2>/dev/null
sleep 3
kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*' > /dev/null 2>&1 &
sleep 5
NODE_IP=$(hostname -I | awk '{print $1}')
echo "✅ kubectl proxy 已启动"
echo "• Grafana: http://$NODE_IP:8080/api/v1/namespaces/monitoring/services/prometheus-grafana:80/proxy/"
echo "• Dashboard: http://$NODE_IP:8080/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
EOF
chmod +x ~/kubectl-proxy-services.sh && ~/kubectl-proxy-services.sh

# 方案 2: 重启 kube-proxy
kubectl delete pod -n kube-system $(kubectl get pods -n kube-system | grep kube-proxy | awk '{print $1}')

# 方案 3: 使用端口转发作为临时解决方案
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --address=0.0.0.0 &
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 --address=0.0.0.0 &

# 然后访问:
# Grafana: http://节点IP:3000
# Dashboard: https://节点IP:8443

# 方案 4: 使用自动化脚本管理端口转发
cat > ~/port-forward-services.sh << 'EOF'
#!/bin/bash
echo "=== 启动 Kubernetes 服务端口转发 ==="
pkill -f "kubectl port-forward" 2>/dev/null
sleep 3
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --address=0.0.0.0 > /dev/null 2>&1 &
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 --address=0.0.0.0 > /dev/null 2>&1 &
sleep 5
echo "✅ 端口转发已启动"
echo "• Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "• Dashboard: https://$(hostname -I | awk '{print $1}'):8443"
EOF

chmod +x ~/port-forward-services.sh
~/port-forward-services.sh
```

**重要说明**: 直接访问 Kubernetes API Server (6443端口) 会返回 403 错误，这是正常的安全行为。需要使用 kubectl 或带有正确认证的工具访问。

#### 问题 2: NVIDIA Container Toolkit 仓库配置问题
**症状**: 添加 NVIDIA 仓库时返回 404 错误
**解决方案**:
```bash
# 使用新的仓库配置方法
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

#### 问题 3: Pod 卡在 Pending 状态
**症状**: Pod 长时间处于 Pending 状态
**诊断**:
```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```
**解决方案**:
- 检查资源限制
- 检查节点污点
- 检查存储类配置

#### 问题 2: 网络连接问题
**症状**: Pod 之间无法通信
**诊断**:
```bash
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel <flannel-pod>
```
**解决方案**:
- 重启 Flannel Pod
- 检查防火墙配置
- 验证 CNI 插件

#### 问题 3: GPU 不可见
**症状**: Pod 无法访问 GPU
**诊断**:
```bash
kubectl get nodes -o yaml | grep nvidia.com/gpu
kubectl get pods -n gpu-operator
```
**解决方案**:
- 检查 NVIDIA 驱动
- 重启 GPU Operator 组件
- 验证 containerd 配置

#### 问题 4: 存储访问问题
**症状**: PVC 卡在 Pending 状态
**诊断**:
```bash
kubectl describe pvc <pvc-name>
kubectl get storageclass
```
**解决方案**:
- 检查 local-path-provisioner 状态
- 验证节点存储空间
- 检查权限配置

### 日志查看命令

```bash
# 查看 kubelet 日志
sudo journalctl -u kubelet -f

# 查看 containerd 日志
sudo journalctl -u containerd -f

# 查看 Pod 日志
kubectl logs <pod-name> -n <namespace>

# 查看前一个容器实例的日志
kubectl logs <pod-name> --previous

# 查看所有容器日志
kubectl logs <pod-name> --all-containers=true
```

## 集群维护

### 定期维护任务

#### 1. 系统更新
```bash
# 每月执行系统更新
sudo apt update && sudo apt upgrade -y

# 更新 containerd（谨慎操作）
sudo apt update && sudo apt install containerd.io
sudo systemctl restart containerd
```

#### 2. 备份关键配置
```bash
# 备份 Kubernetes 配置
sudo cp -r /etc/kubernetes /backup/kubernetes-$(date +%Y%m%d)

# 备份 etcd 数据
sudo ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
```

#### 3. 清理无用资源
```bash
# 清理无用的容器镜像
sudo ctr images prune

# 清理无用的 Kubernetes 资源
kubectl delete pods --field-selector=status.phase=Succeeded -A
kubectl delete pods --field-selector=status.phase=Failed -A
```

### 监控指标

重要的监控指标包括：
- 节点 CPU、内存、磁盘使用率
- Pod 状态和重启次数
- GPU 使用率和温度
- 网络流量和延迟
- 存储 I/O 性能

## 完全卸载

如果需要完全删除 Kubernetes 集群：

```bash
# 重置 kubeadm
sudo kubeadm reset -f

# 删除配置文件
sudo rm -rf /etc/kubernetes
sudo rm -rf ~/.kube

# 删除网络配置
sudo rm -rf /etc/cni/net.d

# 停止和禁用服务
sudo systemctl stop kubelet containerd
sudo systemctl disable kubelet containerd

# 卸载包
sudo apt remove -y kubeadm kubectl kubelet containerd.io
sudo apt autoremove -y

# 删除仓库配置
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/sources.list.d/docker.list

# 删除数据目录
sudo rm -rf /var/lib/kubelet
sudo rm -rf /var/lib/containerd
sudo rm -rf /opt/cni

# 恢复系统配置
sudo rm -f /etc/modules-load.d/k8s.conf
sudo rm -f /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 重启系统
sudo reboot
```

## 总结

本文档详细介绍了在 Ubuntu 24.04 系统上安装单节点 Kubernetes 集群的完整过程，包括：

1. **基础环境准备**: 系统配置、防火墙、内核参数
2. **容器运行时**: containerd 安装和配置
3. **Kubernetes 核心**: kubeadm、kubelet、kubectl 安装
4. **集群初始化**: 单节点集群配置
5. **网络插件**: Flannel 网络方案
6. **存储系统**: local-path-provisioner 本地存储
7. **负载均衡**: NGINX Ingress Controller
8. **监控系统**: Prometheus + Grafana 完整监控
9. **管理界面**: Kubernetes Dashboard
10. **GPU 支持**: NVIDIA GPU Operator 配置

该配置方案兼顾了功能完整性和资源效率，适合开发、测试和小规模生产环境使用。

## 下一步

集群安装完成后，您可以：
1. 部署应用程序到集群
2. 配置 CI/CD 流水线
3. 集成外部服务
4. 优化性能和安全配置
5. 扩展集群功能

## 参考资料

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [containerd 官方文档](https://containerd.io/docs/)
- [Flannel 文档](https://github.com/flannel-io/flannel)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
