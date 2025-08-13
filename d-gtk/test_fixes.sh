#!/bin/bash

echo "測試修復後的 GTK 4 適配版本..."

# 檢查可執行文件
if [ ! -f "./d-mac-calc-fx-gtk4" ]; then
    echo "❌ 可執行文件不存在，請先運行 ./build_gtk4.sh"
    exit 1
fi

echo "✅ 可執行文件存在"

# 測試程序啟動（短時間）
echo "測試程序啟動（5秒後自動終止）..."
timeout 5s ./d-mac-calc-fx-gtk4 &
PID=$!

sleep 2

# 檢查程序是否在運行
if ps -p $PID > /dev/null; then
    echo "✅ 程序成功啟動並運行"
    kill $PID 2>/dev/null
    wait $PID 2>/dev/null
else
    echo "❌ 程序啟動失敗或立即退出"
fi

echo ""
echo "修復內容："
echo "1. ✅ 添加了按鈕點擊調試輸出"
echo "2. ✅ 添加了顯示更新調試輸出"
echo "3. ✅ 更換為可靠的免費匯率 API"
echo "4. ✅ 添加了 API 響應調試輸出"
echo "5. ✅ 添加了備用 API 支援"
echo ""
echo "使用方法："
echo "1. 運行程序：./d-mac-calc-fx-gtk4"
echo "2. 檢查終端輸出的調試信息"
echo "3. 測試計算機按鈕是否有響應"
echo "4. 測試匯率轉換功能"
echo ""
echo "如果仍有問題，請檢查終端的調試輸出信息。"
