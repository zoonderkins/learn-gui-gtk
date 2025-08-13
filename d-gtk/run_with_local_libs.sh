#!/bin/bash

echo "使用本地庫運行 GTK 4 適配版本..."

# 設置本地庫路徑
export DYLD_LIBRARY_PATH="./libs:/usr/local/lib:$DYLD_LIBRARY_PATH"
export DYLD_FALLBACK_LIBRARY_PATH="./libs:/usr/local/lib:$DYLD_FALLBACK_LIBRARY_PATH"

# 檢查可執行文件
if [ ! -f "./d-mac-calc-fx-gtk4" ]; then
    echo "❌ 可執行文件不存在，請先運行 ./build_gtk4.sh"
    exit 1
fi

echo "✅ 環境設置完成"
echo "DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"
echo ""
echo "正在啟動程序..."

# 運行程序
./d-mac-calc-fx-gtk4 2>&1
EXIT_CODE=$?

echo ""
echo "程序退出，退出碼：$EXIT_CODE"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 程序正常退出"
else
    echo "❌ 程序異常退出"
fi
