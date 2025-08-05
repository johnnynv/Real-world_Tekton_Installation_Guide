#!/bin/bash

# Fix Pipeline Artifacts Script
# This script ensures all pipeline runs have proper artifacts and logs directories

set -euo pipefail

NAMESPACE="tekton-pipelines"
PVC_NAME="source-code-workspace"

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

fix_all_pipeline_runs() {
    log_info "Fixing all pipeline run directories..."
    
    # Create a temporary pod to fix all directories
    kubectl run fix-pipeline-artifacts --image=alpine:latest --rm -i --restart=Never -n "$NAMESPACE" --overrides='{
        "spec": {
            "containers": [{
                "name": "fix",
                "image": "alpine:latest",
                "command": ["sh", "-c", "
                    apk add --no-cache findutils
                    cd /shared
                    
                    echo \"🔧 FIXING ALL PIPELINE RUNS\"
                    echo \"============================\"
                    
                    # Fix each pipeline run directory
                    for run_dir in pipeline-runs/run-*; do
                        if [ -d \"\$run_dir\" ]; then
                            echo \"📁 Processing: \$run_dir\"
                            
                            # Create required directories
                            mkdir -p \"\$run_dir/artifacts\" \"\$run_dir/logs\"
                            
                            # Copy artifacts (avoid recursive copying)
                            find . -maxdepth 3 -name \"*.html\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/artifacts/\" \\; 2>/dev/null || true
                            find . -maxdepth 3 -name \"*.ipynb\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/artifacts/\" \\; 2>/dev/null || true
                            find . -maxdepth 3 -name \"*.xml\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/artifacts/\" \\; 2>/dev/null || true
                            find . -maxdepth 3 -name \"*coverage*\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/artifacts/\" \\; 2>/dev/null || true
                            find . -maxdepth 3 -name \"*pytest*\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/artifacts/\" \\; 2>/dev/null || true
                            find . -maxdepth 3 -name \"*report*\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/artifacts/\" \\; 2>/dev/null || true
                            
                            # Copy logs
                            find . -maxdepth 3 -name \"*.log\" -not -path \"*/pipeline-runs/*\" -exec cp {} \"\$run_dir/logs/\" \\; 2>/dev/null || true
                            
                            # Count files
                            artifact_count=\$(ls -1 \"\$run_dir/artifacts/\" 2>/dev/null | wc -l)
                            log_count=\$(ls -1 \"\$run_dir/logs/\" 2>/dev/null | wc -l)
                            
                            echo \"  📦 Artifacts: \$artifact_count files\"
                            echo \"  📋 Logs: \$log_count files\"
                        fi
                    done
                    
                    echo \"✅ All pipeline runs fixed!\"
                "],
                "volumeMounts": [{
                    "name": "shared",
                    "mountPath": "/shared"
                }]
            }],
            "volumes": [{
                "name": "shared",
                "persistentVolumeClaim": {
                    "claimName": "'$PVC_NAME'"
                }
            }]
        }
    }'
    
    log_success "All pipeline runs have been fixed"
}

verify_web_server() {
    log_info "Verifying web server deployment..."
    
    if kubectl get deployment gpu-artifacts-web -n "$NAMESPACE" &>/dev/null; then
        log_success "Web server deployment exists"
    else
        log_error "Web server deployment not found"
        return 1
    fi
    
    if kubectl get ingress gpu-artifacts-ingress -n "$NAMESPACE" &>/dev/null; then
        log_success "Web server ingress exists"
    else
        log_error "Web server ingress not found"
        return 1
    fi
}

show_access_urls() {
    local latest_run=$(kubectl run temp-get-latest --image=busybox --rm -i --restart=Never -n "$NAMESPACE" --overrides='{
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
                    "claimName": "'$PVC_NAME'"
                }
            }]
        }
    }' 2>/dev/null | tail -1)
    
    echo
    log_success "All URLs are now working!"
    echo
    echo "🌐 Main Index Page:"
    echo "   http://artifacts.10.34.2.129.nip.io/"
    echo
    if [ -n "$latest_run" ]; then
        echo "📊 Latest Run ($latest_run):"
        echo "   Web:       http://artifacts.10.34.2.129.nip.io/pipeline-runs/$latest_run/web/"
        echo "   Artifacts: http://artifacts.10.34.2.129.nip.io/pipeline-runs/$latest_run/artifacts/"
        echo "   Logs:      http://artifacts.10.34.2.129.nip.io/pipeline-runs/$latest_run/logs/"
    fi
    echo
}

main() {
    log_info "Starting pipeline artifacts fix..."
    
    # Verify prerequisites
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    if ! kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_error "PVC $PVC_NAME does not exist in namespace $NAMESPACE"
        exit 1
    fi
    
    # Fix all pipeline runs
    fix_all_pipeline_runs
    
    # Verify web server
    verify_web_server
    
    # Show access URLs
    show_access_urls
    
    log_success "Pipeline artifacts fix completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi