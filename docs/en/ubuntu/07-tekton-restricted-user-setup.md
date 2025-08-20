# Tekton Step 5: Creating Restricted User

This document explains how to create a user with restricted permissions for the Tekton Dashboard.

## Overview

The restricted user can only view the following resources:
- Pipelines
- PipelineRuns  
- Tasks
- TaskRuns
- EventListeners

This user cannot perform create, modify, delete operations, nor access sensitive resources like Secrets.

## Execution Steps

### 1. Run Configuration Script

Execute the following command to create the restricted user:

```bash
bash scripts/utils/setup-step5-restricted-user.sh
```

The script will automatically:
- Create service account `tekton-restricted-user`
- Configure ClusterRole and ClusterRoleBinding
- Set up Tekton Dashboard basic authentication
- Generate access credential files

### 2. Verify Configuration

Use the verification script to check if the configuration is correct:

```bash
bash scripts/utils/verify-step5-restricted-user.sh
```

The verification script will check:
- Whether RBAC resources are created correctly
- Whether user permissions are configured as expected
- Whether Dashboard is accessible
- Whether restricted operations are properly denied

## Access Information

After configuration is complete, you can access the Tekton Dashboard using the following information:

- **Username**: `user`
- **Password**: `user123`
- **Dashboard URL**: `http://tekton.10.34.2.129.nip.io`

## Permission Details

### Allowed Operations
- View all Pipelines and PipelineRuns
- View all Tasks and TaskRuns  
- View all EventListeners
- Browse Dashboard interface

### Prohibited Operations
- Create, modify, delete any Tekton resources
- Access Secrets or other sensitive data
- Perform cluster administration operations
- Modify RBAC configuration

## Related Files

The main files involved in this step:

- `examples/config/rbac/rbac-step5-tekton-restricted-user.yaml` - RBAC configuration
- `scripts/utils/setup-step5-restricted-user.sh` - Configuration script
- `scripts/utils/verify-step5-restricted-user.sh` - Verification script

## Troubleshooting

If you encounter problems, please check:

1. **Permission issues**: Ensure current user has sufficient permissions to create ClusterRole and ClusterRoleBinding
2. **Namespace issues**: Confirm that `tekton-pipelines` namespace exists
3. **Dashboard issues**: Check if Tekton Dashboard is running normally

You can run the verification script to get detailed diagnostic information.

## Important Notes on Dashboard Menu Behavior

### Expected Behavior
The Tekton Dashboard displays **all menu items statically**, regardless of user permissions. This is normal behavior:

- **Menu Display**: All menus (Pipelines, Tasks, Triggers, etc.) are always visible
- **Permission Enforcement**: Occurs when accessing resources, not when displaying menus
- **Access Control**: Clicking restricted menu items will show permission errors or empty lists

### Testing Restricted Access
To verify that permissions are working correctly:

**✅ Should work normally:**
- Pipelines - Should display pipeline list
- PipelineRuns - Should display execution history
- Tasks - Should display task list
- TaskRuns - Should display task execution history
- EventListeners - Should display event listeners

**❌ Should show permission errors or empty lists:**
- StepActions - Should show permission error or empty list
- ClusterTasks - Should show permission error or empty list
- CustomRuns - Should show permission error or empty list
- Triggers - Should show permission error or empty list
- TriggerBindings - Should show permission error or empty list
- TriggerTemplates - Should show permission error or empty list
- Interceptors - Should show permission error or empty list

This behavior is by design and ensures that the Dashboard UI remains consistent while enforcing access control at the API level.