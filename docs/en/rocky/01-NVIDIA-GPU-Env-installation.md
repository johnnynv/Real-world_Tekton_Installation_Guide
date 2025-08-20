# NVIDIA GPU Environment Installation Guide

This guide details how to install and configure a complete NVIDIA GPU environment on Rocky Linux 10 systems.

## 🏁 Step 1: System Environment Check

```bash
# Check OS version
cat /etc/os-release

# Check kernel version
uname -r

# Check GPU hardware
lspci | grep -i nvidia

# Check current driver status
nvidia-smi
```

## 🛠️ Step 2: Install Development Tools and Repositories

```bash
# Install EPEL repository
sudo dnf install -y epel-release

# Update system packages
sudo dnf update -y

# Install compilation tools
sudo dnf install -y gcc kernel-devel kernel-headers dkms make bzip2

# Add NVIDIA official repository
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo

# Update repository cache
sudo dnf makecache

# Verify repository
sudo dnf search nvidia-driver
```

## 🎯 Step 3: Install NVIDIA Driver

```bash
# Install NVIDIA driver
sudo dnf install -y nvidia-driver nvidia-driver-cuda

# Check DKMS status
dkms status

# Load kernel modules
sudo modprobe nvidia

# Check module loading
lsmod | grep nvidia

# Verify driver
nvidia-smi
```

## 💻 Step 4: Install CUDA Toolkit

```bash
# Install CUDA 13.0 Toolkit
sudo dnf install -y cuda-toolkit-13-0

# Configure environment variables (zsh)
echo 'export PATH=/usr/local/cuda-13.0/bin:$PATH' >> ~/.zshrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:$LD_LIBRARY_PATH' >> ~/.zshrc

# Set temporary environment variables
export PATH=/usr/local/cuda-13.0/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:$LD_LIBRARY_PATH

# Verify NVCC
nvcc --version
```

## 🧪 Step 5: CUDA Functionality Verification

```bash
# Create test program
cat > /tmp/cuda_test.cu << 'EOF'
#include <stdio.h>
#include <cuda_runtime.h>

__global__ void hello_cuda() {
    printf("Hello from GPU thread %d\n", threadIdx.x);
}

int main() {
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    printf("Found %d CUDA devices\n", deviceCount);
    
    for (int device = 0; device < deviceCount; ++device) {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, device);
        printf("Device %d: %s\n", device, deviceProp.name);
        printf("  Compute capability: %d.%d\n", deviceProp.major, deviceProp.minor);
        printf("  Memory: %.2f GB\n", deviceProp.totalGlobalMem / 1024.0 / 1024.0 / 1024.0);
    }
    
    hello_cuda<<<1, 5>>>();
    cudaDeviceSynchronize();
    
    return 0;
}
EOF

# Compile and run
nvcc /tmp/cuda_test.cu -o /tmp/cuda_test
/tmp/cuda_test
```

## 🔄 Step 6: Configure Persistence Mode

```bash
# Check current persistence status
nvidia-smi -q | grep -A 2 "Persistence Mode"

# Check service status
systemctl status nvidia-persistenced

# Enable and start service
sudo systemctl enable nvidia-persistenced
sudo systemctl start nvidia-persistenced

# Verify persistence mode
systemctl status nvidia-persistenced
nvidia-smi -q | grep -A 2 "Persistence Mode"
```

## 📊 Step 7: Install GPU Monitoring Tools

```bash
# Check Python version
python3 --version

# Install pip3
sudo dnf install -y python3-pip

# Install NVIDIA monitoring library
pip3 install nvidia-ml-py

# Verify monitoring functionality
python3 -c "
import pynvml
pynvml.nvmlInit()
print(f'NVML Version: {pynvml.nvmlSystemGetNVMLVersion()}')
device_count = pynvml.nvmlDeviceGetCount()
print(f'Detected {device_count} GPU devices')
for i in range(device_count):
    handle = pynvml.nvmlDeviceGetHandleByIndex(i)
    name = pynvml.nvmlDeviceGetName(handle)
    memory_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
    temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
    print(f'GPU {i}: {name} - Temp: {temp}°C - Memory: {memory_info.total//1024//1024//1024}GB')
"
```

## ⚡ Step 8: GPU Performance Tuning

```bash
# View supported clock frequencies
nvidia-smi -q -d SUPPORTED_CLOCKS | head -30

# View current clock settings
nvidia-smi -q -d CLOCK

# Set maximum performance mode
sudo nvidia-smi -ac 4000,1965
```

## 🚀 Step 9: Verify System Services

```bash
# Check all NVIDIA services
systemctl list-unit-files | grep nvidia

# Check key service status
systemctl is-active nvidia-persistenced nvidia-powerd
systemctl is-enabled nvidia-persistenced nvidia-powerd
```

## ✅ Step 10: Complete Verification

```bash
echo "🔍 NVIDIA GPU Environment Complete Verification"
echo "=============================================="

# Driver version
echo "1. Driver Version:"
nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1

# CUDA version
echo "2. CUDA Version:"
nvcc --version | grep "release"

# GPU count
echo "3. GPU Device Count:"
nvidia-smi --list-gpus | wc -l

# Persistence mode
echo "4. Persistence Mode:"
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader,nounits | head -1

# Service status
echo "5. Service Status:"
systemctl is-active nvidia-persistenced

# Python library
echo "6. Python NVML:"
python3 -c "import pynvml; pynvml.nvmlInit(); print('✅ OK')" 2>/dev/null || echo "❌ Error"

# CUDA program
echo "7. CUDA Program:"
/tmp/cuda_test > /dev/null 2>&1 && echo "✅ OK" || echo "❌ Error"

echo "=============================================="
echo "🎉 Verification Complete!"
```

## 🎯 Installation Results

- **Driver Version**: NVIDIA 580.65.06
- **CUDA Version**: 13.0  
- **GPU Devices**: 4x NVIDIA Graphics Device
- **Total Memory**: 716GB (4x 179GB)
- **Persistence Mode**: Enabled
- **System Services**: Running normally
- **Monitoring Tools**: Installed
- **Performance Tuning**: Configured
