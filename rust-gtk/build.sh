#!/bin/bash

echo "正在構建 Rust + GTK4 計算機應用程序..."

# 檢查 Rust 安裝
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust 未安裝"
    echo "請安裝 Rust：curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

echo "✅ Rust 版本：$(rustc --version)"

# 檢查 GTK4 安裝
if ! pkg-config --exists gtk4; then
    echo "❌ GTK4 未安裝"
    echo "請安裝 GTK4：brew install gtk4"
    exit 1
fi

echo "✅ GTK4 版本：$(pkg-config --modversion gtk4)"

# 設置環境變數
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# 檢查並下載依賴
echo "正在下載 Rust 依賴..."
cargo check

if [ $? -ne 0 ]; then
    echo "❌ 依賴檢查失敗"
    exit 1
fi

echo "✅ 依賴檢查完成"

# 構建應用程序
echo "正在編譯應用程序..."

# 支援 ARM64 和 x86_64
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    echo "檢測到 ARM64 架構"
    TARGET="aarch64-apple-darwin"
else
    echo "檢測到 x86_64 架構"
    TARGET="x86_64-apple-darwin"
fi

# 編譯 release 版本
cargo build --release --target $TARGET

if [ $? -eq 0 ]; then
    echo "✅ 編譯成功！"
    
    # 複製可執行文件到當前目錄
    cp target/$TARGET/release/rust-mac-calc-fx ./rust-mac-calc-fx
    
    echo "可執行文件：./rust-mac-calc-fx"
    
    # 顯示文件信息
    echo ""
    echo "文件信息："
    ls -lh rust-mac-calc-fx
    echo ""
    echo "文件大小：$(du -h rust-mac-calc-fx | cut -f1)"
    
    # 檢查依賴
    echo ""
    echo "動態庫依賴："
    otool -L rust-mac-calc-fx | head -10
    
else
    echo "❌ 編譯失敗"
    exit 1
fi

echo ""
echo "🎉 構建完成！"
echo ""
echo "運行方法："
echo "1. 直接運行：./rust-mac-calc-fx"
echo "2. 或使用運行腳本：./run.sh"
echo ""
echo "特性："
echo "- ✅ 原生 GTK4 GUI"
echo "- ✅ 完整的計算機功能"
echo "- ✅ 線上匯率轉換"
echo "- ✅ 支援 ARM64 和 x86_64"
echo "- ✅ 零成本抽象"
echo "- ✅ 內存安全"
