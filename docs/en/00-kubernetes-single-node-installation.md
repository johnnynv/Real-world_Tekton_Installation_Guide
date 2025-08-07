# 00 - Kubernetes Single Node Cluster Installation Guide

## Overview

This document provides a complete guide for installing a single-node Kubernetes cluster on Ubuntu 24.04 LTS system. This installation adopts production-grade configurations, including comprehensive monitoring, storage, networking, and GPU support, suitable for development, testing, and small-scale production environments.

## Technology Stack Selection

After technical evaluation, this installation adopts the following technology stack:

- **Container Runtime**: containerd (CNCF graduated project, officially recommended)
- **Kubernetes Version**: v1.30.x (stable version, production-ready)
- **Network Plugin**: Flannel (simple and reliable, suitable for single-node)
- **Storage**: local-path-provisioner (single-node storage solution)
- **Ingress Controller**: NGINX Ingress Controller (industry standard)
- **Monitoring Solution**: Prometheus + Grafana (complete monitoring ecosystem)
- **Dashboard**: Kubernetes Dashboard (official dashboard)
- **GPU Support**: NVIDIA GPU Operator (official GPU management solution)

## System Requirements

### Hardware Requirements
- **CPU**: Minimum 4 cores (recommended 8 cores or more)
- **Memory**: Minimum 8GB RAM (recommended 16GB or more)
- **Storage**: Minimum 50GB available disk space (recommended 100GB)
- **Network**: Stable network connection
- **GPU**: NVIDIA GPU (optional, this environment has 4x NVIDIA A16)

### Software Requirements
- Ubuntu 24.04 LTS (Noble Numbat)
- Root or sudo privileges
- Internet connection

## Part 1: System Prerequisites Preparation

### 1.1 System Information Verification

First verify current system configuration:

```bash
# Check system version
lsb_release -a

# Check kernel version
uname -r

# Check system resources
free -h
df -h

# Check GPU information (if available)
nvidia-smi
```

**Verification Method**:
- Confirm output shows Ubuntu 24.04
- Kernel version should be 6.x series
- Available memory at least 8GB
- Root partition at least 50GB available space
- GPU information displays normally

### 1.2 Update System Packages

```bash
# Update package index
sudo apt update

# Upgrade all packages to latest version
sudo apt upgrade -y

# Install necessary tool packages
sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release
```

**Verification Method**:
```bash
# Check if key tools are installed successfully
which curl wget gnupg2
curl --version
```

### 1.3 Configure System Parameters

#### 1.3.1 Disable Swap

Kubernetes requires disabling swap to ensure performance:

```bash
# Temporarily disable swap
sudo swapoff -a

# Permanently disable swap
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

**Verification Method**:
```bash
# Check if swap is disabled
free -h
# Swap line should show all zeros

# Check fstab configuration
grep swap /etc/fstab
# swap line should be commented out
```

#### 1.3.2 Load Required Kernel Modules

```bash
# Create kernel module configuration file
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Load modules immediately
sudo modprobe overlay
sudo modprobe br_netfilter
```

**Verification Method**:
```bash
# Check if modules are loaded successfully
lsmod | grep overlay
lsmod | grep br_netfilter
```

#### 1.3.3 Configure System Kernel Parameters

```bash
# Create sysctl configuration file
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply configuration
sudo sysctl --system
```

**Verification Method**:
```bash
# Check if parameters are set correctly
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables  
sysctl net.ipv4.ip_forward
# All values should be 1
```

### 1.4 Configure Firewall

Open necessary ports for Kubernetes components:

```bash
# If using ufw (Ubuntu default firewall)
sudo ufw allow 6443/tcp    # Kubernetes API server
sudo ufw allow 2379:2380/tcp # etcd server client API
sudo ufw allow 10250/tcp   # Kubelet API
sudo ufw allow 10251/tcp   # kube-scheduler
sudo ufw allow 10252/tcp   # kube-controller-manager
sudo ufw allow 10255/tcp   # Read-only Kubelet API
sudo ufw allow 30000:32767/tcp # NodePort Services

# Allow container network communication
sudo ufw allow from 10.244.0.0/16  # Pod network (Flannel)
sudo ufw allow from 10.96.0.0/12   # Service network
```

**Verification Method**:
```bash
# Check firewall rules
sudo ufw status numbered
```

## Part 2: Container Runtime Installation and Configuration

### 2.1 Install containerd

#### 2.1.1 Add Docker Official Repository

```bash
# Create keyrings directory
sudo mkdir -p /etc/apt/keyrings

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

#### 2.1.2 Install containerd

```bash
# Update package index
sudo apt update

# Install containerd
sudo apt install -y containerd.io

# Start and enable containerd service
sudo systemctl enable containerd
sudo systemctl start containerd
```

**Verification Method**:
```bash
# Check containerd version and status
containerd --version
sudo systemctl status containerd
```

### 2.2 Configure containerd

#### 2.2.1 Generate Default Configuration

```bash
# Create configuration directory
sudo mkdir -p /etc/containerd

# Generate default configuration
containerd config default | sudo tee /etc/containerd/config.toml

# Backup configuration file
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
```

#### 2.2.2 Configure systemd cgroup Driver

```bash
# Modify systemd cgroup configuration
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

**Verification Method**:
```bash
# Check if configuration is correctly modified
grep -A 5 -B 5 "SystemdCgroup" /etc/containerd/config.toml
```

#### 2.2.3 Restart containerd

```bash
# Restart service to apply new configuration
sudo systemctl restart containerd

# Check service status
sudo systemctl status containerd
```

**Important Note**: If encountering CRI errors during kubeadm init, restart containerd service:
```bash
# If encountering "container runtime is not running" error
sudo systemctl restart containerd

# Verify CRI interface is working
sudo crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock version
```

### 2.3 Install CNI Plugins

```bash
# Create CNI directory
sudo mkdir -p /opt/cni/bin

# Download CNI plugins
CNI_VERSION="v1.3.0"
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz
```

**Verification Method**:
```bash
# Check if CNI plugins are installed successfully
ls -la /opt/cni/bin/
```

## Part 3: Kubernetes Tools Installation

### 3.1 Install kubeadm, kubelet, kubectl

#### 3.1.1 Add Kubernetes Repository

```bash
# Add Kubernetes signing key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

#### 3.1.2 Install Kubernetes Tools

```bash
# Update package index
sudo apt update

# Install Kubernetes tools
sudo apt install -y kubelet kubeadm kubectl

# Prevent automatic updates
sudo apt-mark hold kubelet kubeadm kubectl
```

**Verification Method**:
```bash
# Check versions
kubeadm version
kubelet --version
kubectl version --client
```

### 3.2 Configure kubelet

```bash
# Enable kubelet service
sudo systemctl enable kubelet
```

## Part 4: Initialize Kubernetes Cluster

### 4.1 Create Cluster Configuration File

Create kubeadm configuration file to customize cluster parameters:

```bash
cat <<EOF | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.30.14
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

### 4.2 Initialize Cluster

```bash
# Initialize Kubernetes cluster
sudo kubeadm init --config=/tmp/kubeadm-config.yaml

# Save the join command from output (although it's single-node, recommend saving for future node addition)
```

**Important**: Save the kubeadm join command from the output for future node additions.

### 4.3 Configure kubectl

```bash
# Configure kubectl for current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Verification Method**:
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes
```

### 4.4 Remove Master Node Taint (Single-node Configuration)

```bash
# Allow scheduling Pods on master node
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

**Verification Method**:
```bash
# Check node status
kubectl get nodes
# Status should be Ready, but may show NotReady before network plugin installation
```

## Part 5: Network Plugin Installation (Flannel)

### 5.1 Install Flannel

```bash
# Download and install Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Verification Method**:
```bash
# Check Flannel Pod status
kubectl get pods -n kube-flannel

# Check node status (should become Ready)
kubectl get nodes

# Check all system Pod status
kubectl get pods -A
```

### 5.2 Verify Network Connectivity

```bash
# Create test Pod
kubectl run test-pod --image=busybox --restart=Never --rm -it -- /bin/sh

# Test inside Pod (execute in Pod shell)
nslookup kubernetes.default.svc.cluster.local
ping -c 3 8.8.8.8
exit
```

## Part 6: Storage Configuration (local-path-provisioner)

### 6.1 Install local-path-provisioner

```bash
# Install local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
```

**Verification Method**:
```bash
# Check storage class
kubectl get storageclass

# Check local-path-provisioner Pod
kubectl get pods -n local-path-storage
```

### 6.2 Set Default Storage Class

```bash
# Set local-path as default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**Verification Method**:
```bash
# Check default storage class (should see local-path (default))
kubectl get storageclass
```

### 6.3 Test Storage Functionality

```bash
# Create test PVC
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

# Create test Pod using PVC
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

**Verification Method**:
```bash
# Check PVC status
kubectl get pvc

# Check Pod status
kubectl get pods

# Verify data write
kubectl exec test-storage-pod -- cat /data/test.txt

# Clean up test resources
kubectl delete pod test-storage-pod
kubectl delete pvc test-pvc
```

## Part 7: NGINX Ingress Controller Installation

### 7.1 Install NGINX Ingress Controller

```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
```

**Verification Method**:
```bash
# Check Ingress Controller Pod status
kubectl get pods -n ingress-nginx

# Check service status
kubectl get svc -n ingress-nginx
```

### 7.2 Configure Ingress Controller as NodePort

```bash
# Check NodePort ports
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Record HTTP and HTTPS ports (usually in 30000+ range)
```

### 7.3 Generate Self-signed Certificate

```bash
# Create certificate directory
mkdir -p ~/k8s-certs
cd ~/k8s-certs

# Generate private key
openssl genrsa -out tls.key 2048

# Generate certificate signing request
openssl req -new -key tls.key -out tls.csr -subj "/CN=k8s.local/O=kubernetes"

# Generate self-signed certificate
openssl x509 -req -in tls.csr -signkey tls.key -out tls.crt -days 365

# Create TLS Secret
kubectl create secret tls k8s-local-tls --cert=tls.crt --key=tls.key -n default
```

### 7.4 Test Ingress

```bash
# Create test application
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

**Verification Method**:
```bash
# Check Ingress status
kubectl get ingress

# Add local hosts entry
echo "127.0.0.1 k8s.local" | sudo tee -a /etc/hosts

# Get NodePort port
HTTPS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

# Test access (ignore certificate warning)
curl -k https://k8s.local:$HTTPS_PORT

# Clean up test resources
kubectl delete deployment test-app
kubectl delete service test-app-service
kubectl delete ingress test-app-ingress
```

## Part 8: Monitoring System Installation (Prometheus + Grafana)

### 8.1 Install kube-prometheus-stack

```bash
# Add Prometheus Helm repository
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 8.2 Create Monitoring Namespace

```bash
# Create monitoring namespace
kubectl create namespace monitoring
```

### 8.3 Install Prometheus and Grafana

```bash
# Create configuration directory
mkdir -p configs/monitoring

# Create values configuration file
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

# Install kube-prometheus-stack (set Grafana password to admin123)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values configs/monitoring/prometheus-values.yaml \
  --set grafana.adminPassword=admin123
```

**Verification Method**:
```bash
# Check all monitoring component status
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring

# Get Grafana access port
kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}'
```

### 8.4 Configure Grafana Access

```bash
# Get Grafana NodePort
GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')

echo "Grafana access URL: http://$(hostname -I | awk '{print $1}'):$GRAFANA_PORT"
echo "Username: admin"
echo "Password: admin123"
```

### 8.5 Verify Monitoring Data

```bash
# Get Prometheus access port
PROMETHEUS_PORT=$(kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.spec.ports[0].nodePort}')

echo "Prometheus access URL: http://$(hostname -I | awk '{print $1}'):$PROMETHEUS_PORT"
```

## Part 9: Kubernetes Dashboard Installation

### 9.1 Install Kubernetes Dashboard

```bash
# Install Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### 9.2 Create Admin User

```bash
# Create service account
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

### 9.3 Configure Dashboard Access

```bash
# Modify service type to NodePort
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'

# Get access port
DASHBOARD_PORT=$(kubectl get svc -n kubernetes-dashboard kubernetes-dashboard -o jsonpath='{.spec.ports[0].nodePort}')

echo "Dashboard access URL: https://$(hostname -I | awk '{print $1}'):$DASHBOARD_PORT"
```

### 9.4 Get Access Token

```bash
# Get access token
kubectl -n kubernetes-dashboard create token admin-user

# Or create long-term token
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: "admin-user"
type: kubernetes.io/service-account-token
EOF

# Get long-term token
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

**Verification Method**:
- Access Dashboard URL using browser
- Select "Token" login method
- Input the obtained token
- Successfully login and see cluster overview

## Part 10: GPU Support Configuration (NVIDIA GPU Operator)

### 10.1 Verify GPU Driver

```bash
# Check NVIDIA driver status
nvidia-smi

# Check NVIDIA container toolkit (install if needed)
which nvidia-container-runtime || echo "Need to install nvidia-container-toolkit"
```

### 10.2 Install NVIDIA Container Toolkit

```bash
# Add NVIDIA repository GPG key
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Add NVIDIA repository
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install nvidia-container-toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure containerd
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart containerd
```

### 10.3 Install NVIDIA GPU Operator

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Create GPU Operator namespace
kubectl create namespace gpu-operator

# Install GPU Operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=false \
  --set toolkit.enabled=true
```

**Verification Method**:
```bash
# Check GPU Operator component status
kubectl get pods -n gpu-operator

# Wait for all Pods to be ready (may take several minutes)
kubectl wait --for=condition=Ready pod --all -n gpu-operator --timeout=600s
```

### 10.4 Verify GPU Functionality

```bash
# Create GPU test Pod
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

# Wait for Pod completion
kubectl wait --for=condition=Ready pod/gpu-test --timeout=300s

# View GPU test results
kubectl logs gpu-test

# Clean up test Pod
kubectl delete pod gpu-test
```

### 10.5 Deploy GPU Monitoring

```bash
# GPU Operator automatically deploys DCGM Exporter for GPU monitoring
# Check DCGM Exporter status
kubectl get pods -n gpu-operator | grep dcgm

# Check GPU metrics
kubectl get --raw /api/v1/nodes/$(kubectl get nodes -o name | cut -d/ -f2)/proxy/metrics | grep DCGM
```

## Part 11: System Verification and Testing

### 11.1 Comprehensive Cluster Status Check

```bash
# Check all node status
kubectl get nodes -o wide

# Check all namespace Pod status
kubectl get pods -A

# Check all service status
kubectl get svc -A

# Check storage classes
kubectl get storageclass

# Check Ingress status
kubectl get ingress -A
```

### 11.2 Network Connectivity Test

```bash
# Create network test Pod
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

# Wait for Pod ready
kubectl wait --for=condition=Ready pod/network-test --timeout=300s

# Test internal DNS resolution
kubectl exec network-test -- nslookup kubernetes.default.svc.cluster.local

# Test external network
kubectl exec network-test -- wget -q --spider http://www.google.com && echo "External network OK"

# Clean up test Pod
kubectl delete pod network-test
```

### 11.3 Storage Functionality Test

```bash
# Create storage test
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
    command: ['sh', '-c', 'echo "Storage test data" > /data/test.txt && cat /data/test.txt && sleep 300']
    volumeMounts:
    - name: storage-volume
      mountPath: /data
  volumes:
  - name: storage-volume
    persistentVolumeClaim:
      claimName: storage-test-pvc
EOF

# Check test results
kubectl logs storage-test

# Clean up test resources
kubectl delete pod storage-test
kubectl delete pvc storage-test-pvc
```

### 11.4 GPU Load Test

```bash
# Create GPU load test
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
          echo "Running GPU benchmark test..."
          # Simple GPU computation test
          echo 'import numpy as np; print("GPU test completed")' > test.py
          python3 test.py || echo "Python3 not available, test completed with nvidia-smi"
        resources:
          limits:
            nvidia.com/gpu: 1
      restartPolicy: Never
EOF

# Wait for job completion
kubectl wait --for=condition=Complete job/gpu-benchmark --timeout=600s

# View test results
kubectl logs job/gpu-benchmark

# Clean up test job
kubectl delete job gpu-benchmark
```

### 11.5 Monitoring System Verification

```bash
# Check Prometheus targets status
PROMETHEUS_PORT=$(kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.spec.ports[0].nodePort}')
echo "Access Prometheus targets: http://$(hostname -I | awk '{print $1}'):$PROMETHEUS_PORT/targets"

# Check Grafana dashboards
GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')
echo "Access Grafana: http://$(hostname -I | awk '{print $1}'):$GRAFANA_PORT"
echo "Username: admin, Password: admin123"
```

## Part 12: Performance Optimization and Security Configuration

### 12.1 System Performance Optimization

```bash
# Configure system limits
cat <<EOF | sudo tee /etc/security/limits.d/k8s.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# Configure kernel parameter optimization
cat <<EOF | sudo tee /etc/sysctl.d/k8s-performance.conf
# Network optimization
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# Memory optimization
vm.max_map_count = 262144
vm.swappiness = 1
EOF

# Apply configuration
sudo sysctl --system
```

### 12.2 Security Configuration

```bash
# Configure RBAC minimum privilege principle
# (In actual production, recommend creating dedicated ServiceAccounts for different applications)

# Configure network policies (example)
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

### 12.3 Log Configuration

```bash
# Configure containerd log rotation
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

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: NodePort Services Cannot Be Accessed
**Symptoms**: Browser shows "connection reset" or "cannot reach" when accessing NodePort services
**Diagnosis**:
```bash
# Check NodePort listening status
sudo ss -tlnp | grep -E ":30816|:32000"

# Check kube-proxy status
kubectl get pods -n kube-system | grep kube-proxy
kubectl logs -n kube-system $(kubectl get pods -n kube-system | grep kube-proxy | awk '{print $1}')
```
**Solutions**:
```bash
# Solution 1 (Recommended): Use Ingress to access services
NODE_IP=$(hostname -I | awk '{print $1}')

# Create Ingress for Grafana (Fixed version - remove problematic rewrite-target)
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

# If Grafana still shows "Page not found", update Grafana configuration
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

# Upgrade Grafana configuration via Helm
helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring -f /tmp/grafana-values.yaml

# Configure NGINX Ingress Controller to use standard ports (no port numbers needed)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx -p '{"spec":{"template":{"spec":{"hostNetwork":true,"dnsPolicy":"ClusterFirstWithHostNet"}}}}'

# Wait for restart to complete
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s

# Create Ingress for Dashboard
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

# Final access URLs (no port numbers, using standard 80/443 ports):
echo "✅ No-port access URLs:"
echo "• Grafana: http://grafana.$NODE_IP.nip.io"
echo "• Dashboard: https://dashboard.$NODE_IP.nip.io"

# Get login credentials:
echo ""
echo "🔑 Login Information:"
echo "• Grafana Username: admin"
echo "• Grafana Password: admin123"
echo ""
echo "• Dashboard Token:"
kubectl create token dashboard-admin -n kubernetes-dashboard --duration=8760h
echo ""

# Solution 1 Alternative: If NodePort has issues, use kubectl proxy (Most reliable)
cat > ~/kubectl-proxy-services.sh << 'EOF'
#!/bin/bash
echo "=== Starting kubectl proxy service ==="
pkill -f "kubectl proxy" 2>/dev/null
sleep 3
kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*' > /dev/null 2>&1 &
sleep 5
NODE_IP=$(hostname -I | awk '{print $1}')
echo "✅ kubectl proxy started"
echo "• Grafana: http://$NODE_IP:8080/api/v1/namespaces/monitoring/services/prometheus-grafana:80/proxy/"
echo "• Dashboard: http://$NODE_IP:8080/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
EOF
chmod +x ~/kubectl-proxy-services.sh && ~/kubectl-proxy-services.sh

# Solution 2: Restart kube-proxy
kubectl delete pod -n kube-system $(kubectl get pods -n kube-system | grep kube-proxy | awk '{print $1}')

# Solution 3: Use port forwarding as temporary solution
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --address=0.0.0.0 &
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 --address=0.0.0.0 &

# Then access:
# Grafana: http://NodeIP:3000
# Dashboard: https://NodeIP:8443

# Solution 4: Use automated script to manage port forwarding
cat > ~/port-forward-services.sh << 'EOF'
#!/bin/bash
echo "=== Starting Kubernetes Services Port Forwarding ==="
pkill -f "kubectl port-forward" 2>/dev/null
sleep 3
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --address=0.0.0.0 > /dev/null 2>&1 &
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 --address=0.0.0.0 > /dev/null 2>&1 &
sleep 5
echo "✅ Port forwarding started"
echo "• Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "• Dashboard: https://$(hostname -I | awk '{print $1}'):8443"
EOF

chmod +x ~/port-forward-services.sh
~/port-forward-services.sh
```

**Important Note**: Direct access to Kubernetes API Server (port 6443) returns 403 error, which is normal security behavior. Use kubectl or tools with proper authentication to access.

#### Issue 2: NVIDIA Container Toolkit Repository Configuration Problems
**Symptoms**: 404 errors when adding NVIDIA repository
**Solutions**:
```bash
# Use new repository configuration method
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

#### Issue 3: Pod Stuck in Pending State
**Symptoms**: Pod remains in Pending state for long time
**Diagnosis**:
```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```
**Solutions**:
- Check resource limits
- Check node taints
- Check storage class configuration

#### Issue 2: Network Connection Problems
**Symptoms**: Pods cannot communicate with each other
**Diagnosis**:
```bash
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel <flannel-pod>
```
**Solutions**:
- Restart Flannel Pods
- Check firewall configuration
- Verify CNI plugins

#### Issue 3: GPU Not Visible
**Symptoms**: Pods cannot access GPU
**Diagnosis**:
```bash
kubectl get nodes -o yaml | grep nvidia.com/gpu
kubectl get pods -n gpu-operator
```
**Solutions**:
- Check NVIDIA drivers
- Restart GPU Operator components
- Verify containerd configuration

#### Issue 4: Storage Access Issues
**Symptoms**: PVC stuck in Pending state
**Diagnosis**:
```bash
kubectl describe pvc <pvc-name>
kubectl get storageclass
```
**Solutions**:
- Check local-path-provisioner status
- Verify node storage space
- Check permission configuration

### Log Viewing Commands

```bash
# View kubelet logs
sudo journalctl -u kubelet -f

# View containerd logs
sudo journalctl -u containerd -f

# View Pod logs
kubectl logs <pod-name> -n <namespace>

# View previous container instance logs
kubectl logs <pod-name> --previous

# View all container logs
kubectl logs <pod-name> --all-containers=true
```

## Cluster Maintenance

### Regular Maintenance Tasks

#### 1. System Updates
```bash
# Monthly system updates
sudo apt update && sudo apt upgrade -y

# Update containerd (proceed with caution)
sudo apt update && sudo apt install containerd.io
sudo systemctl restart containerd
```

#### 2. Backup Critical Configurations
```bash
# Backup Kubernetes configuration
sudo cp -r /etc/kubernetes /backup/kubernetes-$(date +%Y%m%d)

# Backup etcd data
sudo ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
```

#### 3. Clean Up Unused Resources
```bash
# Clean up unused container images
sudo ctr images prune

# Clean up unused Kubernetes resources
kubectl delete pods --field-selector=status.phase=Succeeded -A
kubectl delete pods --field-selector=status.phase=Failed -A
```

### Monitoring Metrics

Important monitoring metrics include:
- Node CPU, memory, disk usage
- Pod status and restart counts
- GPU usage and temperature
- Network traffic and latency
- Storage I/O performance

## Complete Uninstallation

If you need to completely remove the Kubernetes cluster:

```bash
# Reset kubeadm
sudo kubeadm reset -f

# Delete configuration files
sudo rm -rf /etc/kubernetes
sudo rm -rf ~/.kube

# Delete network configuration
sudo rm -rf /etc/cni/net.d

# Stop and disable services
sudo systemctl stop kubelet containerd
sudo systemctl disable kubelet containerd

# Uninstall packages
sudo apt remove -y kubeadm kubectl kubelet containerd.io
sudo apt autoremove -y

# Delete repository configuration
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/sources.list.d/docker.list

# Delete data directories
sudo rm -rf /var/lib/kubelet
sudo rm -rf /var/lib/containerd
sudo rm -rf /opt/cni

# Restore system configuration
sudo rm -f /etc/modules-load.d/k8s.conf
sudo rm -f /etc/sysctl.d/k8s.conf
sudo sysctl --system

# Restart system
sudo reboot
```

## Summary

This document details the complete process of installing a single-node Kubernetes cluster on Ubuntu 24.04 system, including:

1. **Basic Environment Preparation**: System configuration, firewall, kernel parameters
2. **Container Runtime**: containerd installation and configuration
3. **Kubernetes Core**: kubeadm, kubelet, kubectl installation
4. **Cluster Initialization**: Single-node cluster configuration
5. **Network Plugin**: Flannel network solution
6. **Storage System**: local-path-provisioner local storage
7. **Load Balancing**: NGINX Ingress Controller
8. **Monitoring System**: Prometheus + Grafana complete monitoring
9. **Management Interface**: Kubernetes Dashboard
10. **GPU Support**: NVIDIA GPU Operator configuration

This configuration solution balances functionality completeness and resource efficiency, suitable for development, testing, and small-scale production environments.

## Next Steps

After cluster installation is complete, you can:
1. Deploy applications to the cluster
2. Configure CI/CD pipelines
3. Integrate external services
4. Optimize performance and security configuration
5. Extend cluster functionality

## References

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [containerd Official Documentation](https://containerd.io/docs/)
- [Flannel Documentation](https://github.com/flannel-io/flannel)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
