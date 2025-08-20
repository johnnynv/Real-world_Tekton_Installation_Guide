# NVIDIA GPU 环境安装指南

本指南详细介绍如何在 Rocky Linux 10 系统上安装和配置完整的 NVIDIA GPU 环境。

## 🏁 步骤1：系统环境检查

```bash
# 检查操作系统版本
cat /etc/os-release

# 检查内核版本
uname -r

# 检查 GPU 硬件
lspci | grep -i nvidia

# 检查当前驱动状态
nvidia-smi
```

## 🛠️ 步骤2：安装开发工具和仓库

```bash
# 安装 EPEL 仓库
sudo dnf install -y epel-release

# 更新系统包
sudo dnf update -y

# 安装编译工具
sudo dnf install -y gcc kernel-devel kernel-headers dkms make bzip2

# 添加 NVIDIA 官方仓库
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo

# 更新仓库缓存
sudo dnf makecache

# 验证仓库
sudo dnf search nvidia-driver
```

## 🎯 步骤3：安装 NVIDIA 驱动

```bash
# 安装 NVIDIA 驱动
sudo dnf install -y nvidia-driver nvidia-driver-cuda

# 检查 DKMS 状态
dkms status

# 加载内核模块
sudo modprobe nvidia

# 检查模块加载
lsmod | grep nvidia

# 验证驱动
nvidia-smi
```

## 💻 步骤4：安装 CUDA Toolkit

```bash
# 安装 CUDA 13.0 Toolkit
sudo dnf install -y cuda-toolkit-13-0

# 配置环境变量（zsh）
echo 'export PATH=/usr/local/cuda-13.0/bin:$PATH' >> ~/.zshrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:$LD_LIBRARY_PATH' >> ~/.zshrc

# 临时设置环境变量
export PATH=/usr/local/cuda-13.0/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:$LD_LIBRARY_PATH

# 验证 NVCC
nvcc --version
```

## 🧪 步骤5：CUDA 功能验证

```bash
# 创建测试程序
cat > /tmp/cuda_test.cu << 'EOF'
#include <stdio.h>
#include <cuda_runtime.h>

__global__ void hello_cuda() {
    printf("Hello from GPU thread %d\n", threadIdx.x);
}

int main() {
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    printf("发现 %d 个 CUDA 设备\n", deviceCount);
    
    for (int device = 0; device < deviceCount; ++device) {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, device);
        printf("设备 %d: %s\n", device, deviceProp.name);
        printf("  计算能力: %d.%d\n", deviceProp.major, deviceProp.minor);
        printf("  显存: %.2f GB\n", deviceProp.totalGlobalMem / 1024.0 / 1024.0 / 1024.0);
    }
    
    hello_cuda<<<1, 5>>>();
    cudaDeviceSynchronize();
    
    return 0;
}
EOF

# 编译并运行
nvcc /tmp/cuda_test.cu -o /tmp/cuda_test
/tmp/cuda_test
```

## 🔄 步骤6：配置持久化模式

```bash
# 检查当前持久化状态
nvidia-smi -q | grep -A 2 "Persistence Mode"

# 检查服务状态
systemctl status nvidia-persistenced

# 启用并启动服务
sudo systemctl enable nvidia-persistenced
sudo systemctl start nvidia-persistenced

# 验证持久化模式
systemctl status nvidia-persistenced
nvidia-smi -q | grep -A 2 "Persistence Mode"
```

## 📊 步骤7：安装GPU监控工具

```bash
# 检查 Python 版本
python3 --version

# 安装 pip3
sudo dnf install -y python3-pip

# 安装 NVIDIA 监控库
pip3 install nvidia-ml-py

# 验证监控功能
python3 -c "
import pynvml
pynvml.nvmlInit()
print(f'NVML版本: {pynvml.nvmlSystemGetNVMLVersion()}')
device_count = pynvml.nvmlDeviceGetCount()
print(f'检测到 {device_count} 个GPU设备')
for i in range(device_count):
    handle = pynvml.nvmlDeviceGetHandleByIndex(i)
    name = pynvml.nvmlDeviceGetName(handle)
    memory_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
    temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
    print(f'GPU {i}: {name} - 温度: {temp}°C - 显存: {memory_info.total//1024//1024//1024}GB')
"
```

## ⚡ 步骤8：GPU性能调优

```bash
# 查看支持的时钟频率
nvidia-smi -q -d SUPPORTED_CLOCKS | head -30

# 查看当前时钟设置
nvidia-smi -q -d CLOCK

# 设置最大性能模式
sudo nvidia-smi -ac 4000,1965
```

## 🚀 步骤9：验证系统服务

```bash
# 检查所有 NVIDIA 服务
systemctl list-unit-files | grep nvidia

# 检查关键服务状态
systemctl is-active nvidia-persistenced nvidia-powerd
systemctl is-enabled nvidia-persistenced nvidia-powerd
```

## ✅ 步骤10：完整验证

```bash
echo "🔍 NVIDIA GPU 环境完整验证"
echo "========================="

# 驱动版本
echo "1. 驱动版本："
nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1

# CUDA 版本
echo "2. CUDA 版本："
nvcc --version | grep "release"

# GPU 数量
echo "3. GPU 设备数量："
nvidia-smi --list-gpus | wc -l

# 持久化模式
echo "4. 持久化模式："
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader,nounits | head -1

# 服务状态
echo "5. 服务状态："
systemctl is-active nvidia-persistenced

# Python 库
echo "6. Python NVML："
python3 -c "import pynvml; pynvml.nvmlInit(); print('✅ 正常')" 2>/dev/null || echo "❌ 异常"

# CUDA 程序
echo "7. CUDA 程序："
/tmp/cuda_test > /dev/null 2>&1 && echo "✅ 正常" || echo "❌ 异常"

echo "========================="
echo "🎉 验证完成！"
```

## 🎯 安装结果

- **驱动版本**：NVIDIA 580.65.06
- **CUDA 版本**：13.0  
- **GPU 设备**：4个 NVIDIA Graphics Device
- **显存总量**：716GB (4x 179GB)
- **持久化模式**：已启用
- **系统服务**：正常运行
- **监控工具**：已安装
- **性能调优**：已配置