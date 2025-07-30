# Troubleshooting and Development Files

This directory contains debug versions, iterative development files, and troubleshooting resources that were created during the development of the GPU pipelines.

## 📁 Directory Structure

### `pipelines/`
Contains various iterations and debug versions of the main workflows:
- Early development versions
- Failed experiments and lessons learned
- Specific issue reproduction cases
- Alternative implementation approaches

### `tasks/`
Contains debug versions of individual tasks:
- Environment setup iterations
- Papermill execution debugging
- Permission and security experiments
- RMM initialization attempts

## 🐛 Common Issues and Solutions

### Issue Categories Found During Development:

#### 1. **RMM (RAPIDS Memory Manager) Issues**
- **Files**: `rmm-verification-test.yaml`
- **Problems**: Memory allocation failures, improper initialization
- **Solutions**: Init container patterns, proper RMM setup

#### 2. **Container Permissions**
- **Files**: Various files with `root`, `simple`, `fixed` suffixes
- **Problems**: `git: command not found`, package installation failures
- **Solutions**: `securityContext: runAsUser: 0`

#### 3. **Dependency Management**
- **Files**: Files with `production`, `init`, `complete` variations
- **Problems**: Missing Python packages, PATH issues
- **Solutions**: Proper poetry setup, pip fallbacks

#### 4. **GPU Memory Exhaustion**
- **Files**: Various `simple` vs `complete` workflow versions
- **Problems**: `MemoryError` with large datasets
- **Solutions**: Dataset subsampling in lite versions

#### 5. **GitHub Repository Access**
- **Files**: Multiple git clone variations
- **Problems**: Private repository authentication
- **Solutions**: GitHub token integration

## 🔧 How to Use These Files

### For Learning
Review the progression from simple to complex implementations to understand the evolution of solutions.

### For Debugging
If you encounter similar issues, check if there's a specific debug file that reproduces your problem.

### For Development
Use these as reference implementations for alternative approaches.

## ⚠️ Important Notes

- **These files are NOT for production use**
- **They may contain outdated configurations**
- **Some may be intentionally broken for testing purposes**
- **Use the files in `examples/production/` for actual deployments**

## 📚 Learning Path

If you're new to this codebase, we recommend this learning sequence:

1. Start with `examples/production/README.md`
2. Review the final working pipelines
3. Then come back here to understand the development journey
4. Compare different approaches to see what worked and what didn't

## 🔍 File Naming Convention

- `*-simple-*`: Basic implementations
- `*-complete-*`: Full-featured attempts
- `*-fixed-*`: Bug fix iterations
- `*-test-*`: Testing and validation versions
- `*-debug-*`: Specific debugging scenarios
- `*-original-*`: Based on original notebook implementations

This collection represents months of iterative development and problem-solving in the GPU computing pipeline space. 