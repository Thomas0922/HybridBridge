#!/bin/bash

echo "清理 Kubernetes 資源..."

# 刪除 Network Policies
kubectl delete networkpolicy --all -n hybridbridge 2>/dev/null

# 刪除 Deployment 和 Service
kubectl delete deployment hybrid-test-app -n hybridbridge 2>/dev/null
kubectl delete service hybrid-test-app -n hybridbridge 2>/dev/null

# 刪除 ConfigMap
kubectl delete configmap aws-endpoints -n hybridbridge 2>/dev/null

# 刪除命名空間（會刪除所有資源）
# kubectl delete namespace hybridbridge

echo "✅ 清理完成"
