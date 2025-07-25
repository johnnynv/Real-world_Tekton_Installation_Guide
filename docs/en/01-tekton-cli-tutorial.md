# Tekton CLI Getting Started Tutorial

This tutorial will guide you step-by-step through Tekton's core concepts and hands-on practice using the `tkn` command-line tool.

## 📋 Table of Contents

1. [Environment Setup](#environment-setup)
2. [Tekton Core Concepts](#tekton-core-concepts)
3. [Task Basics](#task-basics)
4. [Pipeline Operations](#pipeline-operations)
5. [PipelineRun Management](#pipelinerun-management)
6. [Dashboard UI Navigation](#dashboard-ui-navigation)
7. [Common CLI Commands](#common-cli-commands)
8. [Troubleshooting](#troubleshooting)

## 🔧 Environment Setup

### 1. Check Tekton Environment

```bash
# Check Tekton namespaces
kubectl get namespaces | grep tekton

# Check Tekton component status
kubectl get pods -n tekton-pipelines

# Check tkn CLI version
tkn version
```

### 2. Install tkn CLI Tool (if not installed)

```bash
# Download latest tkn CLI
curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | \
  grep "browser_download_url.*Linux_x86_64" | \
  cut -d '"' -f 4 | xargs curl -LO

# Extract and install
tar xzf tkn_*_Linux_x86_64.tar.gz
sudo mv tkn /usr/local/bin/
rm tkn_*_Linux_x86_64.tar.gz

# Verify installation
tkn version
```

## 📚 Tekton Core Concepts

### Task
- **Definition**: The smallest executable unit containing a series of steps
- **Features**: Reusable, parameterizable
- **Purpose**: Execute specific operations like build, test, deploy

### Pipeline
- **Definition**: An ordered collection of multiple Tasks
- **Features**: Defines dependencies and execution order between tasks
- **Purpose**: Implement complex CI/CD workflows

### PipelineRun
- **Definition**: A concrete execution instance of a Pipeline
- **Features**: Contains actual parameter values and runtime status
- **Purpose**: Trigger and monitor Pipeline execution

### TaskRun
- **Definition**: A concrete execution instance of a Task
- **Features**: Automatically created by PipelineRun or manually created
- **Purpose**: Execute specific tasks and record results

## 🎯 Task Basics

### 1. View Existing Tasks

```bash
# List all Tasks
tkn task list

# Describe specific Task
tkn task describe hello-world

# View Task in YAML format
kubectl get task hello-world -n tekton-pipelines -o yaml
```

### 2. Create and Apply Task

```bash
# Apply example Task
kubectl apply -f examples/tasks/hello-world-task.yaml

# Verify Task creation
tkn task list | grep hello-world
```

### 3. Run Task

```bash
# Start Task manually
tkn task start hello-world -n tekton-pipelines

# Check TaskRun status
tkn taskrun list

# Describe TaskRun details
tkn taskrun describe <taskrun-name>

# View TaskRun logs
tkn taskrun logs <taskrun-name>
```

### 📊 View Tasks in Dashboard

1. Access Tekton Dashboard (usually at `http://localhost:9097`)
2. Navigate to "Tasks" page
3. View Task list and details
4. Click on TaskRun to see execution logs and status

## 🔄 Pipeline Operations

### 1. View Existing Pipelines

```bash
# List all Pipelines
tkn pipeline list

# Describe Pipeline details
tkn pipeline describe hello-world-pipeline

# View Pipeline graphical representation
tkn pipeline describe hello-world-pipeline --graph
```

### 2. Create and Apply Pipeline

```bash
# Apply example Pipeline
kubectl apply -f examples/pipelines/hello-world-pipeline.yaml

# Verify Pipeline creation
tkn pipeline list | grep hello-world
```

### 3. Run Pipeline

```bash
# Start Pipeline manually
tkn pipeline start hello-world-pipeline -n tekton-pipelines

# Or use interactive start
tkn pipeline start hello-world-pipeline -n tekton-pipelines --use-pipelinerun-prefix

# View all Pipeline runs
tkn pipelinerun list
```

## 🚀 PipelineRun Management

### 1. View PipelineRun Status

```bash
# List all PipelineRuns
tkn pipelinerun list

# Describe specific PipelineRun
tkn pipelinerun describe <pipelinerun-name>

# Follow PipelineRun logs in real-time
tkn pipelinerun logs <pipelinerun-name> -f

# View PipelineRun graphical status
tkn pipelinerun describe <pipelinerun-name> --graph
```

### 2. Use PipelineRun Resource Files

```bash
# Apply PipelineRun resource file
kubectl apply -f examples/pipelines/hello-world-pipeline-run.yaml

# View newly created PipelineRun
kubectl get pipelinerun -n tekton-pipelines -l app=tekton-example
```

### 3. Manage PipelineRuns

```bash
# Cancel running PipelineRun
tkn pipelinerun cancel <pipelinerun-name>

# Delete PipelineRun
tkn pipelinerun delete <pipelinerun-name>

# Delete all completed PipelineRuns
tkn pipelinerun delete --all -n tekton-pipelines
```

## 🖥️ Dashboard UI Navigation

### Access Dashboard

```bash
# Check Dashboard service status
kubectl get service -n tekton-pipelines | grep dashboard

# Access via port-forward
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097
```

### Dashboard Features

1. **Overview**
   - View overview of all Tekton resources in the cluster
   - Display recent run status and statistics

2. **Pipelines**
   - Browse all Pipeline definitions
   - View Pipeline graphical representation
   - Start new PipelineRuns

3. **PipelineRuns**
   - View status of all PipelineRuns
   - Monitor execution progress in real-time
   - View detailed execution logs

4. **Tasks**
   - Browse all Task definitions
   - View Task detailed configuration

5. **TaskRuns**
   - View status of all TaskRuns
   - View task execution logs

## 🛠️ Common CLI Commands

### View Commands

```bash
# View all resources
tkn list

# View help information
tkn --help
tkn task --help
tkn pipeline --help

# Output in different formats
tkn pipelinerun list -o json
tkn pipelinerun list -o yaml
```

### Log Commands

```bash
# View latest PipelineRun logs
tkn pipelinerun logs --last

# Follow log output
tkn pipelinerun logs <name> -f

# View specific Task logs
tkn pipelinerun logs <name> -t <task-name>
```

### Cleanup Commands

```bash
# Delete all completed runs
tkn pipelinerun delete --all

# Delete runs keeping last N
tkn pipelinerun delete --keep 5

# Force delete
tkn pipelinerun delete <name> --force
```

## 🔍 Troubleshooting

### 1. Check Resource Status

```bash
# Check Pod status
kubectl get pods -n tekton-pipelines

# Describe Pod details
kubectl describe pod <pod-name> -n tekton-pipelines

# View Pod logs
kubectl logs <pod-name> -n tekton-pipelines
```

### 2. Common Issues

**Task/Pipeline Not Found**
```bash
# Check if resources exist
kubectl get task,pipeline -n tekton-pipelines

# Check namespace
tkn task list -n tekton-pipelines
```

**Permission Issues**
```bash
# Check ServiceAccount
kubectl get serviceaccount -n tekton-pipelines

# Check RBAC configuration
kubectl get rolebinding,clusterrolebinding | grep tekton
```

**Execution Failures**
```bash
# View failure details
tkn pipelinerun describe <failed-run-name>

# View related events
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'
```

## 📝 Hands-on Exercises

### Exercise 1: Create Simple Task

1. Create a Task that displays current time
2. Run the Task and view output
3. Check execution results in Dashboard

### Exercise 2: Create Pipeline

1. Create a Pipeline with multiple Tasks
2. Set up dependencies between Tasks
3. Run Pipeline and monitor execution

### Exercise 3: Parameterized Configuration

1. Add parameters to Tasks
2. Pass parameters in Pipeline
3. Provide parameter values when running via CLI

## 🎉 Summary

Through this tutorial, you have learned:

- ✅ Tekton core concepts (Task, Pipeline, PipelineRun)
- ✅ Managing Tekton resources using `tkn` CLI tool
- ✅ Viewing and monitoring execution status in Dashboard UI
- ✅ Common troubleshooting methods

Next recommended learning:
- Tekton Triggers and Webhook integration
- Advanced parameter configuration and resource management
- Integration with Git and container registries 