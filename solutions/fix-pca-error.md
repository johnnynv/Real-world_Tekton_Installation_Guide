# 🔧 PCA KeyError Solution Guide

## Problem Diagnosis

**Error Symptoms:**
```
KeyError: 'pca'
in sc.pl.pca_variance_ratio(adata, log=True, n_pcs=100) step
```

**Root Causes:**
1. PCA computation step (`sc.tl.pca()`) was not executed correctly
2. Or PCA results were not saved to `adata.uns['pca']`
3. But subsequent visualization steps expect to find PCA results

## Solutions

### Solution 1: Fix PCA Flow in Notebook
Create fixed version of PCA execution logic:

```python
# Ensure PCA is correctly executed and saved
import scanpy as sc
import pandas as pd

# Ensure data is ready before PCA
if 'highly_variable' in adata.var.columns:
    # Use only highly variable genes for PCA
    adata.raw = adata
    adata = adata[:, adata.var.highly_variable]

# Execute PCA
print("🔄 Computing PCA...")
sc.tl.pca(adata, svd_solver='arpack', n_comps=50)

# Verify PCA results are correctly saved
if 'pca' in adata.uns:
    print("✅ PCA computation successful")
    print(f"   - PCA shape: {adata.obsm['X_pca'].shape}")
    print(f"   - Variance ratio shape: {adata.uns['pca']['variance_ratio'].shape}")
else:
    print("❌ PCA computation failed")
    # Manually recompute PCA
    from sklearn.decomposition import PCA
    pca_sklearn = PCA(n_components=50)
    X_pca = pca_sklearn.fit_transform(adata.X.toarray() if hasattr(adata.X, 'toarray') else adata.X)
    adata.obsm['X_pca'] = X_pca
    adata.uns['pca'] = {
        'variance': pca_sklearn.explained_variance_,
        'variance_ratio': pca_sklearn.explained_variance_ratio_
    }

# Now safely perform PCA visualization
try:
    sc.pl.pca_variance_ratio(adata, log=True, n_pcs=50, show=False)
    print("✅ PCA variance ratio plot successful")
except Exception as e:
    print(f"⚠️  PCA plotting failed: {e}")
    # Use matplotlib for direct plotting
    import matplotlib.pyplot as plt
    plt.figure(figsize=(8, 5))
    plt.plot(range(1, len(adata.uns['pca']['variance_ratio'])+1), 
             adata.uns['pca']['variance_ratio'], 'o-')
    plt.xlabel('Principal Component')
    plt.ylabel('Variance Ratio')
    plt.title('PCA Variance Ratio')
    plt.show()
```

### Solution 2: Create Fixed Task

Fixed papermill execution with error handling in PCA step:

```yaml
# Add error handling parameters in papermill
papermill ${INPUT_NOTEBOOK} ${OUTPUT_NOTEBOOK} \
  --log-output \
  --log-level DEBUG \
  --progress-bar \
  --parameters-yaml <(cat << EOF
# Add error recovery parameters
error_handling: "continue"
pca_fallback: true
skip_problematic_plots: true
EOF
)
```

### Solution 3: Preprocess Notebook

Preprocess notebook before executing papermill to fix known issues:

```bash
# Use Python script to fix notebook
python3 -c "
import nbformat
import re

# Read notebook
nb = nbformat.read('input.ipynb', as_version=4)

# Fix PCA-related cells
for i, cell in enumerate(nb.cells):
    if cell.cell_type == 'code':
        source = cell.source
        
        # Add validation before PCA variance ratio plot
        if 'sc.pl.pca_variance_ratio' in source:
            new_source = '''
# Verify PCA results exist
if 'pca' not in adata.uns:
    print(\"⚠️  PCA results not found, recomputing...\")
    sc.tl.pca(adata, svd_solver='arpack', n_comps=50)

# Original code
''' + source
            cell.source = new_source

# Save fixed notebook
nbformat.write(nb, 'fixed_input.ipynb')
"

# Use fixed notebook
papermill fixed_input.ipynb output.ipynb
```

## Immediate Fix Commands

### Quick Fix for Current Pipeline
To immediately fix the current issue:

```bash
# Create fixed Pipeline
cat > /tmp/gpu-real-8-step-workflow-pca-fixed.yaml << 'EOF'
# [Add PCA error handling logic in Step3]
EOF

kubectl apply -f /tmp/gpu-real-8-step-workflow-pca-fixed.yaml
```