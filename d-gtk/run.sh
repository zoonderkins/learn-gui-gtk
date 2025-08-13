#!/bin/bash

# 設置 GTK 3 庫路徑
export DYLD_LIBRARY_PATH="/usr/local/lib:/usr/local/Cellar/at-spi2-core/2.56.4/lib:/usr/local/Cellar/gtk+3/3.24.49/lib:$DYLD_LIBRARY_PATH"

# 設置 GTK 相關環境變數
export GTK_PATH="/usr/local/lib/gtk-3.0"
export GDK_PIXBUF_MODULE_FILE="/usr/local/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

echo "正在設置 GTK 3 環境..."
echo "DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"

echo "正在編譯並運行 D 計算機程序..."
dub run --compiler=ldc2
