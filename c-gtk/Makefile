# C + GTK4 計算機應用程序 Makefile

# 編譯器和標誌
CC = gcc
CFLAGS = -Wall -Wextra -O3 -std=c11
LDFLAGS = -lcurl -ljson-c -lpthread

# GTK4 相關標誌
GTK_CFLAGS = $(shell pkg-config --cflags gtk4)
GTK_LIBS = $(shell pkg-config --libs gtk4)

# 目標文件
TARGET = c-mac-calc-fx
SOURCE = main.c

# 預設目標
all: $(TARGET)

# 編譯規則
$(TARGET): $(SOURCE)
	@echo "正在編譯 C + GTK4 計算機應用程序..."
	@echo "GTK4 版本：$(shell pkg-config --modversion gtk4)"
	$(CC) $(CFLAGS) $(GTK_CFLAGS) -o $(TARGET) $(SOURCE) $(GTK_LIBS) $(LDFLAGS)
	@echo "✅ 編譯成功！"
	@echo "可執行文件：./$(TARGET)"
	@echo "文件大小：$(shell du -h $(TARGET) | cut -f1)"

# 清理
clean:
	rm -f $(TARGET)
	@echo "清理完成"

# 運行
run: $(TARGET)
	./$(TARGET)

# 調試版本
debug: CFLAGS += -g -DDEBUG
debug: $(TARGET)

# 安裝依賴（macOS）
install-deps:
	@echo "安裝 C + GTK4 依賴..."
	brew install gtk4 libcurl json-c pkg-config
	@echo "依賴安裝完成"

# 檢查依賴
check-deps:
	@echo "檢查依賴..."
	@pkg-config --exists gtk4 && echo "✅ GTK4: $(shell pkg-config --modversion gtk4)" || echo "❌ GTK4 未安裝"
	@pkg-config --exists libcurl && echo "✅ libcurl: $(shell pkg-config --modversion libcurl)" || echo "❌ libcurl 未安裝"
	@pkg-config --exists json-c && echo "✅ json-c: $(shell pkg-config --modversion json-c)" || echo "❌ json-c 未安裝"

# 幫助
help:
	@echo "可用的 make 目標："
	@echo "  all          - 編譯程序（預設）"
	@echo "  clean        - 清理編譯文件"
	@echo "  run          - 編譯並運行程序"
	@echo "  debug        - 編譯調試版本"
	@echo "  install-deps - 安裝依賴（macOS）"
	@echo "  check-deps   - 檢查依賴"
	@echo "  help         - 顯示此幫助"

.PHONY: all clean run debug install-deps check-deps help
