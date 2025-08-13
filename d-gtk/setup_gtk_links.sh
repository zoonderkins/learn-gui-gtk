#!/bin/bash

echo "正在創建 GTK 庫符號連結..."

# 創建必要的符號連結
sudo ln -sf /usr/local/Cellar/at-spi2-core/2.56.4/lib/libatk-1.0.0.dylib /usr/local/lib/libatk-1.0.0.dylib
sudo ln -sf /usr/local/Cellar/gtk+3/3.24.49/lib/libgtk-3.0.dylib /usr/local/lib/libgtk-3.0.dylib
sudo ln -sf /usr/local/Cellar/gtk+3/3.24.49/lib/libgdk-3.0.dylib /usr/local/lib/libgdk-3.0.dylib

# 檢查連結是否成功
echo "檢查符號連結："
ls -la /usr/local/lib/libatk-1.0.0.dylib
ls -la /usr/local/lib/libgtk-3.0.dylib  
ls -la /usr/local/lib/libgdk-3.0.dylib

echo "符號連結創建完成！"
echo "現在可以嘗試運行程序：dub run --compiler=ldc2"
