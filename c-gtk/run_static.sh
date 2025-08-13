#!/bin/bash

echo "正在啟動 C + GTK4 計算機應用程序（靜態連結版本）..."

# 檢查可執行文件
EXECUTABLE=""
if [ -f "./c-mac-calc-fx-static" ]; then
    EXECUTABLE="./c-mac-calc-fx-static"
    echo "✅ 找到靜態連結版本"
elif [ -f "./c-mac-calc-fx-partial-static" ]; then
    EXECUTABLE="./c-mac-calc-fx-partial-static"
    echo "✅ 找到部分靜態連結版本"
else
    echo "❌ 靜態連結可執行文件不存在"
    echo "請先運行構建腳本：./build_static.sh"
    exit 1
fi

# 顯示文件信息
echo "可執行文件：$EXECUTABLE"
echo "文件大小：$(du -h $EXECUTABLE | cut -f1)"

# 檢查依賴
echo ""
echo "動態庫依賴檢查："
DEPS=$(otool -L $EXECUTABLE | wc -l)
echo "依賴庫數量：$DEPS"

if [ $DEPS -le 5 ]; then
    echo "🎉 靜態連結效果優秀！"
elif [ $DEPS -le 10 ]; then
    echo "✅ 靜態連結效果良好！"
else
    echo "⚠️  仍有較多動態依賴"
    echo "詳細依賴："
    otool -L $EXECUTABLE
fi

# 設置最小的環境變數（靜態連結版本需要較少環境設置）
export DYLD_LIBRARY_PATH="/usr/local/lib:$DYLD_LIBRARY_PATH"

echo ""
echo "✅ 環境設置完成"
echo "正在啟動程序..."

# 運行程序並捕獲輸出
$EXECUTABLE 2>&1
EXIT_CODE=$?

echo ""
echo "程序退出，退出碼：$EXIT_CODE"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 程序正常退出"
else
    echo "❌ 程序異常退出"
    echo ""
    echo "可能的解決方案："
    echo "1. 檢查是否有缺少的系統庫"
    echo "2. 嘗試重新構建：./build_static.sh"
    echo "3. 檢查系統兼容性"
fi
