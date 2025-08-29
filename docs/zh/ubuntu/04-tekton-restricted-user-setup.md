# Tekton 步骤5：创建受限权限用户

本文档说明如何为 Tekton Dashboard 创建一个具有受限权限的用户。

## 概述

受限用户仅能查看以下资源：
- Pipelines（流水线）
- PipelineRuns（流水线运行）  
- Tasks（任务）
- TaskRuns（任务运行）
- EventListeners（事件监听器）

该用户无法执行创建、修改、删除等操作，也无法访问敏感资源如 Secrets。

## 执行步骤

### 1. 运行配置脚本

执行以下命令创建受限用户：

```bash
bash scripts/utils/setup-step5-restricted-user.sh
```

脚本将自动：
- 创建服务账户 `tekton-restricted-user`
- 配置 ClusterRole 和 ClusterRoleBinding
- 设置 Tekton Dashboard 基本认证
- 生成访问凭据文件

### 2. 验证配置

使用验证脚本检查配置是否正确：

```bash
bash scripts/utils/verify-step5-restricted-user.sh
```

验证脚本将检查：
- RBAC 资源是否正确创建
- 用户权限是否按预期配置
- Dashboard 是否可访问
- 受限操作是否被正确拒绝

## 访问信息

配置完成后，您可以使用以下信息访问 Tekton Dashboard：

- **用户名**：`user`
- **密码**：`user123`
- **Dashboard 地址**：`http://tekton.10.34.2.129.nip.io`

## 权限详情

### 允许的操作
- 查看所有 Pipelines 和 PipelineRuns
- 查看所有 Tasks 和 TaskRuns  
- 查看所有 EventListeners
- 浏览 Dashboard 界面

### 禁止的操作
- 创建、修改、删除任何 Tekton 资源
- 访问 Secrets 或其他敏感数据
- 执行集群管理操作
- 修改 RBAC 配置

## 相关文件

本步骤涉及的主要文件：

- `examples/config/rbac/rbac-step5-tekton-restricted-user.yaml` - RBAC 配置
- `scripts/utils/setup-step5-restricted-user.sh` - 配置脚本
- `scripts/utils/verify-step5-restricted-user.sh` - 验证脚本

## 故障排除

如果遇到问题，请检查：

1. **权限问题**：确保当前用户有足够权限创建 ClusterRole 和 ClusterRoleBinding
2. **命名空间问题**：确认 `tekton-pipelines` 命名空间存在
3. **Dashboard 问题**：检查 Tekton Dashboard 是否正常运行

可以运行验证脚本获取详细的诊断信息。