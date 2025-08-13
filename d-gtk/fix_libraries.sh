#!/bin/bash

echo "修復 GTK 庫加載問題..."

# 創建本地庫目錄
mkdir -p ./libs

# 複製必要的庫到本地目錄
echo "複製 GTK 庫到本地目錄..."

# ATK 庫
if [ -f "/usr/local/Cellar/at-spi2-core/2.56.4/lib/libatk-1.0.0.dylib" ]; then
    cp "/usr/local/Cellar/at-spi2-core/2.56.4/lib/libatk-1.0.0.dylib" ./libs/
    echo "✅ 複製 libatk-1.0.0.dylib"
fi

# GTK 3 庫
if [ -f "/usr/local/Cellar/gtk+3/3.24.49/lib/libgtk-3.0.dylib" ]; then
    cp "/usr/local/Cellar/gtk+3/3.24.49/lib/libgtk-3.0.dylib" ./libs/
    echo "✅ 複製 libgtk-3.0.dylib"
fi

if [ -f "/usr/local/Cellar/gtk+3/3.24.49/lib/libgdk-3.0.dylib" ]; then
    cp "/usr/local/Cellar/gtk+3/3.24.49/lib/libgdk-3.0.dylib" ./libs/
    echo "✅ 複製 libgdk-3.0.dylib"
fi

# 其他必要庫
LIBS_TO_COPY=(
    "/usr/local/lib/libgobject-2.0.0.dylib"
    "/usr/local/lib/libglib-2.0.0.dylib"
    "/usr/local/lib/libgio-2.0.0.dylib"
    "/usr/local/lib/libgmodule-2.0.0.dylib"
    "/usr/local/lib/libpango-1.0.0.dylib"
    "/usr/local/lib/libpangocairo-1.0.0.dylib"
    "/usr/local/lib/libgdk_pixbuf-2.0.0.dylib"
    "/usr/local/lib/libcairo.2.dylib"
    "/usr/local/lib/libcairo-gobject.2.dylib"
)

for lib in "${LIBS_TO_COPY[@]}"; do
    if [ -f "$lib" ]; then
        cp "$lib" ./libs/
        echo "✅ 複製 $(basename $lib)"
    else
        echo "⚠️  未找到 $lib"
    fi
done

echo ""
echo "創建運行腳本..."

# 創建新的運行腳本
cat > run_with_local_libs.sh << 'EOF'
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
EOF

chmod +x run_with_local_libs.sh

echo "✅ 庫修復完成！"
echo ""
echo "使用方法："
echo "1. 運行：./run_with_local_libs.sh"
echo "2. 或者直接：DYLD_LIBRARY_PATH=./libs:$DYLD_LIBRARY_PATH ./d-mac-calc-fx-gtk4"
echo ""
echo "如果仍有問題，請檢查 ./libs/ 目錄中的庫文件。"
