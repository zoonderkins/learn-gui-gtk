#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <curl/curl.h>
#include <json-c/json.h>
#include <pthread.h>

// 支援的貨幣
static const char* CURRENCIES[] = {"USD", "EUR", "JPY", "CNY", "MYR", "TWD", "SGD", "GBP"};
static const int NUM_CURRENCIES = 8;

// 匯率結構
typedef struct {
    double rates[8];  // 對應 CURRENCIES 陣列
    char as_of[256];
    gboolean live;
} AppRates;

// 計算機結構
typedef struct {
    char current[256];
    double accumulator;
    char operator;
    gboolean just_evaluated;
} Calculator;

// 應用程序結構
typedef struct {
    GtkApplication *app;
    GtkWidget *window;
    GtkWidget *notebook;
    
    // 計算機頁面
    GtkWidget *calc_display;
    Calculator calc;
    
    // 匯率頁面
    GtkWidget *amount_entry;
    GtkWidget *from_combo;
    GtkWidget *to_combo;
    GtkWidget *result_label;
    GtkWidget *as_of_label;
    GtkWidget *status_label;
    AppRates rates;
} AppState;

// HTTP 響應結構
typedef struct {
    char *memory;
    size_t size;
} HTTPResponse;

// 預設匯率
static void init_default_rates(AppRates *rates) {
    rates->rates[0] = 1.0;    // USD
    rates->rates[1] = 0.85;   // EUR
    rates->rates[2] = 110.0;  // JPY
    rates->rates[3] = 6.5;    // CNY
    rates->rates[4] = 4.2;    // MYR
    rates->rates[5] = 28.0;   // TWD
    rates->rates[6] = 1.35;   // SGD
    rates->rates[7] = 0.75;   // GBP
    strcpy(rates->as_of, "預設匯率（離線）");
    rates->live = FALSE;
}

// 計算機方法
static void calc_clear(Calculator *calc) {
    strcpy(calc->current, "");
    calc->accumulator = 0.0;
    calc->operator = 0;
    calc->just_evaluated = FALSE;
}

static void calc_input_digit(Calculator *calc, const char *digit) {
    if (calc->just_evaluated && (digit[0] >= '0' && digit[0] <= '9')) {
        calc_clear(calc);
    }
    if (strcmp(digit, ".") == 0 && strstr(calc->current, ".") != NULL) {
        return; // 避免多個小數點
    }
    strcat(calc->current, digit);
}

static double calc_current_value(Calculator *calc) {
    if (strlen(calc->current) == 0) {
        return 0.0;
    }
    return atof(calc->current);
}

static void calc_apply_pending(Calculator *calc) {
    double x = calc_current_value(calc);
    if (calc->operator == 0) {
        calc->accumulator = x;
    } else {
        switch (calc->operator) {
            case '+':
                calc->accumulator += x;
                break;
            case '-':
                calc->accumulator -= x;
                break;
            case '*':
                calc->accumulator *= x;
                break;
            case '/':
                if (x != 0.0) {
                    calc->accumulator /= x;
                } else {
                    calc->accumulator = 0.0; // 避免除零錯誤
                }
                break;
        }
    }
    strcpy(calc->current, "");
}

static void calc_set_operator(Calculator *calc, char op) {
    if (strlen(calc->current) == 0 && calc->operator != 0) {
        calc->operator = op;
        return;
    }
    calc_apply_pending(calc);
    calc->operator = op;
    calc->just_evaluated = FALSE;
}

static double calc_evaluate(Calculator *calc) {
    calc_apply_pending(calc);
    calc->operator = 0;
    calc->just_evaluated = TRUE;
    return calc->accumulator;
}

static void calc_backspace(Calculator *calc) {
    int len = strlen(calc->current);
    if (len > 0) {
        calc->current[len - 1] = '\0';
    }
}

static void calc_display(Calculator *calc, char *buffer, size_t size) {
    if (strlen(calc->current) > 0) {
        strncpy(buffer, calc->current, size - 1);
        buffer[size - 1] = '\0';
    } else {
        snprintf(buffer, size, "%.12g", calc->accumulator);
    }
}

// 匯率轉換
static double convert_currency(double amount, int from_idx, int to_idx, AppRates *rates) {
    if (from_idx == to_idx) {
        return amount;
    }
    double from_rate = rates->rates[from_idx];
    double to_rate = rates->rates[to_idx];
    return amount * (to_rate / from_rate);
}

// HTTP 回調函數
static size_t write_callback(void *contents, size_t size, size_t nmemb, HTTPResponse *response) {
    size_t realsize = size * nmemb;
    char *ptr = realloc(response->memory, response->size + realsize + 1);
    if (ptr == NULL) {
        printf("記憶體不足！\n");
        return 0;
    }
    
    response->memory = ptr;
    memcpy(&(response->memory[response->size]), contents, realsize);
    response->size += realsize;
    response->memory[response->size] = 0;
    
    return realsize;
}

// 獲取線上匯率
static gboolean fetch_rates_from_api(AppRates *rates) {
    CURL *curl;
    CURLcode res;
    HTTPResponse response = {0};
    
    curl = curl_easy_init();
    if (!curl) {
        return FALSE;
    }
    
    // 使用可靠的免費 API
    char url[512];
    snprintf(url, sizeof(url), "https://open.er-api.com/v6/latest/USD");

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36");

    res = curl_easy_perform(curl);

    if (res != CURLE_OK || response.size == 0) {
        printf("API 請求失敗，使用離線匯率\n");
        curl_easy_cleanup(curl);
        if (response.memory) free(response.memory);
        return FALSE;
    }
    
    curl_easy_cleanup(curl);
    
    if (res != CURLE_OK || response.size == 0) {
        if (response.memory) free(response.memory);
        return FALSE;
    }
    
    printf("API 響應: %.200s\n", response.memory);

    // 檢查響應是否為 JSON
    if (response.memory[0] != '{') {
        printf("錯誤：API 返回非 JSON 格式數據\n");
        free(response.memory);
        return FALSE;
    }

    // 解析 JSON
    json_object *root = json_tokener_parse(response.memory);
    if (!root) {
        printf("錯誤：JSON 解析失敗\n");
        free(response.memory);
        return FALSE;
    }
    
    // 處理日期
    json_object *date_obj;
    if (json_object_object_get_ex(root, "time_last_update_utc", &date_obj)) {
        snprintf(rates->as_of, sizeof(rates->as_of), "線上匯率 %s", json_object_get_string(date_obj));
    } else if (json_object_object_get_ex(root, "date", &date_obj)) {
        snprintf(rates->as_of, sizeof(rates->as_of), "線上匯率 %s", json_object_get_string(date_obj));
    } else {
        strcpy(rates->as_of, "線上匯率");
    }
    
    // 處理匯率數據
    json_object *rates_obj;
    if (!json_object_object_get_ex(root, "rates", &rates_obj)) {
        printf("錯誤：找不到匯率數據字段\n");
        json_object_put(root);
        free(response.memory);
        return FALSE;
    }

    printf("成功找到匯率數據字段\n");
    
    // 解析各種貨幣匯率
    AppRates default_rates;
    init_default_rates(&default_rates);
    
    int success_count = 0;
    for (int i = 0; i < NUM_CURRENCIES; i++) {
        json_object *rate_obj;
        if (json_object_object_get_ex(rates_obj, CURRENCIES[i], &rate_obj)) {
            // 這個 API 返回的都是數字，直接獲取 double 值
            rates->rates[i] = json_object_get_double(rate_obj);
            success_count++;
            printf("成功解析 %s 匯率：%.4f\n", CURRENCIES[i], rates->rates[i]);
        } else {
            rates->rates[i] = default_rates.rates[i];
            printf("警告：未找到 %s 匯率，使用預設值：%.4f\n", CURRENCIES[i], rates->rates[i]);
        }
    }

    printf("成功解析 %d/%d 種貨幣匯率\n", success_count, NUM_CURRENCIES);
    
    rates->live = TRUE;
    
    json_object_put(root);
    free(response.memory);
    return TRUE;
}

// 更新計算機顯示
static void update_calc_display(AppState *app) {
    char display[256];
    calc_display(&app->calc, display, sizeof(display));
    printf("更新顯示：%s\n", display);
    gtk_editable_set_text(GTK_EDITABLE(app->calc_display), display);
}

// 計算機按鈕處理
static void on_calc_press(GtkWidget *button, gpointer user_data) {
    AppState *app = (AppState *)user_data;
    const char *label = gtk_button_get_label(GTK_BUTTON(button));

    printf("按鈕被按下：%s\n", label);

    if (strcmp(label, "C") == 0) {
        calc_clear(&app->calc);
    } else if (strcmp(label, "⌫") == 0) {
        calc_backspace(&app->calc);
    } else if (strcmp(label, "=") == 0) {
        calc_evaluate(&app->calc);
    } else if (strcmp(label, "+") == 0 || strcmp(label, "-") == 0 ||
               strcmp(label, "*") == 0 || strcmp(label, "/") == 0) {
        calc_set_operator(&app->calc, label[0]);
    } else {
        calc_input_digit(&app->calc, label);
    }

    update_calc_display(app);
}

// 構建計算機頁面
static GtkWidget* build_calc_tab(AppState *app) {
    GtkWidget *calc_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 5);
    gtk_widget_set_margin_top(calc_box, 10);
    gtk_widget_set_margin_bottom(calc_box, 10);
    gtk_widget_set_margin_start(calc_box, 10);
    gtk_widget_set_margin_end(calc_box, 10);

    // 顯示器
    app->calc_display = gtk_entry_new();
    gtk_editable_set_text(GTK_EDITABLE(app->calc_display), "0");
    gtk_editable_set_editable(GTK_EDITABLE(app->calc_display), FALSE);
    gtk_entry_set_alignment(GTK_ENTRY(app->calc_display), 1.0); // 右對齊
    gtk_box_append(GTK_BOX(calc_box), app->calc_display);

    // 按鈕網格
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 5);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 5);
    gtk_box_append(GTK_BOX(calc_box), grid);

    // 按鈕佈局
    const char *layout[5][4] = {
        {"C", "⌫", "", "/"},
        {"7", "8", "9", "*"},
        {"4", "5", "6", "-"},
        {"1", "2", "3", "+"},
        {"0", ".", "=", ""}
    };

    for (int r = 0; r < 5; r++) {
        for (int c = 0; c < 4; c++) {
            if (strlen(layout[r][c]) == 0) {
                continue;
            }

            GtkWidget *btn = gtk_button_new_with_label(layout[r][c]);
            g_signal_connect(btn, "clicked", G_CALLBACK(on_calc_press), app);

            if (r == 4 && strcmp(layout[r][c], "0") == 0) {
                gtk_grid_attach(GTK_GRID(grid), btn, c, r, 2, 1); // "0" 按鈕佔兩列
            } else {
                gtk_grid_attach(GTK_GRID(grid), btn, c, r, 1, 1);
            }
        }
    }

    return calc_box;
}

// 更新匯率顯示
static void update_fx_display(AppState *app) {
    char buffer[512];
    snprintf(buffer, sizeof(buffer), "匯率版本：%s", app->rates.as_of);
    gtk_label_set_text(GTK_LABEL(app->as_of_label), buffer);

    if (app->rates.live) {
        gtk_label_set_text(GTK_LABEL(app->status_label), "狀態：已更新（線上匯率）");
    } else {
        gtk_label_set_text(GTK_LABEL(app->status_label), "狀態：使用離線匯率");
    }
}

// 匯率轉換處理
static void on_convert(GtkWidget *button, gpointer user_data) {
    AppState *app = (AppState *)user_data;

    const char *amount_text = gtk_editable_get_text(GTK_EDITABLE(app->amount_entry));
    double amount = atof(amount_text);

    if (amount == 0.0 && strcmp(amount_text, "0") != 0) {
        gtk_label_set_text(GTK_LABEL(app->result_label), "錯誤：請輸入有效數字");
        return;
    }

    int from_idx = gtk_combo_box_get_active(GTK_COMBO_BOX(app->from_combo));
    int to_idx = gtk_combo_box_get_active(GTK_COMBO_BOX(app->to_combo));

    if (from_idx < 0 || to_idx < 0 || from_idx >= NUM_CURRENCIES || to_idx >= NUM_CURRENCIES) {
        gtk_label_set_text(GTK_LABEL(app->result_label), "錯誤：請選擇有效貨幣");
        return;
    }

    double result = convert_currency(amount, from_idx, to_idx, &app->rates);

    char result_text[256];
    snprintf(result_text, sizeof(result_text), "結果：%.4f %s", result, CURRENCIES[to_idx]);
    gtk_label_set_text(GTK_LABEL(app->result_label), result_text);
}

// 貨幣交換處理
static void on_swap(GtkWidget *button, gpointer user_data) {
    AppState *app = (AppState *)user_data;

    int from_active = gtk_combo_box_get_active(GTK_COMBO_BOX(app->from_combo));
    int to_active = gtk_combo_box_get_active(GTK_COMBO_BOX(app->to_combo));

    gtk_combo_box_set_active(GTK_COMBO_BOX(app->from_combo), to_active);
    gtk_combo_box_set_active(GTK_COMBO_BOX(app->to_combo), from_active);
}

// 異步匯率獲取的線程函數
typedef struct {
    AppState *app;
} FetchRatesData;

static gboolean update_rates_ui(gpointer user_data) {
    FetchRatesData *data = (FetchRatesData *)user_data;
    AppState *app = data->app;

    update_fx_display(app);
    g_free(data);
    return G_SOURCE_REMOVE;
}

typedef struct {
    AppState *app;
    gboolean success;
    char as_of_text[512];
    char status_text[512];
} UpdateUIData;

static gboolean update_ui_callback(gpointer user_data) {
    UpdateUIData *data = (UpdateUIData *)user_data;

    if (data->success) {
        gtk_label_set_text(GTK_LABEL(data->app->as_of_label), data->as_of_text);
        gtk_label_set_text(GTK_LABEL(data->app->status_label), "狀態：已更新。");
    } else {
        gtk_label_set_text(GTK_LABEL(data->app->status_label), data->status_text);
    }

    g_free(data);
    return G_SOURCE_REMOVE;
}

static void* fetch_rates_thread(void *user_data) {
    FetchRatesData *data = (FetchRatesData *)user_data;
    AppState *app = data->app;

    UpdateUIData *ui_data = g_malloc(sizeof(UpdateUIData));
    ui_data->app = app;

    if (fetch_rates_from_api(&app->rates)) {
        ui_data->success = TRUE;
        snprintf(ui_data->as_of_text, sizeof(ui_data->as_of_text),
                "匯率版本：%s（線上）", app->rates.as_of);
    } else {
        ui_data->success = FALSE;
        strcpy(ui_data->status_text, "狀態：更新失敗（使用離線匯率）");
        printf("獲取匯率失敗\n");
    }

    g_idle_add(update_ui_callback, ui_data);
    g_free(data);

    return NULL;
}

// 刷新匯率處理
static void on_refresh(GtkWidget *button, gpointer user_data) {
    AppState *app = (AppState *)user_data;

    FetchRatesData *data = g_malloc(sizeof(FetchRatesData));
    data->app = app;

    pthread_t thread;
    pthread_create(&thread, NULL, fetch_rates_thread, data);
    pthread_detach(thread);
}

// 構建匯率頁面
static GtkWidget* build_fx_tab(AppState *app) {
    GtkWidget *fx_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_widget_set_margin_top(fx_box, 10);
    gtk_widget_set_margin_bottom(fx_box, 10);
    gtk_widget_set_margin_start(fx_box, 10);
    gtk_widget_set_margin_end(fx_box, 10);

    // 金額輸入
    GtkWidget *amount_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    GtkWidget *amount_label = gtk_label_new("金額：");
    app->amount_entry = gtk_entry_new();
    gtk_editable_set_text(GTK_EDITABLE(app->amount_entry), "100");
    gtk_box_append(GTK_BOX(amount_box), amount_label);
    gtk_box_append(GTK_BOX(amount_box), app->amount_entry);
    gtk_box_append(GTK_BOX(fx_box), amount_box);

    // 貨幣選擇
    GtkWidget *currency_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);

    app->from_combo = gtk_combo_box_text_new();
    app->to_combo = gtk_combo_box_text_new();

    for (int i = 0; i < NUM_CURRENCIES; i++) {
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(app->from_combo), CURRENCIES[i]);
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(app->to_combo), CURRENCIES[i]);
    }
    gtk_combo_box_set_active(GTK_COMBO_BOX(app->from_combo), 0); // USD
    gtk_combo_box_set_active(GTK_COMBO_BOX(app->to_combo), 1);   // EUR

    GtkWidget *from_label = gtk_label_new("從：");
    gtk_box_append(GTK_BOX(currency_box), from_label);
    gtk_box_append(GTK_BOX(currency_box), app->from_combo);

    // 交換按鈕
    GtkWidget *swap_btn = gtk_button_new_with_label("⇄");
    g_signal_connect(swap_btn, "clicked", G_CALLBACK(on_swap), app);
    gtk_box_append(GTK_BOX(currency_box), swap_btn);

    GtkWidget *to_label = gtk_label_new("到：");
    gtk_box_append(GTK_BOX(currency_box), to_label);
    gtk_box_append(GTK_BOX(currency_box), app->to_combo);

    gtk_box_append(GTK_BOX(fx_box), currency_box);

    // 轉換按鈕
    GtkWidget *convert_btn = gtk_button_new_with_label("轉換");
    g_signal_connect(convert_btn, "clicked", G_CALLBACK(on_convert), app);
    gtk_box_append(GTK_BOX(fx_box), convert_btn);

    // 結果顯示
    app->result_label = gtk_label_new("結果：");
    gtk_widget_set_halign(app->result_label, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(fx_box), app->result_label);

    // 匯率信息
    app->as_of_label = gtk_label_new("");
    gtk_widget_set_halign(app->as_of_label, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(fx_box), app->as_of_label);

    // 狀態和刷新
    GtkWidget *status_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    app->status_label = gtk_label_new("狀態：準備中");
    gtk_box_append(GTK_BOX(status_box), app->status_label);

    GtkWidget *refresh_btn = gtk_button_new_with_label("刷新匯率");
    g_signal_connect(refresh_btn, "clicked", G_CALLBACK(on_refresh), app);
    gtk_box_append(GTK_BOX(status_box), refresh_btn);

    gtk_box_append(GTK_BOX(fx_box), status_box);

    return fx_box;
}

// 應用程序啟動
static void on_activate(GtkApplication *app, gpointer user_data) {
    AppState *app_state = (AppState *)user_data;

    app_state->window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(app_state->window), "C 計算機（含匯率轉換・自動抓取）");
    gtk_window_set_default_size(GTK_WINDOW(app_state->window), 380, 500);

    // 創建筆記本（標籤頁）
    app_state->notebook = gtk_notebook_new();
    gtk_window_set_child(GTK_WINDOW(app_state->window), app_state->notebook);

    // 構建計算機頁面
    GtkWidget *calc_tab = build_calc_tab(app_state);
    GtkWidget *calc_label = gtk_label_new("計算機");
    gtk_notebook_append_page(GTK_NOTEBOOK(app_state->notebook), calc_tab, calc_label);

    // 構建匯率頁面
    GtkWidget *fx_tab = build_fx_tab(app_state);
    GtkWidget *fx_label = gtk_label_new("匯率轉換");
    gtk_notebook_append_page(GTK_NOTEBOOK(app_state->notebook), fx_tab, fx_label);

    // 更新匯率顯示
    update_fx_display(app_state);

    // 顯示窗口
    gtk_window_present(GTK_WINDOW(app_state->window));

    // 啟動後自動獲取匯率
    on_refresh(NULL, app_state);
}

// 主函數
int main(int argc, char *argv[]) {
    // 初始化 curl
    curl_global_init(CURL_GLOBAL_DEFAULT);

    AppState app_state = {0};

    // 初始化計算機
    calc_clear(&app_state.calc);

    // 初始化匯率
    init_default_rates(&app_state.rates);

    // 創建應用程序
    app_state.app = gtk_application_new("com.example.c-mac-calc-fx", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app_state.app, "activate", G_CALLBACK(on_activate), &app_state);

    int status = g_application_run(G_APPLICATION(app_state.app), argc, argv);

    g_object_unref(app_state.app);
    curl_global_cleanup();

    return status;
}
