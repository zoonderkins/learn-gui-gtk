use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, Box, Button, ComboBoxText, Entry, Grid, Label, Notebook, Orientation};
use glib::clone;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

// 支援的貨幣
const CURRENCIES: &[&str] = &["USD", "EUR", "JPY", "CNY", "MYR", "TWD", "SGD", "GBP"];

// 匯率結構
#[derive(Debug, Clone, serde::Deserialize)]
pub struct Rates {
    pub rates: HashMap<String, f64>,
    pub date: Option<String>,
    pub time_last_updated: Option<String>,
}

// 應用程序匯率狀態
#[derive(Debug, Clone)]
pub struct AppRates {
    pub rates: HashMap<String, f64>,
    pub as_of: String,
    pub live: bool,
}

impl Default for AppRates {
    fn default() -> Self {
        let mut rates = HashMap::new();
        rates.insert("USD".to_string(), 1.0);
        rates.insert("EUR".to_string(), 0.85);
        rates.insert("JPY".to_string(), 110.0);
        rates.insert("CNY".to_string(), 6.5);
        rates.insert("MYR".to_string(), 4.2);
        rates.insert("TWD".to_string(), 28.0);
        rates.insert("SGD".to_string(), 1.35);
        rates.insert("GBP".to_string(), 0.75);

        Self {
            rates,
            as_of: "預設匯率（離線）".to_string(),
            live: false,
        }
    }
}

// 計算機結構
#[derive(Debug, Clone)]
pub struct Calculator {
    current: String,
    accumulator: f64,
    operator: Option<char>,
    just_evaluated: bool,
}

impl Default for Calculator {
    fn default() -> Self {
        Self {
            current: String::new(),
            accumulator: 0.0,
            operator: None,
            just_evaluated: false,
        }
    }
}

impl Calculator {
    pub fn clear(&mut self) {
        self.current.clear();
        self.accumulator = 0.0;
        self.operator = None;
        self.just_evaluated = false;
    }

    pub fn input_digit(&mut self, digit: &str) {
        if self.just_evaluated && digit.chars().all(|c| c.is_ascii_digit()) {
            self.clear();
        }
        if digit == "." && self.current.contains('.') {
            return; // 避免多個小數點
        }
        self.current.push_str(digit);
    }

    fn current_value(&self) -> f64 {
        if self.current.is_empty() {
            0.0
        } else {
            self.current.parse().unwrap_or(0.0)
        }
    }

    fn apply_pending(&mut self) {
        let x = self.current_value();
        if let Some(op) = self.operator {
            match op {
                '+' => self.accumulator += x,
                '-' => self.accumulator -= x,
                '*' => self.accumulator *= x,
                '/' => {
                    if x != 0.0 {
                        self.accumulator /= x;
                    } else {
                        self.accumulator = 0.0; // 避免除零錯誤
                    }
                }
                _ => {}
            }
        } else {
            self.accumulator = x;
        }
        self.current.clear();
    }

    pub fn set_operator(&mut self, op: char) {
        if self.current.is_empty() && self.operator.is_some() {
            self.operator = Some(op);
            return;
        }
        self.apply_pending();
        self.operator = Some(op);
        self.just_evaluated = false;
    }

    pub fn evaluate(&mut self) -> f64 {
        self.apply_pending();
        self.operator = None;
        self.just_evaluated = true;
        self.accumulator
    }

    pub fn backspace(&mut self) {
        if !self.current.is_empty() {
            self.current.pop();
        }
    }

    pub fn display(&self) -> String {
        if !self.current.is_empty() {
            self.current.clone()
        } else {
            format!("{}", self.accumulator)
        }
    }
}

// 匯率轉換
pub fn convert_currency(amount: f64, from: &str, to: &str, rates: &AppRates) -> f64 {
    if from == to {
        return amount;
    }
    let from_rate = rates.rates.get(from).unwrap_or(&1.0);
    let to_rate = rates.rates.get(to).unwrap_or(&1.0);
    amount * (to_rate / from_rate)
}

// 獲取線上匯率
pub async fn fetch_rates_from_api() -> anyhow::Result<AppRates> {
    let currencies_str = CURRENCIES.join(",");

    // 嘗試主要 API
    let url = format!("https://api.fixer.io/latest?base=USD&symbols={}", currencies_str);

    let response = match reqwest::get(&url).await {
        Ok(resp) if resp.status().is_success() => resp,
        Ok(_) | Err(_) => {
            println!("主 API 失敗，嘗試備用 API");
            // 備用 API
            let backup_url = "https://api.exchangerate-api.com/v4/latest/USD";
            reqwest::get(backup_url).await?
        }
    };

    let body = response.text().await?;
    println!("API 響應: {}", &body[..body.len().min(200)]);

    let api_response: serde_json::Value = serde_json::from_str(&body)?;

    let mut app_rates = AppRates::default();
    app_rates.live = true;

    // 處理日期
    if let Some(date) = api_response.get("date").and_then(|d| d.as_str()) {
        app_rates.as_of = format!("線上匯率 {}", date);
    } else if let Some(time) = api_response.get("time_last_updated").and_then(|t| t.as_str()) {
        app_rates.as_of = format!("線上匯率 {}", time);
    } else {
        app_rates.as_of = format!("線上匯率 {}", chrono::Utc::now().format("%Y-%m-%d"));
    }

    // 處理匯率數據
    let rates_data = api_response.get("rates")
        .or_else(|| api_response.get("conversion_rates"))
        .ok_or_else(|| anyhow::anyhow!("找不到匯率數據字段"))?;

    let default_rates = AppRates::default();
    for currency in CURRENCIES {
        if let Some(rate_value) = rates_data.get(*currency) {
            let rate = match rate_value {
                serde_json::Value::Number(n) => n.as_f64().unwrap_or(0.0),
                serde_json::Value::String(s) => s.parse().unwrap_or(0.0),
                _ => {
                    println!("警告：未知的 {} 匯率數據類型，使用預設值", currency);
                    *default_rates.rates.get(*currency).unwrap_or(&1.0)
                }
            };
            app_rates.rates.insert(currency.to_string(), rate);
            println!("成功解析 {} 匯率：{:.4}", currency, rate);
        } else {
            let default_rate = *default_rates.rates.get(*currency).unwrap_or(&1.0);
            app_rates.rates.insert(currency.to_string(), default_rate);
            println!("警告：未找到 {} 匯率，使用預設值：{:.4}", currency, default_rate);
        }
    }

    Ok(app_rates)
}

// 應用程序狀態
pub struct AppState {
    pub calculator: Rc<RefCell<Calculator>>,
    pub rates: Rc<RefCell<AppRates>>,
    pub calc_display: Entry,
    pub amount_entry: Entry,
    pub from_combo: ComboBoxText,
    pub to_combo: ComboBoxText,
    pub result_label: Label,
    pub as_of_label: Label,
    pub status_label: Label,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            calculator: Rc::new(RefCell::new(Calculator::default())),
            rates: Rc::new(RefCell::new(AppRates::default())),
            calc_display: Entry::new(),
            amount_entry: Entry::new(),
            from_combo: ComboBoxText::new(),
            to_combo: ComboBoxText::new(),
            result_label: Label::new(Some("結果：")),
            as_of_label: Label::new(Some("")),
            status_label: Label::new(Some("狀態：準備中")),
        }
    }

    pub fn update_calc_display(&self) {
        let display = self.calculator.borrow().display();
        println!("更新顯示：{}", display);
        self.calc_display.set_text(&display);
    }

    pub fn update_fx_display(&self) {
        let rates = self.rates.borrow();
        self.as_of_label.set_text(&format!("匯率版本：{}", rates.as_of));
        if rates.live {
            self.status_label.set_text("狀態：已更新（線上匯率）");
        } else {
            self.status_label.set_text("狀態：使用離線匯率");
        }
    }
}

// 構建計算機頁面
pub fn build_calc_tab(state: &AppState) -> Box {
    let calc_box = Box::new(Orientation::Vertical, 5);
    calc_box.set_margin_top(10);
    calc_box.set_margin_bottom(10);
    calc_box.set_margin_start(10);
    calc_box.set_margin_end(10);

    // 顯示器
    state.calc_display.set_text("0");
    state.calc_display.set_editable(false);
    gtk4::prelude::EntryExt::set_alignment(&state.calc_display, 1.0); // 右對齊
    calc_box.append(&state.calc_display);

    // 按鈕網格
    let grid = Grid::new();
    grid.set_row_spacing(5);
    grid.set_column_spacing(5);
    calc_box.append(&grid);

    // 按鈕佈局
    let layout = [
        ["C", "⌫", "", "/"],
        ["7", "8", "9", "*"],
        ["4", "5", "6", "-"],
        ["1", "2", "3", "+"],
        ["0", ".", "=", ""],
    ];

    for (r, row) in layout.iter().enumerate() {
        for (c, &text) in row.iter().enumerate() {
            if text.is_empty() {
                continue;
            }

            let btn = Button::with_label(text);
            let calculator_clone = state.calculator.clone();
            let calc_display_clone = state.calc_display.clone();
            let text_owned = text.to_string();

            btn.connect_clicked({
                let calculator_clone = calculator_clone.clone();
                let calc_display_clone = calc_display_clone.clone();
                let text_owned = text_owned.clone();
                move |_| {
                    on_calc_press_simple(&calculator_clone, &calc_display_clone, &text_owned);
                }
            });

            if r == 4 && text == "0" {
                grid.attach(&btn, c as i32, r as i32, 2, 1); // "0" 按鈕佔兩列
            } else {
                grid.attach(&btn, c as i32, r as i32, 1, 1);
            }
        }
    }

    calc_box
}

// 計算機按鈕處理
pub fn on_calc_press(state: &AppState, label: &str) {
    println!("按鈕被按下：{}", label);

    let mut calc = state.calculator.borrow_mut();
    match label {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "." => {
            calc.input_digit(label);
        }
        "+" | "-" | "*" | "/" => {
            calc.set_operator(label.chars().next().unwrap());
        }
        "=" => {
            calc.evaluate();
        }
        "C" => {
            calc.clear();
        }
        "⌫" => {
            calc.backspace();
        }
        _ => {}
    }
    drop(calc);
    state.update_calc_display();
}

// 簡化的計算機按鈕處理
pub fn on_calc_press_simple(calculator: &Rc<RefCell<Calculator>>, display: &Entry, label: &str) {
    println!("按鈕被按下：{}", label);

    let mut calc = calculator.borrow_mut();
    match label {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "." => {
            calc.input_digit(label);
        }
        "+" | "-" | "*" | "/" => {
            calc.set_operator(label.chars().next().unwrap());
        }
        "=" => {
            calc.evaluate();
        }
        "C" => {
            calc.clear();
        }
        "⌫" => {
            calc.backspace();
        }
        _ => {}
    }

    let display_text = calc.display();
    drop(calc);

    println!("更新顯示：{}", display_text);
    display.set_text(&display_text);
}

// 構建匯率頁面
pub fn build_fx_tab(state: &AppState) -> Box {
    let fx_box = Box::new(Orientation::Vertical, 10);
    fx_box.set_margin_top(10);
    fx_box.set_margin_bottom(10);
    fx_box.set_margin_start(10);
    fx_box.set_margin_end(10);

    // 金額輸入
    let amount_box = Box::new(Orientation::Horizontal, 5);
    let amount_label = Label::new(Some("金額："));
    state.amount_entry.set_text("100");
    amount_box.append(&amount_label);
    amount_box.append(&state.amount_entry);
    fx_box.append(&amount_box);

    // 貨幣選擇
    let currency_box = Box::new(Orientation::Horizontal, 5);

    for currency in CURRENCIES {
        state.from_combo.append_text(currency);
        state.to_combo.append_text(currency);
    }
    state.from_combo.set_active(Some(0)); // USD
    state.to_combo.set_active(Some(1));   // EUR

    let from_label = Label::new(Some("從："));
    currency_box.append(&from_label);
    currency_box.append(&state.from_combo);

    // 交換按鈕
    let swap_btn = Button::with_label("⇄");
    let from_combo_clone = state.from_combo.clone();
    let to_combo_clone = state.to_combo.clone();
    swap_btn.connect_clicked(move |_| {
        let from_active = from_combo_clone.active();
        let to_active = to_combo_clone.active();
        from_combo_clone.set_active(to_active);
        to_combo_clone.set_active(from_active);
    });
    currency_box.append(&swap_btn);

    let to_label = Label::new(Some("到："));
    currency_box.append(&to_label);
    currency_box.append(&state.to_combo);

    fx_box.append(&currency_box);

    // 轉換按鈕
    let convert_btn = Button::with_label("轉換");
    let amount_entry_clone = state.amount_entry.clone();
    let from_combo_clone = state.from_combo.clone();
    let to_combo_clone = state.to_combo.clone();
    let result_label_clone = state.result_label.clone();
    let rates_clone = state.rates.clone();

    convert_btn.connect_clicked({
        let amount_entry_clone = amount_entry_clone.clone();
        let from_combo_clone = from_combo_clone.clone();
        let to_combo_clone = to_combo_clone.clone();
        let result_label_clone = result_label_clone.clone();
        let rates_clone = rates_clone.clone();
        move |_| {
            on_convert_simple(&amount_entry_clone, &from_combo_clone, &to_combo_clone, &result_label_clone, &rates_clone);
        }
    });
    fx_box.append(&convert_btn);

    // 結果顯示
    state.result_label.set_halign(gtk4::Align::Start);
    fx_box.append(&state.result_label);

    // 匯率信息
    state.as_of_label.set_halign(gtk4::Align::Start);
    fx_box.append(&state.as_of_label);

    // 狀態和刷新
    let status_box = Box::new(Orientation::Horizontal, 5);
    status_box.append(&state.status_label);

    let refresh_btn = Button::with_label("刷新匯率");
    let rates_clone2 = state.rates.clone();
    let as_of_label_clone = state.as_of_label.clone();
    let status_label_clone = state.status_label.clone();

    refresh_btn.connect_clicked({
        let rates_clone2 = rates_clone2.clone();
        let as_of_label_clone = as_of_label_clone.clone();
        let status_label_clone = status_label_clone.clone();
        move |_| {
            fetch_rates_async_simple(&rates_clone2, &as_of_label_clone, &status_label_clone);
        }
    });
    status_box.append(&refresh_btn);

    fx_box.append(&status_box);

    fx_box
}

// 匯率轉換處理
pub fn on_convert(state: &AppState) {
    let amount_text = state.amount_entry.text();
    let amount: f64 = match amount_text.parse() {
        Ok(a) => a,
        Err(_) => {
            state.result_label.set_text("錯誤：請輸入有效數字");
            return;
        }
    };

    let from_index = state.from_combo.active().unwrap_or(0) as usize;
    let to_index = state.to_combo.active().unwrap_or(0) as usize;

    if from_index >= CURRENCIES.len() || to_index >= CURRENCIES.len() {
        state.result_label.set_text("錯誤：請選擇有效貨幣");
        return;
    }

    let from = CURRENCIES[from_index];
    let to = CURRENCIES[to_index];

    let rates = state.rates.borrow();
    let result = convert_currency(amount, from, to, &rates);
    state.result_label.set_text(&format!("結果：{:.4} {}", result, to));
}

// 簡化的匯率轉換處理
pub fn on_convert_simple(
    amount_entry: &Entry,
    from_combo: &ComboBoxText,
    to_combo: &ComboBoxText,
    result_label: &Label,
    rates: &Rc<RefCell<AppRates>>
) {
    let amount_text = amount_entry.text();
    let amount: f64 = match amount_text.parse() {
        Ok(a) => a,
        Err(_) => {
            result_label.set_text("錯誤：請輸入有效數字");
            return;
        }
    };

    let from_index = from_combo.active().unwrap_or(0) as usize;
    let to_index = to_combo.active().unwrap_or(0) as usize;

    if from_index >= CURRENCIES.len() || to_index >= CURRENCIES.len() {
        result_label.set_text("錯誤：請選擇有效貨幣");
        return;
    }

    let from = CURRENCIES[from_index];
    let to = CURRENCIES[to_index];

    let rates_borrow = rates.borrow();
    let result = convert_currency(amount, from, to, &rates_borrow);
    result_label.set_text(&format!("結果：{:.4} {}", result, to));
}

// 異步獲取匯率
pub fn fetch_rates_async(state: &AppState) {
    state.status_label.set_text("狀態：正在更新匯率...");

    let rates_clone = state.rates.clone();
    let as_of_label_clone = state.as_of_label.clone();
    let status_label_clone = state.status_label.clone();

    glib::spawn_future_local(async move {
        match fetch_rates_from_api().await {
            Ok(new_rates) => {
                *rates_clone.borrow_mut() = new_rates.clone();
                as_of_label_clone.set_text(&format!("匯率版本：{}（線上）", new_rates.as_of));
                status_label_clone.set_text("狀態：已更新。");
            }
            Err(e) => {
                println!("獲取匯率失敗：{}", e);
                status_label_clone.set_text(&format!("狀態：更新失敗（使用離線匯率）。錯誤：{}", e));
            }
        }
    });
}

// 簡化的異步獲取匯率
pub fn fetch_rates_async_simple(
    rates: &Rc<RefCell<AppRates>>,
    as_of_label: &Label,
    status_label: &Label
) {
    status_label.set_text("狀態：正在更新匯率...");

    let rates_clone = rates.clone();
    let as_of_label_clone = as_of_label.clone();
    let status_label_clone = status_label.clone();

    glib::spawn_future_local(async move {
        match fetch_rates_from_api().await {
            Ok(new_rates) => {
                *rates_clone.borrow_mut() = new_rates.clone();
                as_of_label_clone.set_text(&format!("匯率版本：{}（線上）", new_rates.as_of));
                status_label_clone.set_text("狀態：已更新。");
            }
            Err(e) => {
                println!("獲取匯率失敗：{}", e);
                status_label_clone.set_text(&format!("狀態：更新失敗（使用離線匯率）。錯誤：{}", e));
            }
        }
    });
}

// 構建應用程序
pub fn build_ui(app: &Application) {
    let window = ApplicationWindow::builder()
        .application(app)
        .title("Rust 計算機（含匯率轉換・自動抓取）")
        .default_width(380)
        .default_height(500)
        .build();

    let state = AppState::new();

    // 創建筆記本（標籤頁）
    let notebook = Notebook::new();
    window.set_child(Some(&notebook));

    // 構建計算機頁面
    let calc_tab = build_calc_tab(&state);
    let calc_label = Label::new(Some("計算機"));
    notebook.append_page(&calc_tab, Some(&calc_label));

    // 構建匯率頁面
    let fx_tab = build_fx_tab(&state);
    let fx_label = Label::new(Some("匯率轉換"));
    notebook.append_page(&fx_tab, Some(&fx_label));

    // 更新匯率顯示
    state.update_fx_display();

    // 顯示窗口
    window.present();

    // 啟動後自動獲取匯率
    fetch_rates_async_simple(&state.rates, &state.as_of_label, &state.status_label);
}

#[tokio::main]
async fn main() -> glib::ExitCode {
    let app = Application::builder()
        .application_id("com.example.rust-mac-calc-fx")
        .build();

    app.connect_activate(build_ui);
    app.run()
}
