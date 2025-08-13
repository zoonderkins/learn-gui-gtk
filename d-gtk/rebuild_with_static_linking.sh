#!/bin/bash

echo "正在準備靜態連結編譯..."

# 檢查 pkg-config 是否可用
if ! command -v pkg-config &> /dev/null; then
    echo "錯誤：pkg-config 未安裝"
    echo "請運行：brew install pkg-config"
    exit 1
fi

# 檢查 GTK+3 pkg-config
echo "檢查 GTK+3 pkg-config..."
pkg-config --exists gtk+-3.0
if [ $? -eq 0 ]; then
    echo "✅ GTK+3 pkg-config 可用"
    echo "GTK+3 版本：$(pkg-config --modversion gtk+-3.0)"
    echo "GTK+3 cflags：$(pkg-config --cflags gtk+-3.0)"
    echo "GTK+3 libs：$(pkg-config --libs gtk+-3.0)"
else
    echo "❌ GTK+3 pkg-config 不可用"
    echo "請檢查 GTK+3 安裝"
    exit 1
fi

# 創建修改後的 dub.sdl 以使用系統 GTK
echo "創建 dub_static.sdl..."
cat > dub_static.sdl << 'EOF'
name "d-mac-calc-fx"
description "Simple Calculator with live FX (no API key) — D + GtkD — macOS Intel x64"
authors "Ed Oo"
license "MIT"
targetType "executable"

dependency "gtk-d:gtkd" version=">=3.10.0 <4.0.0"

compiler "ldc2"

configuration "release" {
    buildType "release"
}

configuration "static" {
    buildType "release"
    lflags "-L/usr/local/lib" "-lgtk-3" "-lgdk-3" "-latk-1.0"
}
EOF

echo "✅ dub_static.sdl 已創建"
echo ""
echo "使用方法："
echo "1. 運行符號連結腳本：./setup_gtk_links.sh"
echo "2. 或者嘗試靜態連結：dub build --config=static --compiler=ldc2 --override-config=dub_static.sdl"
echo "3. 然後運行：./d-mac-calc-fx"
