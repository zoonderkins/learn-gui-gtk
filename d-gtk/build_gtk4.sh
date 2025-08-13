#!/bin/bash

echo "正在構建 GTK 4 適配版本的 D 計算機..."

# 檢查必要的依賴
echo "檢查 GTK 4 安裝..."
if ! pkg-config --exists gtk4; then
    echo "❌ GTK 4 未安裝"
    echo "請運行：brew install gtk4"
    exit 1
fi

echo "✅ GTK 4 版本：$(pkg-config --modversion gtk4)"

# 檢查 GTK 3 綁定（用於適配）
echo "檢查 GTK 3 綁定..."
if ! pkg-config --exists gtk+-3.0; then
    echo "❌ GTK 3 未安裝"
    echo "請運行：brew install gtk+3"
    exit 1
fi

echo "✅ GTK 3 版本：$(pkg-config --modversion gtk+-3.0)"

# 設置環境變數以使用 GTK 4
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export DYLD_LIBRARY_PATH="/usr/local/lib:$DYLD_LIBRARY_PATH"

echo "正在編譯 GTK 4 適配版本..."

# 備份原始 dub.sdl（如果存在）
if [ -f "dub.sdl" ]; then
    echo "備份原始 dub.sdl..."
    cp dub.sdl dub_original_backup.sdl
fi

# 使用 GTK 4 配置
echo "準備構建配置..."
cp dub_gtk4.sdl dub.sdl

# 嘗試普通編譯
echo "嘗試普通編譯..."
if dub build --config=release --compiler=ldc2; then
    echo "✅ 普通編譯成功！"
    echo "可執行文件：./d-mac-calc-fx-gtk4"
else
    echo "❌ 普通編譯失敗，嘗試靜態連結..."

    # 嘗試靜態連結
    if dub build --config=static --compiler=ldc2; then
        echo "✅ 靜態連結編譯成功！"
        echo "可執行文件：./d-mac-calc-fx-gtk4"
    else
        echo "❌ 編譯失敗"
        echo "請檢查錯誤信息並手動調試"

        # 恢復原始配置
        if [ -f "dub_original_backup.sdl" ]; then
            mv dub_original_backup.sdl dub.sdl
        else
            rm -f dub.sdl
        fi
        exit 1
    fi
fi

# 恢復原始配置
if [ -f "dub_original_backup.sdl" ]; then
    echo "恢復原始 dub.sdl..."
    mv dub_original_backup.sdl dub.sdl
else
    rm -f dub.sdl
fi

echo ""
echo "🎉 GTK 4 適配版本構建完成！"
echo ""
echo "運行方法："
echo "1. 直接運行：./d-mac-calc-fx-gtk4"
echo "2. 或者設置環境變數後運行："
echo "   export DYLD_LIBRARY_PATH=\"/usr/local/lib:\$DYLD_LIBRARY_PATH\""
echo "   ./d-mac-calc-fx-gtk4"
echo ""
echo "特性："
echo "- ✅ 修復了計算器崩潰問題"
echo "- ✅ 使用 GTK 4 庫（通過 GTK 3 綁定適配）"
echo "- ✅ 支援靜態連結"
echo "- ✅ 完整的計算機和匯率轉換功能"
