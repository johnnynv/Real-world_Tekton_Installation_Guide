# Tekton Hardware Requirements

This document lists the minimum and production-level hardware requirements for installing Tekton, both with and without GPU support.

## 1. Without GPU

### 1. Minimum Hardware Requirements

- CPU: 2 cores
- Memory: 4 GB
- Storage: 20 GB
- Network: Gigabit Ethernet
- Number of nodes: 1 (single-node test environment)

### 2. Production-Level Hardware Requirements

- CPU: 4 cores or more
- Memory: 16 GB or more
- Storage: 100 GB or more (SSD recommended)
- Network: Gigabit Ethernet
- Number of nodes: 3 or more (high-availability cluster)

## 2. With GPU

### 1. Minimum Hardware Requirements

- CPU: 4 cores
- Memory: 16 GB
- Storage: 50 GB
- GPU: 1 NVIDIA GPU (e.g., T4, A10, A100, CUDA-capable)
- Network: Gigabit Ethernet
- Number of nodes: 1 (single-node test environment)

### 2. Production-Level Hardware Requirements

- CPU: 8 cores or more
- Memory: 64 GB or more
- Storage: 500 GB or more (SSD recommended)
- GPU: 2 or more NVIDIA GPUs (e.g., A100, H100, actual number depends on workload)
- Network: 10 Gigabit Ethernet
- Number of nodes: 3 or more (high-availability cluster)

> Note: Actual requirements should be adjusted based on your business scenario, number of concurrent tasks, and data volume.
