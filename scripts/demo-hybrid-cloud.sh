#!/bin/bash

echo "╔════════════════════════════════════════════════════╗"
echo "║    HybridBridge - 混合雲架構展示                  ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# 啟動 port-forward
echo "啟動服務..."
kubectl port-forward -n hybridbridge svc/hybrid-test-app 8080:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

echo "✅ 應用已就緒，可透過 http://localhost:8080 訪問"
echo ""
echo "可用的 API 端點："
echo "  GET /              - 基本資訊"
echo "  GET /health        - 健康檢查"
echo "  GET /network-info  - 網路資訊"
echo "  GET /test-aws      - 測試 AWS 連線（重點！）"
echo ""

# 互動式選單
while true; do
    echo "─────────────────────────────────────────────────"
    echo "請選擇要展示的功能："
    echo "  1) 顯示 Pod 資訊"
    echo "  2) 測試基本端點"
    echo "  3) 測試 AWS 連線（混合雲）"
    echo "  4) 顯示網路資訊"
    echo "  5) 查看 Pod 日誌"
    echo "  6) 進入 Pod Shell"
    echo "  7) 完整測試"
    echo "  0) 退出"
    echo ""
    read -p "選擇 [0-7]: " choice
    
    case $choice in
        1)
            echo ""
            kubectl get pods -n hybridbridge -l app=hybrid-test-app -o wide
            ;;
        2)
            echo ""
            echo "基本資訊："
            curl -s http://localhost:8080/ | jq
            ;;
        3)
            echo ""
            echo "測試 K8s → AWS 連線："
            curl -s http://localhost:8080/test-aws | jq
            ;;
        4)
            echo ""
            echo "網路資訊："
            curl -s http://localhost:8080/network-info | jq
            ;;
        5)
            echo ""
            kubectl logs -n hybridbridge -l app=hybrid-test-app --tail=50
            ;;
        6)
            echo ""
            POD=$(kubectl get pods -n hybridbridge -l app=hybrid-test-app -o jsonpath='{.items[0].metadata.name}')
            echo "進入 Pod: $POD"
            kubectl exec -it -n hybridbridge $POD -- /bin/bash
            ;;
        7)
            echo ""
            ./scripts/test-k8s-app.sh
            ;;
        0)
            echo "關閉 port-forward..."
            kill $PF_PID 2>/dev/null
            echo "再見！"
            exit 0
            ;;
        *)
            echo "無效選擇"
            ;;
    esac
    echo ""
done
