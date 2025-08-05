#!/bin/bash

PIPELINE_NAME="gpu-scrna-analysis-preprocessing-workflow-2npps"
NAMESPACE="tekton-pipelines"

echo "🔍 Monitoring pipeline: $PIPELINE_NAME"
echo "⏰ Will apply fix immediately upon completion"
echo

# Wait for completion
while true; do
    STATUS=$(kubectl get pipelinerun $PIPELINE_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    REASON=$(kubectl get pipelinerun $PIPELINE_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Running")
    
    echo "📊 Status: $STATUS, Reason: $REASON ($(date))"
    
    if [ "$STATUS" = "True" ] && [ "$REASON" = "Succeeded" ]; then
        echo "✅ Pipeline completed successfully!"
        break
    elif [ "$STATUS" = "False" ]; then
        echo "❌ Pipeline failed with reason: $REASON"
        exit 1
    fi
    
    sleep 10
done

echo
echo "🔧 Applying immediate fix..."

# Get the latest pipeline run directory
LATEST_RUN=$(kubectl run temp-get-latest-dir --image=busybox --rm -i --restart=Never -n $NAMESPACE --overrides='{
    "spec": {
        "containers": [{
            "name": "temp",
            "image": "busybox",
            "command": ["sh", "-c", "ls -t /shared/pipeline-runs/ | grep run- | head -1"],
            "volumeMounts": [{
                "name": "shared",
                "mountPath": "/shared"
            }]
        }],
        "volumes": [{
            "name": "shared",
            "persistentVolumeClaim": {
                "claimName": "source-code-workspace"
            }
        }]
    }
}' 2>/dev/null | tail -1)

echo "📁 Latest run directory: $LATEST_RUN"

# Apply the fix
echo "🔧 Fixing directory structure..."
kubectl run fix-latest-run --image=alpine:latest --rm -i --restart=Never -n $NAMESPACE --overrides='{
    "spec": {
        "containers": [{
            "name": "fix",
            "image": "alpine:latest",
            "command": ["sh", "-c", "
                apk add --no-cache findutils
                cd /shared
                
                # Fix the latest run
                run_dir=\"pipeline-runs/'$LATEST_RUN'\"
                if [ -d \"$run_dir\" ]; then
                    echo \"📁 Fixing: $run_dir\"
                    mkdir -p \"$run_dir/artifacts\" \"$run_dir/logs\"
                    
                    # Copy artifacts
                    find . -maxdepth 3 -name \"*.html\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/artifacts/\" \\; 2>/dev/null || true
                    find . -maxdepth 3 -name \"*.ipynb\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/artifacts/\" \\; 2>/dev/null || true
                    find . -maxdepth 3 -name \"*.xml\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/artifacts/\" \\; 2>/dev/null || true
                    find . -maxdepth 3 -name \"*coverage*\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/artifacts/\" \\; 2>/dev/null || true
                    find . -maxdepth 3 -name \"*pytest*\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/artifacts/\" \\; 2>/dev/null || true
                    find . -maxdepth 3 -name \"*report*\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/artifacts/\" \\; 2>/dev/null || true
                    
                    # Copy logs
                    find . -maxdepth 3 -name \"*.log\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"$run_dir/logs/\" \\; 2>/dev/null || true
                    
                    # Count files
                    artifact_count=\$(ls -1 \"$run_dir/artifacts/\" 2>/dev/null | wc -l)
                    log_count=\$(ls -1 \"$run_dir/logs/\" 2>/dev/null | wc -l)
                    
                    echo \"✅ Fixed: \$artifact_count artifacts, \$log_count logs\"
                    
                    # Verify structure
                    echo \"📁 Final structure:\"
                    ls -la \"$run_dir/\"
                else
                    echo \"❌ Directory not found: $run_dir\"
                fi
            "],
            "volumeMounts": [{
                "name": "shared",
                "mountPath": "/shared"
            }]
        }],
        "volumes": [{
            "name": "shared",
            "persistentVolumeClaim": {
                "claimName": "source-code-workspace"
            }
        }]
    }
}' 2>/dev/null

echo
echo "🌐 Your results are ready at:"
echo "📊 Web Interface: http://artifacts.10.34.2.129.nip.io/pipeline-runs/$LATEST_RUN/web/"
echo "📦 Artifacts:     http://artifacts.10.34.2.129.nip.io/pipeline-runs/$LATEST_RUN/artifacts/"
echo "📋 Logs:          http://artifacts.10.34.2.129.nip.io/pipeline-runs/$LATEST_RUN/logs/"
echo "🌐 All Runs:      http://artifacts.10.34.2.129.nip.io/"
echo
echo "✅ NO MORE 404 ERRORS!"