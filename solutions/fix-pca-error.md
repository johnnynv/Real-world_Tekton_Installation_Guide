# 🔧 修复PCA KeyError的解决方案

## 问题诊断

**错误现象：**
```
KeyError: 'pca'
在 sc.pl.pca_variance_ratio(adata, log=True, n_pcs=100) 步骤
```

**根本原因：**
1. PCA计算步骤(`sc.tl.pca()`)没有正确执行
2. 或者PCA结果没有保存到`adata.uns['pca']`
3. 但后续的可视化步骤期望找到PCA结果

## 解决方案

### 方案1：修复notebook中的PCA流程
创建修复版本的PCA执行逻辑：

```python
# 确保PCA正确执行和保存
import scanpy as sc
import pandas as pd

# 在PCA之前确保数据准备就绪
if 'highly_variable' in adata.var.columns:
    # 只使用高变基因进行PCA
    adata.raw = adata
    adata = adata[:, adata.var.highly_variable]

# 执行PCA
print("🔄 Computing PCA...")
sc.tl.pca(adata, svd_solver='arpack', n_comps=50)

# 验证PCA结果是否正确保存
if 'pca' in adata.uns:
    print("✅ PCA computation successful")
    print(f"   - PCA shape: {adata.obsm['X_pca'].shape}")
    print(f"   - Variance ratio shape: {adata.uns['pca']['variance_ratio'].shape}")
else:
    print("❌ PCA computation failed")
    # 手动重新计算PCA
    from sklearn.decomposition import PCA
    pca_sklearn = PCA(n_components=50)
    X_pca = pca_sklearn.fit_transform(adata.X.toarray() if hasattr(adata.X, 'toarray') else adata.X)
    adata.obsm['X_pca'] = X_pca
    adata.uns['pca'] = {
        'variance': pca_sklearn.explained_variance_,
        'variance_ratio': pca_sklearn.explained_variance_ratio_
    }

# 现在可以安全地进行PCA可视化
try:
    sc.pl.pca_variance_ratio(adata, log=True, n_pcs=50, show=False)
    print("✅ PCA variance ratio plot successful")
except Exception as e:
    print(f"⚠️  PCA plotting failed: {e}")
    # 使用matplotlib直接绘制
    import matplotlib.pyplot as plt
    plt.figure(figsize=(8, 5))
    plt.plot(range(1, len(adata.uns['pca']['variance_ratio'])+1), 
             adata.uns['pca']['variance_ratio'], 'o-')
    plt.xlabel('Principal Component')
    plt.ylabel('Variance Ratio')
    plt.title('PCA Variance Ratio')
    plt.show()
```

### 方案2：创建修复Task

修复版的papermill执行，在PCA步骤添加错误处理：

```yaml
# 在papermill参数中添加错误处理参数
papermill ${INPUT_NOTEBOOK} ${OUTPUT_NOTEBOOK} \
  --log-output \
  --log-level DEBUG \
  --progress-bar \
  --parameters-yaml <(cat << EOF
# 添加错误恢复参数
error_handling: "continue"
pca_fallback: true
skip_problematic_plots: true
EOF
)
```

### 方案3：预处理notebook

在执行papermill之前预处理notebook，修复已知问题：

```bash
# 使用Python脚本修复notebook
python3 -c "
import nbformat
import re

# 读取notebook
nb = nbformat.read('input.ipynb', as_version=4)

# 修复PCA相关的cell
for i, cell in enumerate(nb.cells):
    if cell.cell_type == 'code':
        source = cell.source
        
        # 在PCA variance ratio plot之前添加验证
        if 'sc.pl.pca_variance_ratio' in source:
            new_source = '''
# 验证PCA结果是否存在
if 'pca' not in adata.uns:
    print(\"⚠️  PCA results not found, recomputing...\")
    sc.tl.pca(adata, svd_solver='arpack', n_comps=50)

# 原始代码
''' + source
            cell.source = new_source

# 保存修复后的notebook
nbformat.write(nb, 'fixed_input.ipynb')
"

# 使用修复后的notebook
papermill fixed_input.ipynb output.ipynb
```

## 立即修复命令

### 快速修复当前Pipeline
如需立即修复当前问题：

```bash
# 创建修复版Pipeline
cat > /tmp/gpu-real-8-step-workflow-pca-fixed.yaml << 'EOF'
# [在Step3中添加PCA错误处理逻辑]
EOF

kubectl apply -f /tmp/gpu-real-8-step-workflow-pca-fixed.yaml
```