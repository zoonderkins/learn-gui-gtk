#!/bin/bash

echo "正在啟動 GTK 4 適配版本的 D 計算機..."

# 檢查並創建必要的符號連結
echo "檢查 GTK 庫符號連結..."
if [ ! -L "/usr/local/lib/libatk-1.0.0.dylib" ]; then
    echo "⚠️  缺少 ATK 庫符號連結，嘗試創建..."
    sudo ln -sf /usr/local/Cellar/at-spi2-core/2.56.4/lib/libatk-1.0.0.dylib /usr/local/lib/libatk-1.0.0.dylib
fi

# 設置完整的庫路徑
export DYLD_LIBRARY_PATH="/usr/local/lib:/usr/local/Cellar/gtk+3/3.24.49/lib:/usr/local/Cellar/at-spi2-core/2.56.4/lib:/usr/local/Cellar/glib/2.82.4/lib:/usr/local/Cellar/pango/1.56.0/lib:/usr/local/Cellar/gdk-pixbuf/2.42.12/lib:/usr/local/Cellar/cairo/1.18.2/lib:$DYLD_LIBRARY_PATH"

# 設置 GTK 相關環境變數
export GTK_PATH="/usr/local/lib/gtk-3.0"
export GDK_PIXBUF_MODULE_FILE="/usr/local/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

# 禁用 macOS 的 SIP 對 DYLD_LIBRARY_PATH 的限制（僅對當前進程）
export DYLD_FALLBACK_LIBRARY_PATH="$DYLD_LIBRARY_PATH"

# 檢查可執行文件是否存在
if [ ! -f "./d-mac-calc-fx-gtk4" ]; then
    echo "❌ 可執行文件不存在"
    echo "請先運行：./build_gtk4.sh"
    exit 1
fi

echo "✅ 環境設置完成"
echo "DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"
echo ""
echo "正在啟動程序..."

# 運行程序並捕獲輸出
echo "執行命令：./d-mac-calc-fx-gtk4"
./d-mac-calc-fx-gtk4 2>&1
EXIT_CODE=$?

echo ""
echo "程序退出，退出碼：$EXIT_CODE"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 程序正常退出"
else
    echo "❌ 程序異常退出"
    echo "可能的解決方案："
    echo "1. 檢查 GTK 庫是否正確安裝"
    echo "2. 嘗試運行符號連結腳本：./setup_gtk_links.sh"
    echo "3. 檢查是否有 X11 或顯示問題"
fi
