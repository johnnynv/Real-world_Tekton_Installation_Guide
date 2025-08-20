# Rocky Linux 10 Single Node Kubernetes Cluster Installation Guide

This guide details how to install a single-node Kubernetes cluster on Rocky Linux 10 systems with GPU workload support.

## 📋 Technical Stack

- **Kubernetes**: kubeadm v1.31.12
- **Container Runtime**: containerd v1.7.27
- **Network Plugin**: Calico v3.29.2
- **Storage**: Local Path Provisioner v0.0.30
- **Monitoring**: Metrics Server + NVIDIA DCGM Exporter
- **Dashboard**: Kubernetes Dashboard v2.7.0
- **GPU Support**: NVIDIA GPU Operator
- **Package Manager**: Helm v3.18.5

## 🏁 Step 1: System Environment Check

```bash
# Check OS version
cat /etc/os-release
# Expected: Rocky Linux 10.0 (Red Quartz)

# Check hardware resources
free -h
nproc
df -h /

# Check network and hostname
hostname
hostname -I

# Check firewall status
systemctl status firewalld
# Expected: inactive (disabled)

# Check SELinux status
getenforce
# Expected: Disabled

# Check swap status
swapon --show
free -h
# Expected: Swap 0B (disabled)
```

**Verification Results**:
- ✅ Rocky Linux 10.0 system
- ✅ Memory 502GB, CPU 32 cores, Disk 3TB
- ✅ Firewall disabled
- ✅ SELinux disabled
- ✅ Swap disabled

## 🔧 Step 2: System Prerequisites

### Configure Kernel Modules

```bash
# Configure required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Load kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Verify module loading
lsmod | grep -E "(overlay|br_netfilter)"
```

### Configure Kernel Parameters

```bash
# Configure network parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply configuration
sudo sysctl --system

# Verify key parameters
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

**Verification Results**:
- ✅ overlay and br_netfilter modules loaded
- ✅ Network forwarding parameters enabled

## 🐳 Step 3: Install containerd Container Runtime

### Add Docker Repository

```bash
# Add Docker repository (contains containerd)
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Update cache
sudo dnf makecache

# Search containerd
sudo dnf search containerd
```

### Install containerd

```bash
# Install containerd.io
sudo dnf install -y containerd.io

# Generate default configuration
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Configure systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Verify configuration
grep -n "SystemdCgroup" /etc/containerd/config.toml
```

### Start containerd Service

```bash
# Start and enable service
sudo systemctl enable --now containerd

# Verify status
systemctl status containerd --no-pager
```

**Verification Results**:
- ✅ containerd v1.7.27 installed successfully
- ✅ systemd cgroup driver configured
- ✅ Service running normally

## ⚙️ Step 4: Install Kubernetes Tools

### Add Kubernetes Repository

```bash
# Add Kubernetes official repository
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

### Install Kubernetes Components

```bash
# Update repository cache
sudo dnf makecache

# Install kubeadm, kubelet, kubectl
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Enable kubelet service
sudo systemctl enable kubelet

# Verify versions
kubeadm version
kubelet --version
kubectl version --client
```

**Verification Results**:
- ✅ kubeadm v1.31.12
- ✅ kubelet v1.31.12
- ✅ kubectl v1.31.12

## 🎯 Step 5: Initialize Kubernetes Cluster

### Cluster Initialization

```bash
# Initialize cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/containerd/containerd.sock

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Remove master node taint (single node cluster)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Verify cluster status
kubectl get nodes
kubectl get pods -A
```

**Verification Results**:
- ✅ Cluster initialization successful
- ✅ Node status NotReady (needs network plugin)
- ✅ Control plane components running normally

## 🌐 Step 6: Install Calico Network Plugin

### Install Tigera Operator

```bash
# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml
```

### Configure Calico Installation

```bash
# Create Calico installation configuration
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

# Wait for installation to complete
kubectl wait --for=condition=Ready --timeout=300s installation/default

# Verify installation
kubectl get pods -n calico-system
kubectl get nodes
```

**Verification Results**:
- ✅ Calico network plugin installed successfully
- ✅ Node status changed to Ready
- ✅ Network connectivity normal

## 💾 Step 7: Install Local Path Provisioner Storage

### Install Storage Provisioner

```bash
# Install Local Path Provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# Set as default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify installation
kubectl get storageclass
kubectl get pods -n local-path-storage
```

**Verification Results**:
- ✅ local-path set as default storage class
- ✅ provisioner running normally

## 📊 Step 8: Install Metrics Server Monitoring

### Install Metrics Server

```bash
# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Fix TLS issues for single node cluster
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

# Verify functionality
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl top nodes
```

**Verification Results**:
- ✅ Metrics Server running normally
- ✅ Can retrieve node resource metrics

## 🖥️ Step 9: Install Kubernetes Dashboard

### Install Dashboard

```bash
# Install Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create admin user
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

# Verify installation
kubectl get pods -n kubernetes-dashboard
```

### Access Dashboard

```bash
# Get access token
kubectl -n kubernetes-dashboard create token admin-user

# Start port forwarding
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443
```

**Access Information**:
- **URL**: https://localhost:8443
- **Token**: Obtained through command above
- **User**: admin-user

## 📦 Step 10: Install Helm Package Manager

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify version
helm version
```

**Verification Results**:
- ✅ Helm v3.18.5 installed successfully

## 🎮 Step 11: Install NVIDIA GPU Operator

### Add NVIDIA Helm Repository

```bash
# Add NVIDIA repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Install GPU Operator

```bash
# Install GPU Operator (disable driver installation)
helm install --wait gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false

# Verify installation
kubectl get pods -n gpu-operator
```

### Verify GPU Resources

```bash
# Check GPU resources
kubectl describe node | grep -A 5 -B 5 nvidia.com/gpu

# Check GPU allocation
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
```

**Verification Results**:
- ✅ 4 GPU devices detected
- ✅ All GPU Operator components running normally
- ✅ NVIDIA DCGM Exporter automatically installed

## 📈 Step 12: Verify DCGM Monitoring Metrics

### Access GPU Metrics

```bash
# Port forward DCGM Exporter
kubectl port-forward -n gpu-operator service/nvidia-dcgm-exporter 9400:9400 &

# Test metrics retrieval
curl -s http://localhost:9400/metrics | grep -E "(DCGM_FI_DEV_GPU_UTIL|DCGM_FI_DEV_MEM_COPY_UTIL)" | head -5
```

**DCGM Metrics Access**:
- **URL**: http://localhost:9400/metrics
- **Key Metrics**: GPU utilization, memory usage, temperature, etc.

## ✅ Step 13: Complete System Verification

### Cluster Status Verification

```bash
echo "🔍 Complete System Verification"
echo "========================="

# 1. Node status
echo "1. Node Status:"
kubectl get nodes

# 2. All pod status
echo "2. Key Pod Status:"
kubectl get pods -A --field-selector=status.phase!=Succeeded | grep -v Completed

# 3. GPU resources
echo "3. GPU Resource Allocation:"
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu

# 4. Storage classes
echo "4. Storage Classes:"
kubectl get storageclass

# 5. Network plugin
echo "5. Network Plugin:"
kubectl get pods -n calico-system

echo "========================="
echo "🎉 System Verification Complete!"
```

## 🚀 Access Information Summary

### Dashboard and Monitoring Access

#### 🌐 **Access via nip.io Domain (Recommended)**

##### Dashboard Access
```bash
# Create NodePort service
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

# Install nginx reverse proxy
sudo dnf install -y nginx

# Create SSL certificate
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/dashboard.key \
  -out /etc/nginx/ssl/dashboard.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=dashboard.$(hostname -I | awk '{print $1}').nip.io"

# Configure nginx
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

# GPU Monitoring Service
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

# Start nginx
sudo systemctl enable --now nginx

# Get access token
kubectl -n kubernetes-dashboard create token admin-user
```

##### GPU Monitoring Access
```bash
# Create DCGM Exporter NodePort service
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

#### 📱 **Access Links**

- **Kubernetes Dashboard**: https://dashboard.10.78.14.61.nip.io
- **GPU Monitoring Metrics**: http://gpu-metrics.10.78.14.61.nip.io/metrics  
- **Token Generation**: `kubectl -n kubernetes-dashboard create token admin-user`

#### 🔧 **Local Port Forwarding Access (Alternative)**
```bash
# Dashboard port forwarding
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443 &

# GPU monitoring port forwarding
kubectl port-forward -n gpu-operator service/nvidia-dcgm-exporter 9400:9400 &
```

- **Dashboard URL**: https://localhost:8443
- **DCGM Metrics URL**: http://localhost:9400/metrics

## 📋 Installation Results Summary

### ✅ Successfully Installed Components
1. **Kubernetes Cluster**: v1.31.12 single node cluster
2. **Container Runtime**: containerd v1.7.27
3. **Network Plugin**: Calico v3.29.2
4. **Storage**: Local Path Provisioner (default storage class)
5. **Monitoring**: Metrics Server + NVIDIA DCGM Exporter
6. **Dashboard**: Kubernetes Dashboard v2.7.0
7. **GPU Support**: NVIDIA GPU Operator
8. **Package Manager**: Helm v3.18.5

### 📊 Cluster Specifications
- **Node Count**: 1 (control-plane + worker)
- **GPU Devices**: 4x NVIDIA Graphics Device
- **Total GPU Memory**: 716GB (4x179GB)
- **Compute Capability**: 10.0 (supports latest CUDA features)
- **Network**: Calico VXLAN, Pod CIDR 192.168.0.0/16
- **Storage**: Local path storage with dynamic provisioning

### 🎯 Next Integration Ready
This cluster is ready for the following workloads:
- **Tekton Pipeline**: GPU-accelerated CI/CD workflows
- **Scientific Computing**: PyTorch, TensorFlow, RAPIDS, etc.
- **Machine Learning**: Model training and inference workloads
- **Containerized Applications**: GPU-enabled container applications

## 🛠️ One-Click Installation Scripts

### Quick Installation
```bash
# Download and run installation script
curl -O https://raw.githubusercontent.com/your-repo/scripts/install-k8s-gpu.sh
chmod +x install-k8s-gpu.sh
./install-k8s-gpu.sh
```

### Complete Uninstallation
```bash
# Download and run uninstallation script
curl -O https://raw.githubusercontent.com/your-repo/scripts/uninstall-k8s-gpu.sh
chmod +x uninstall-k8s-gpu.sh
./uninstall-k8s-gpu.sh
```

## 📚 Next Steps

After cluster installation, you can continue with:
1. [Tekton Core Installation](04-tekton-installation.md)
2. [Tekton Triggers Setup](05-tekton-triggers-setup.md)
3. [GPU Pipeline Deployment](07-gpu-pipeline-deployment.md)

## 🔧 Troubleshooting

### Common Issues
1. **Node NotReady**: Check network plugin installation status
2. **Pod image pull failures**: Check network connectivity and DNS configuration
3. **GPU resources not detected**: Verify GPU Operator and driver status
4. **Dashboard inaccessible**: Check port forwarding and token validity

### Diagnostic Commands
```bash
# Node diagnosis
kubectl describe nodes

# Pod diagnosis
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>

# GPU diagnosis
kubectl get pods -n gpu-operator
kubectl logs -n gpu-operator <gpu-operator-pod>

# Network diagnosis
kubectl get pods -n calico-system
kubectl logs -n calico-system <calico-pod>
```

## 📖 References

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [Calico Network Plugin](https://docs.tigera.io/calico/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
- [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/)
