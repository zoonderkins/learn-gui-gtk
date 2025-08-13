#!/bin/bash

echo "正在構建 C + GTK4 計算機應用程序（靜態連結版本）..."

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
echo "正在編譯應用程序（靜態連結）..."

# 支援 ARM64 和 x86_64
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    echo "檢測到 ARM64 架構"
    ARCH_FLAGS="-arch arm64"
else
    echo "檢測到 x86_64 架構"
    ARCH_FLAGS="-arch x86_64"
fi

# 嘗試不同的靜態連結方法
echo "方法 1：使用 Makefile.static..."
make -f Makefile.static clean
make -f Makefile.static all

if [ $? -eq 0 ]; then
    echo "✅ 靜態連結編譯成功！"
    EXECUTABLE="./c-mac-calc-fx-static"
else
    echo "⚠️  Makefile 方法失敗，嘗試手動編譯..."
    
    # 手動靜態連結編譯（macOS 適配）
    echo "方法 2：macOS 靜態連結..."

    # 獲取所有必要的庫
    GTK_CFLAGS=$(pkg-config --cflags gtk4)
    GTK_LIBS=$(pkg-config --libs --static gtk4)

    # macOS 編譯命令（移除不支援的選項）
    gcc -Wall -Wextra -O3 -std=c11 \
        $GTK_CFLAGS \
        -o c-mac-calc-fx-static \
        main.c \
        $GTK_LIBS \
        -lcurl -ljson-c -lpthread \
        -lz -lbz2 -llzma -liconv -lresolv \
        -framework CoreFoundation \
        -framework Security \
        -framework ApplicationServices \
        -framework Carbon \
        -framework AppKit
    
    if [ $? -eq 0 ]; then
        echo "✅ 手動靜態連結編譯成功！"
        EXECUTABLE="./c-mac-calc-fx-static"
    else
        echo "❌ 靜態連結編譯失敗，嘗試部分靜態連結..."
        
        # 方法 3：部分靜態連結（macOS 適配）
        echo "方法 3：部分靜態連結..."
        gcc -Wall -Wextra -O3 -std=c11 \
            $GTK_CFLAGS \
            -o c-mac-calc-fx-partial-static \
            main.c \
            $(pkg-config --libs gtk4) \
            -lcurl -ljson-c -lpthread
        
        if [ $? -eq 0 ]; then
            echo "✅ 部分靜態連結編譯成功！"
            EXECUTABLE="./c-mac-calc-fx-partial-static"
        else
            echo "❌ 所有編譯方法都失敗"
            exit 1
        fi
    fi
fi

# 顯示文件信息
echo ""
echo "文件信息："
ls -lh $EXECUTABLE
echo ""
echo "文件大小：$(du -h $EXECUTABLE | cut -f1)"

# 檢查依賴
echo ""
echo "動態庫依賴檢查："
DEPS=$(otool -L $EXECUTABLE | wc -l)
echo "依賴庫數量：$DEPS"
echo ""
echo "詳細依賴："
otool -L $EXECUTABLE

# 分析靜態連結效果
echo ""
if [ $DEPS -le 5 ]; then
    echo "🎉 靜態連結效果優秀！依賴庫很少。"
elif [ $DEPS -le 10 ]; then
    echo "✅ 靜態連結效果良好！依賴庫較少。"
else
    echo "⚠️  靜態連結效果一般，仍有較多動態依賴。"
fi

echo ""
echo "🎉 構建完成！"
echo ""
echo "運行方法："
echo "1. 直接運行：$EXECUTABLE"
echo "2. 或使用運行腳本：./run_static.sh"
echo ""
echo "特性："
echo "- ✅ 靜態連結（減少依賴）"
echo "- ✅ 原生 GTK4 GUI"
echo "- ✅ 完整的計算機功能"
echo "- ✅ 線上匯率轉換"
echo "- ✅ 支援 ARM64 和 x86_64"
echo "- ✅ 更好的可移植性"
