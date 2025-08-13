#!/bin/bash

echo "正在啟動 Go + GTK4 計算機應用程序..."

# 檢查可執行文件
if [ ! -f "./go-mac-calc-fx" ]; then
    echo "❌ 可執行文件不存在"
    echo "請先運行構建腳本：./build.sh"
    exit 1
fi

# 設置 GTK4 環境變數
export DYLD_LIBRARY_PATH="/usr/local/lib:$DYLD_LIBRARY_PATH"
export GTK_PATH="/usr/local/lib/gtk-4.0"
export GDK_PIXBUF_MODULE_FILE="/usr/local/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

# 設置 macOS 特定環境
export DYLD_FALLBACK_LIBRARY_PATH="/usr/local/lib:$DYLD_FALLBACK_LIBRARY_PATH"

echo "✅ 環境設置完成"
echo "DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"
echo ""
echo "正在啟動程序..."

# 運行程序並捕獲輸出
./go-mac-calc-fx 2>&1
EXIT_CODE=$?

echo ""
echo "程序退出，退出碼：$EXIT_CODE"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 程序正常退出"
else
    echo "❌ 程序異常退出"
    echo ""
    echo "可能的解決方案："
    echo "1. 檢查 GTK4 是否正確安裝：brew install gtk4"
    echo "2. 檢查依賴庫：brew install glib cairo pango gdk-pixbuf"
    echo "3. 重新構建程序：./build.sh"
fi
