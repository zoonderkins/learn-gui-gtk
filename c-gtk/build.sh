#!/bin/bash

echo "正在構建 C + GTK4 計算機應用程序..."

# 檢查編譯器
if ! command -v gcc &> /dev/null; then
    echo "❌ GCC 未安裝"
    echo "請安裝 Xcode Command Line Tools：xcode-select --install"
    exit 1
fi

echo "✅ GCC 版本：$(gcc --version | head -1)"

# 檢查 GTK4 安裝
if ! pkg-config --exists gtk4; then
    echo "❌ GTK4 未安裝"
    echo "請安裝 GTK4：brew install gtk4"
    exit 1
fi

echo "✅ GTK4 版本：$(pkg-config --modversion gtk4)"

# 檢查其他依賴
if ! pkg-config --exists libcurl; then
    echo "❌ libcurl 未安裝"
    echo "請安裝 libcurl：brew install curl"
    exit 1
fi

echo "✅ libcurl 版本：$(pkg-config --modversion libcurl)"

if ! pkg-config --exists json-c; then
    echo "❌ json-c 未安裝"
    echo "請安裝 json-c：brew install json-c"
    exit 1
fi

echo "✅ json-c 版本：$(pkg-config --modversion json-c)"

# 設置環境變數
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# 構建應用程序
echo "正在編譯應用程序..."

# 支援 ARM64 和 x86_64
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    echo "檢測到 ARM64 架構"
    ARCH_FLAGS="-arch arm64"
else
    echo "檢測到 x86_64 架構"
    ARCH_FLAGS="-arch x86_64"
fi

# 使用 Makefile 編譯
make clean
make all

if [ $? -eq 0 ]; then
    echo "✅ 編譯成功！"
    echo "可執行文件：./c-mac-calc-fx"
    
    # 顯示文件信息
    echo ""
    echo "文件信息："
    ls -lh c-mac-calc-fx
    echo ""
    echo "文件大小：$(du -h c-mac-calc-fx | cut -f1)"
    
    # 檢查依賴
    echo ""
    echo "動態庫依賴："
    otool -L c-mac-calc-fx | head -10
    
else
    echo "❌ 編譯失敗"
    exit 1
fi

echo ""
echo "🎉 構建完成！"
echo ""
echo "運行方法："
echo "1. 直接運行：./c-mac-calc-fx"
echo "2. 或使用運行腳本：./run.sh"
echo "3. 或使用 make：make run"
echo ""
echo "特性："
echo "- ✅ 原生 GTK4 GUI"
echo "- ✅ 完整的計算機功能"
echo "- ✅ 線上匯率轉換"
echo "- ✅ 支援 ARM64 和 x86_64"
echo "- ✅ 最小的二進制大小"
echo "- ✅ 最佳性能"
