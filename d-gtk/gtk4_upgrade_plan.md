# GTK 4 升級計劃

## 當前狀況
- 使用 GtkD 3.11.0 (GTK 3 綁定)
- GTK 4.18.6 已安裝
- 需要升級到 GTK 4 綁定

## 升級選項

### 選項 A：使用 gidgen 生成 GTK 4 綁定
1. 安裝 gidgen：`dub fetch gidgen`
2. 生成 GTK 4 綁定包
3. 修改 dub.sdl 使用新綁定
4. 更新源代碼以適應 GTK 4 API

### 選項 B：使用現有的 GTK 4 綁定包
1. 查找現有的 GTK 4 D 語言綁定
2. 更新 dub.sdl 依賴
3. 修改源代碼

## 需要修改的代碼部分

### 1. 導入語句
```d
// GTK 3 (當前)
import gtk.Main;
import gtk.Window;
import gtk.Widget;

// GTK 4 (目標)
import gtk4.Main;
import gtk4.Window;
import gtk4.Widget;
```

### 2. 初始化
```d
// GTK 3 (當前)
string[] args;
Main.init(args);

// GTK 4 (目標)
// GTK 4 不需要 init 參數
Main.init();
```

### 3. 事件處理
```d
// GTK 3 (當前)
win.addOnDestroy((Widget w) { Main.quit(); });

// GTK 4 (目標)
// 可能需要不同的事件處理方式
```

## 執行步驟

1. **備份當前代碼**
   ```bash
   cp -r source source_gtk3_backup
   ```

2. **嘗試 gidgen 方法**
   ```bash
   dub run gidgen -- --help
   ```

3. **生成 GTK 4 綁定**
   ```bash
   # 需要 GIR 文件和定義文件
   ```

4. **更新項目配置**
   ```bash
   # 修改 dub.sdl
   ```

5. **逐步移植代碼**
   - 更新導入
   - 修改初始化
   - 調整事件處理
   - 測試編譯

## 風險評估
- **高風險**：API 變化可能需要大量代碼修改
- **中風險**：綁定生成可能失敗
- **低風險**：基本功能應該可以移植

## 回退計劃
如果升級失敗，可以：
1. 恢復 GTK 3 代碼
2. 使用符號連結解決當前問題
3. 繼續使用 GTK 3 版本
