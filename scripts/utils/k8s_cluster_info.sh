#!/bin/bash

# Kubernetes 集群信息展示脚本
# 快速查看集群状态、Pod、Service、Ingress 等关键信息

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 函数定义
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 kubectl
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    log_success "kubectl 连接正常"
}

# 显示集群基本信息
show_cluster_info() {
    print_section "集群基本信息"
    
    echo "集群信息:"
    kubectl cluster-info | head -5
    
    echo ""
    echo "API 版本:"
    kubectl version --short 2>/dev/null || kubectl version --client
    
    echo ""
    echo "集群节点:"
    kubectl get nodes -o wide
    
    echo ""
    echo "集群资源使用情况:"
    kubectl top nodes 2>/dev/null || echo "Metrics Server 未安装，无法显示资源使用情况"
}

# 显示命名空间信息
show_namespaces() {
    print_section "命名空间信息"
    
    echo "所有命名空间:"
    kubectl get namespaces -o wide
    
    echo ""
    echo "各命名空间中的 Pod 数量:"
    kubectl get pods --all-namespaces | awk 'NR>1 {count[$1]++} END {for (ns in count) printf "%-25s %d\n", ns, count[ns]}' | sort
}

# 显示 Pod 信息
show_pods() {
    print_section "Pod 信息"
    
    echo "所有命名空间中的 Pod 状态概览:"
    kubectl get pods --all-namespaces -o wide | head -20
    
    echo ""
    echo "Pod 状态统计:"
    kubectl get pods --all-namespaces --no-headers | awk '{print $4}' | sort | uniq -c
    
    echo ""
    echo "非 Running 状态的 Pod:"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running 2>/dev/null || echo "所有 Pod 都在 Running 状态"
    
    echo ""
    echo "重启次数最多的 Pod (Top 10):"
    kubectl get pods --all-namespaces --no-headers | awk '{if ($5 > 0) print $1, $2, $5}' | sort -k3 -nr | head -10
}

# 显示 Service 信息
show_services() {
    print_section "Service 信息"
    
    echo "所有命名空间中的 Service:"
    kubectl get services --all-namespaces -o wide
    
    echo ""
    echo "LoadBalancer 类型的 Service:"
    kubectl get services --all-namespaces --field-selector=spec.type=LoadBalancer 2>/dev/null || echo "未找到 LoadBalancer 类型的 Service"
    
    echo ""
    echo "NodePort 类型的 Service:"
    kubectl get services --all-namespaces --field-selector=spec.type=NodePort 2>/dev/null || echo "未找到 NodePort 类型的 Service"
}

# 显示 Ingress 信息
show_ingress() {
    print_section "Ingress 信息"
    
    echo "所有 Ingress:"
    kubectl get ingress --all-namespaces -o wide 2>/dev/null || echo "未找到 Ingress 资源"
    
    echo ""
    echo "IngressClass:"
    kubectl get ingressclass -o wide 2>/dev/null || echo "未找到 IngressClass 资源"
    
    echo ""
    echo "Ingress Controller Pods:"
    kubectl get pods --all-namespaces | grep -i ingress || echo "未找到 Ingress Controller"
}

# 显示存储信息
show_storage() {
    print_section "存储信息"
    
    echo "StorageClass:"
    kubectl get storageclass -o wide 2>/dev/null || echo "未找到 StorageClass"
    
    echo ""
    echo "PersistentVolume:"
    kubectl get pv -o wide 2>/dev/null || echo "未找到 PersistentVolume"
    
    echo ""
    echo "PersistentVolumeClaim:"
    kubectl get pvc --all-namespaces -o wide 2>/dev/null || echo "未找到 PersistentVolumeClaim"
}

# 显示配置信息
show_config() {
    print_section "配置信息"
    
    echo "ConfigMap 数量 (按命名空间):"
    kubectl get configmap --all-namespaces --no-headers | awk '{count[$1]++} END {for (ns in count) printf "%-25s %d\n", ns, count[ns]}' | sort
    
    echo ""
    echo "Secret 数量 (按命名空间):"
    kubectl get secret --all-namespaces --no-headers | awk '{count[$1]++} END {for (ns in count) printf "%-25s %d\n", ns, count[ns]}' | sort
}

# 显示 RBAC 信息
show_rbac() {
    print_section "RBAC 信息"
    
    echo "ServiceAccount 数量 (按命名空间):"
    kubectl get serviceaccount --all-namespaces --no-headers | awk '{count[$1]++} END {for (ns in count) printf "%-25s %d\n", ns, count[ns]}' | sort
    
    echo ""
    echo "ClusterRole 数量:"
    kubectl get clusterrole --no-headers | wc -l
    
    echo ""
    echo "ClusterRoleBinding 数量:"
    kubectl get clusterrolebinding --no-headers | wc -l
    
    echo ""
    echo "Role 数量 (按命名空间):"
    kubectl get role --all-namespaces --no-headers | awk '{count[$1]++} END {for (ns in count) printf "%-25s %d\n", ns, count[ns]}' | sort
}

# 显示工作负载信息
show_workloads() {
    print_section "工作负载信息"
    
    echo "Deployment:"
    kubectl get deployment --all-namespaces -o wide 2>/dev/null || echo "未找到 Deployment"
    
    echo ""
    echo "DaemonSet:"
    kubectl get daemonset --all-namespaces -o wide 2>/dev/null || echo "未找到 DaemonSet"
    
    echo ""
    echo "StatefulSet:"
    kubectl get statefulset --all-namespaces -o wide 2>/dev/null || echo "未找到 StatefulSet"
    
    echo ""
    echo "Job:"
    kubectl get job --all-namespaces -o wide 2>/dev/null || echo "未找到 Job"
    
    echo ""
    echo "CronJob:"
    kubectl get cronjob --all-namespaces -o wide 2>/dev/null || echo "未找到 CronJob"
}

# 显示 Tekton 相关信息
show_tekton() {
    print_section "Tekton 组件信息"
    
    echo "Tekton Pipeline Pods:"
    kubectl get pods -n tekton-pipelines 2>/dev/null || echo "Tekton Pipeline 未安装"
    
    echo ""
    echo "Tekton CRDs:"
    kubectl get crd | grep tekton 2>/dev/null || echo "未找到 Tekton CRDs"
    
    echo ""
    echo "最近的 PipelineRuns (Top 5):"
    kubectl get pipelinerun --all-namespaces --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -6 || echo "未找到 PipelineRuns"
    
    echo ""
    echo "最近的 TaskRuns (Top 5):"
    kubectl get taskrun --all-namespaces --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -6 || echo "未找到 TaskRuns"
}

# 显示网络信息
show_network() {
    print_section "网络信息"
    
    echo "NetworkPolicy:"
    kubectl get networkpolicy --all-namespaces 2>/dev/null || echo "未找到 NetworkPolicy"
    
    echo ""
    echo "Endpoints:"
    kubectl get endpoints --all-namespaces | head -10
    
    echo ""
    echo "DNS 配置:"
    kubectl get svc -n kube-system | grep dns
}

# 显示资源使用情况
show_resource_usage() {
    print_section "资源使用情况"
    
    echo "节点资源使用:"
    kubectl top nodes 2>/dev/null || echo "Metrics Server 未安装"
    
    echo ""
    echo "Pod 资源使用 (Top 10):"
    kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -11 || echo "Metrics Server 未安装"
}

# 显示事件信息
show_events() {
    print_section "最近事件"
    
    echo "最近的集群事件 (最新 20 条):"
    kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp | tail -20
    
    echo ""
    echo "Warning 事件:"
    kubectl get events --all-namespaces --field-selector type=Warning 2>/dev/null | head -10 || echo "未找到 Warning 事件"
}

# 显示有用的命令
show_useful_commands() {
    print_section "常用 Kubernetes 命令"
    
    echo -e "${YELLOW}基本信息查看:${NC}"
    echo "  kubectl cluster-info                    # 集群信息"
    echo "  kubectl get nodes -o wide               # 节点信息"
    echo "  kubectl get pods --all-namespaces      # 所有 Pod"
    echo "  kubectl get svc --all-namespaces       # 所有 Service"
    echo "  kubectl get ingress --all-namespaces   # 所有 Ingress"
    echo ""
    
    echo -e "${YELLOW}资源监控:${NC}"
    echo "  kubectl top nodes                       # 节点资源使用"
    echo "  kubectl top pods --all-namespaces      # Pod 资源使用"
    echo "  kubectl describe node <node-name>      # 节点详情"
    echo "  kubectl describe pod <pod-name> -n <ns> # Pod 详情"
    echo ""
    
    echo -e "${YELLOW}日志和调试:${NC}"
    echo "  kubectl logs <pod-name> -n <namespace>  # Pod 日志"
    echo "  kubectl logs -f <pod-name> -n <ns>      # 实时日志"
    echo "  kubectl exec -it <pod-name> -n <ns> -- /bin/bash # 进入 Pod"
    echo "  kubectl get events --sort-by=.metadata.creationTimestamp # 事件"
    echo ""
    
    echo -e "${YELLOW}Tekton 相关:${NC}"
    echo "  kubectl get pipelinerun -n tekton-pipelines # PipelineRun"
    echo "  kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines -f # EventListener 日志"
    echo "  kubectl get eventlistener -n tekton-pipelines # EventListener 状态"
    echo ""
    
    echo -e "${YELLOW}配置和 RBAC:${NC}"
    echo "  kubectl get configmap --all-namespaces # ConfigMap"
    echo "  kubectl get secret --all-namespaces    # Secret"
    echo "  kubectl get serviceaccount --all-namespaces # ServiceAccount"
    echo "  kubectl get clusterrole                 # ClusterRole"
}

# 生成完整报告
generate_full_report() {
    local report_file="k8s_cluster_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "生成完整集群报告..."
    
    {
        echo "Kubernetes 集群完整报告"
        echo "生成时间: $(date)"
        echo "======================================="
        echo ""
        
        kubectl cluster-info
        echo ""
        
        echo "=== 节点信息 ==="
        kubectl get nodes -o wide
        echo ""
        
        echo "=== 命名空间 ==="
        kubectl get namespaces
        echo ""
        
        echo "=== Pod 状态 ==="
        kubectl get pods --all-namespaces -o wide
        echo ""
        
        echo "=== Service ==="
        kubectl get services --all-namespaces -o wide
        echo ""
        
        echo "=== Ingress ==="
        kubectl get ingress --all-namespaces -o wide 2>/dev/null || echo "未找到 Ingress"
        echo ""
        
        echo "=== Deployment ==="
        kubectl get deployment --all-namespaces -o wide
        echo ""
        
        echo "=== 最近事件 ==="
        kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp | tail -20
        echo ""
        
    } > "$report_file"
    
    log_success "完整报告已生成: $report_file"
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${PURPLE}选择要查看的信息:${NC}"
    echo "  1) 集群基本信息"
    echo "  2) Pod 信息"
    echo "  3) Service 和 Ingress"
    echo "  4) 工作负载 (Deployment, DaemonSet, etc.)"
    echo "  5) 存储信息"
    echo "  6) RBAC 信息"
    echo "  7) Tekton 组件"
    echo "  8) 网络信息"
    echo "  9) 资源使用情况"
    echo " 10) 最近事件"
    echo " 11) 常用命令"
    echo " 12) 生成完整报告"
    echo "  0) 全部显示"
    echo "  q) 退出"
    echo ""
}

# 交互式菜单
interactive_menu() {
    while true; do
        show_menu
        read -p "请选择 (0-12, q): " choice
        
        case $choice in
            1) show_cluster_info ;;
            2) show_pods ;;
            3) show_services; show_ingress ;;
            4) show_workloads ;;
            5) show_storage ;;
            6) show_rbac ;;
            7) show_tekton ;;
            8) show_network ;;
            9) show_resource_usage ;;
            10) show_events ;;
            11) show_useful_commands ;;
            12) generate_full_report ;;
            0) show_all_info ;;
            q|Q) log_info "退出"; break ;;
            *) log_warning "无效选择，请重试" ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..." 
    done
}

# 显示所有信息
show_all_info() {
    show_cluster_info
    show_namespaces
    show_pods
    show_services
    show_ingress
    show_workloads
    show_storage
    show_config
    show_rbac
    show_tekton
    show_network
    show_resource_usage
    show_events
    show_useful_commands
}

# 主函数
main() {
    print_header "Kubernetes 集群信息查看工具"
    
    check_kubectl
    
    # 检查参数
    case "${1:-}" in
        --all|-a)
            show_all_info
            ;;
        --report|-r)
            generate_full_report
            ;;
        --tekton|-t)
            show_tekton
            ;;
        --pods|-p)
            show_pods
            ;;
        --services|-s)
            show_services
            show_ingress
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --all, -a      显示所有信息"
            echo "  --report, -r   生成完整报告"
            echo "  --tekton, -t   显示 Tekton 信息"
            echo "  --pods, -p     显示 Pod 信息"
            echo "  --services, -s 显示 Service 和 Ingress 信息"
            echo "  --help, -h     显示帮助"
            echo ""
            echo "不带参数时进入交互式菜单"
            ;;
        "")
            interactive_menu
            ;;
        *)
            log_error "未知参数: $1"
            echo "使用 --help 查看可用选项"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 
