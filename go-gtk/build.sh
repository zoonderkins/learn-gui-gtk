#!/bin/bash

echo "正在構建 Go + GTK4 計算機應用程序..."

# 檢查 Go 安裝
if ! command -v go &> /dev/null; then
    echo "❌ Go 未安裝"
    echo "請安裝 Go：brew install go"
    exit 1
fi

echo "✅ Go 版本：$(go version)"

# 檢查 GTK4 安裝
if ! pkg-config --exists gtk4; then
    echo "❌ GTK4 未安裝"
    echo "請安裝 GTK4：brew install gtk4"
    exit 1
fi

echo "✅ GTK4 版本：$(pkg-config --modversion gtk4)"

# 設置環境變數
export CGO_ENABLED=1
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# 檢查並下載依賴
echo "正在下載 Go 模組依賴..."
go mod tidy

if [ $? -ne 0 ]; then
    echo "❌ 下載依賴失敗"
    exit 1
fi

echo "✅ 依賴下載完成"

# 構建應用程序
echo "正在編譯應用程序..."

# 設置構建標籤和參數
BUILD_FLAGS="-v -ldflags=-w -ldflags=-s"

# 支援 ARM64 和 x86_64
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    echo "檢測到 ARM64 架構"
    GOARCH=arm64
else
    echo "檢測到 x86_64 架構"
    GOARCH=amd64
fi

# 編譯
GOOS=darwin GOARCH=$GOARCH go build $BUILD_FLAGS -o go-mac-calc-fx main.go

if [ $? -eq 0 ]; then
    echo "✅ 編譯成功！"
    echo "可執行文件：./go-mac-calc-fx"
    
    # 顯示文件信息
    echo ""
    echo "文件信息："
    ls -lh go-mac-calc-fx
    echo ""
    echo "文件大小：$(du -h go-mac-calc-fx | cut -f1)"
    
    # 檢查依賴
    echo ""
    echo "動態庫依賴："
    otool -L go-mac-calc-fx | head -10
    
else
    echo "❌ 編譯失敗"
    exit 1
fi

echo ""
echo "🎉 構建完成！"
echo ""
echo "運行方法："
echo "1. 直接運行：./go-mac-calc-fx"
echo "2. 或使用運行腳本：./run.sh"
echo ""
echo "特性："
echo "- ✅ 原生 GTK4 GUI"
echo "- ✅ 完整的計算機功能"
echo "- ✅ 線上匯率轉換"
echo "- ✅ 支援 ARM64 和 x86_64"
echo "- ✅ 靜態連結 Go 運行時"
