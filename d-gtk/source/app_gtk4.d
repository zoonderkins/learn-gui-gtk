module app_gtk4;

import std.stdio;
import std.string;
import std.conv;
import std.exception;
import std.datetime;
import std.math;
import std.algorithm;
import std.format;
import std.json;
import std.net.curl;
import core.thread;

// GTK 4 適配 - 使用 GTK 3 綁定但適配 GTK 4 API
// 由於 gidgen 綁定生成複雜，我們使用 GTK 3 綁定並手動適配 GTK 4 變化
import gtk.Main;
import gtk.Window;
import gtk.Widget;
import gtk.Box;
import gtk.Grid;
import gtk.Button;
import gtk.Entry;
import gtk.Label;
import gtk.ComboBoxText;
import gtk.Notebook;
import glib.Idle;

immutable string[] CURRENCIES = ["USD","EUR","JPY","CNY","MYR","TWD","SGD","GBP"];

struct Rates {
    // 以 USD 為基準：1 USD = rate[currency]
    double[string] rate;
    string asOf;
    bool live = false;
}

Rates defaultRates() {
    Rates r;
    r.rate["USD"] = 1.0;
    r.rate["EUR"] = 0.85;
    r.rate["JPY"] = 110.0;
    r.rate["CNY"] = 6.5;
    r.rate["MYR"] = 4.2;
    r.rate["TWD"] = 28.0;
    r.rate["SGD"] = 1.35;
    r.rate["GBP"] = 0.75;
    r.asOf = "預設匯率（離線）";
    return r;
}

Rates fetchRatesFromAPI() {
    // 使用 fixer.io 的免費 API（無需 API key 的舊版本端點）
    auto url = "https://api.fixer.io/latest?base=USD&symbols=" ~ CURRENCIES.join(",");
    string body;

    try {
        body = cast(string)get(url);
        writeln("API 響應：", body[0..min(200, body.length)]); // 調試輸出
    } catch (Exception e) {
        writeln("API 請求失敗，嘗試備用 API：", e.msg);
        // 備用 API：exchangerate-api.com
        url = "https://api.exchangerate-api.com/v4/latest/USD";
        body = cast(string)get(url);
        writeln("備用 API 響應：", body[0..min(200, body.length)]);
    }

    auto j = parseJSON(body);
    Rates r;
    r.live = true;

    if (j.type != JSONType.object) throw new Exception("Unexpected JSON format");
    auto obj = j.object;

    string dateStr;
    if ("date" in obj) {
        dateStr = obj["date"].str;
    } else if ("time_last_updated" in obj) {
        dateStr = obj["time_last_updated"].str;
    } else {
        dateStr = Clock.currTime().toISOExtString();
    }
    r.asOf = "線上匯率 " ~ dateStr;

    // 檢查不同的 rates 字段名稱
    JSONValue ratesObj;
    if ("rates" in obj && obj["rates"].type == JSONType.object) {
        ratesObj = obj["rates"];
    } else if ("conversion_rates" in obj && obj["conversion_rates"].type == JSONType.object) {
        ratesObj = obj["conversion_rates"];
    } else {
        throw new Exception("找不到匯率數據字段");
    }

    foreach (cur; CURRENCIES) {
        if (cur in ratesObj.object) {
            auto rateValue = ratesObj.object[cur];
            try {
                if (rateValue.type == JSONType.float_) {
                    r.rate[cur] = rateValue.floating;
                } else if (rateValue.type == JSONType.integer) {
                    r.rate[cur] = cast(double)rateValue.integer;
                } else if (rateValue.type == JSONType.string) {
                    r.rate[cur] = to!double(rateValue.str);
                } else {
                    throw new Exception("未知的匯率數據類型");
                }
                writeln("成功解析 ", cur, " 匯率：", r.rate[cur]);
            } catch (Exception e) {
                r.rate[cur] = defaultRates().rate[cur];
                writeln("警告：解析 ", cur, " 匯率失敗（", e.msg, "），使用預設值：", r.rate[cur]);
            }
        } else {
            r.rate[cur] = defaultRates().rate[cur];
            writeln("警告：未找到 ", cur, " 匯率，使用預設值：", r.rate[cur]);
        }
    }
    return r;
}

double fxConvert(double amount, string from, string to, Rates r) {
    if (from == to) return amount;
    double usdFrom = r.rate[from];
    double usdTo   = r.rate[to];
    return amount * (usdTo / usdFrom);
}

class Calculator {
    private string current = "";     // 輸入中的數字（含小數點）
    private double acc = 0;          // 累計器
    private char op = '\0';          // 當前運算子
    private bool justEvaluated = false;

    void clear() {
        current = "";
        acc = 0;
        op = '\0';
        justEvaluated = false;
    }

    void inputDigit(string d) {
        if (justEvaluated && (d >= "0" && d <= "9")) {
            clear();
        }
        if (d == "." && current.canFind('.')) return; // 避免多個小數點
        current ~= d;
    }

    private double currentValue() {
        if (current.length == 0) return 0;
        return to!double(current);
    }

    private void applyPending() {
        double x = currentValue();
        if (op == '\0') {
            acc = x;
        } else {
            switch (op) {
                case '+': acc += x; break;
                case '-': acc -= x; break;
                case '*': acc *= x; break;
                case '/': acc = (x == 0) ? double.nan : acc / x; break;
                default: break;
            }
        }
        current = "";
    }

    void setOp(char newOp) {
        if (current.length == 0 && op != '\0') { op = newOp; return; }
        applyPending();
        op = newOp;
        justEvaluated = false;
    }

    double evaluate() {
        applyPending();
        op = '\0';
        justEvaluated = true;
        return acc;
    }

    void backspace() {
        if (current.length > 0) current = current[0 .. $-1];
    }

    string display() const {
        if (current.length) return current;
        if (isNaN(acc)) return "錯誤";
        return format!"%.12g"(acc);
    }
}

// GTK 4 適配版本的應用程序類
class App {
    Window win;
    Notebook notebook;

    // 計算機頁面
    Entry calcDisplay;
    Calculator calc;

    // 匯率頁面
    Entry amountEntry;
    ComboBoxText fromCbx, toCbx;
    Label resultLbl, asOfLbl, statusLbl;
    Button swapBtn, refreshBtn;
    Rates rates;

    this() {
        string[] args;
        Main.init(args);

        // 初始化計算器
        calc = new Calculator();

        win = new Window("D 計算機（含匯率轉換・自動抓取）- GTK 4 適配版");
        win.setDefaultSize(380, 500);
        win.addOnDestroy((Widget w) { Main.quit(); });

        notebook = new Notebook();
        win.add(notebook);

        buildCalcTab();
        buildFxTab();

        // 初始化匯率數據
        rates = defaultRates();
        updateFxDisplay();

        win.showAll();

        // 開啟後自動抓取匯率（背景執行）
        fetchRatesAsync();
    }

    void run() {
        Main.run();
    }

    void buildCalcTab() {
        auto calcBox = new Box(Orientation.VERTICAL, 5);
        calcBox.setBorderWidth(10);

        // 顯示器
        calcDisplay = new Entry();
        calcDisplay.setText("0");
        calcDisplay.setEditable(false);
        calcDisplay.setAlignment(1.0); // 右對齊
        calcBox.packStart(calcDisplay, false, false, 5);

        // 按鈕網格
        auto grid = new Grid();
        grid.setRowSpacing(5);
        grid.setColumnSpacing(5);
        calcBox.packStart(grid, true, true, 5);

        // 按鈕佈局
        string[][] layout = [
            ["C", "⌫", "", "/"],
            ["7", "8", "9", "*"],
            ["4", "5", "6", "-"],
            ["1", "2", "3", "+"],
            ["0", ".", "=", ""]
        ];

        foreach (r, row; layout) {
            foreach (c, text; row) {
                if (text.length == 0) continue;

                auto b = new Button(text);
                // 使用按鈕的標籤來獲取文字，避免閉包問題
                b.addOnClicked((Button btn) {
                    string label = btn.getLabel();
                    onCalcPress(label);
                });

                if (r == 4 && text == "0") {
                    grid.attach(b, cast(int)c, cast(int)r, 2, 1);
                }
                else if (r == 4 && text == ".") {
                    grid.attach(b, cast(int)c, cast(int)r, 1, 1);
                }
                else {
                    grid.attach(b, cast(int)c, cast(int)r, 1, 1);
                }
            }
        }

        notebook.appendPage(calcBox, new Label("計算機"));
    }

    void onCalcPress(string label) {
        writeln("按鈕被按下：", label); // 調試輸出
        switch (label) {
            case "0": case "1": case "2": case "3": case "4":
            case "5": case "6": case "7": case "8": case "9":
            case ".":
                calc.inputDigit(label);
                updateCalcDisplay();
                break;
            case "+": case "-": case "*": case "/":
                calc.setOp(label[0]);
                updateCalcDisplay();
                break;
            case "=":
                calc.evaluate();
                updateCalcDisplay();
                break;
            case "C":
                calc.clear();
                updateCalcDisplay();
                break;
            case "⌫":
                calc.backspace();
                updateCalcDisplay();
                break;
            default: break;
        }
    }

    void updateCalcDisplay() {
        string displayText = calc.display();
        writeln("更新顯示：", displayText); // 調試輸出
        calcDisplay.setText(displayText);
    }

    void buildFxTab() {
        auto fxBox = new Box(Orientation.VERTICAL, 10);
        fxBox.setBorderWidth(10);

        // 金額輸入
        auto amountBox = new Box(Orientation.HORIZONTAL, 5);
        amountBox.packStart(new Label("金額："), false, false, 0);
        amountEntry = new Entry();
        amountEntry.setText("100");
        amountBox.packStart(amountEntry, true, true, 0);
        fxBox.packStart(amountBox, false, false, 0);

        // 貨幣選擇
        auto currencyBox = new Box(Orientation.HORIZONTAL, 5);

        fromCbx = new ComboBoxText();
        toCbx = new ComboBoxText();
        foreach (cur; CURRENCIES) {
            fromCbx.appendText(cur);
            toCbx.appendText(cur);
        }
        fromCbx.setActive(0); // USD
        toCbx.setActive(1);   // EUR

        currencyBox.packStart(new Label("從："), false, false, 0);
        currencyBox.packStart(fromCbx, true, true, 0);

        swapBtn = new Button("⇄");
        swapBtn.addOnClicked((Button btn) {
            auto fi = fromCbx.getActive();
            auto ti = toCbx.getActive();
            fromCbx.setActive(ti);
            toCbx.setActive(fi);
        });
        currencyBox.packStart(swapBtn, false, false, 0);

        currencyBox.packStart(new Label("到："), false, false, 0);
        currencyBox.packStart(toCbx, true, true, 0);

        fxBox.packStart(currencyBox, false, false, 0);

        // 轉換按鈕
        auto convertBtn = new Button("轉換");
        convertBtn.addOnClicked((Button btn) { onConvert(); });
        fxBox.packStart(convertBtn, false, false, 0);

        // 結果顯示
        resultLbl = new Label("結果：");
        resultLbl.setAlignment(0.0, 0.5);
        fxBox.packStart(resultLbl, false, false, 0);

        // 匯率信息
        asOfLbl = new Label("");
        asOfLbl.setAlignment(0.0, 0.5);
        fxBox.packStart(asOfLbl, false, false, 0);

        // 狀態和刷新
        auto statusBox = new Box(Orientation.HORIZONTAL, 5);
        statusLbl = new Label("狀態：準備中");
        statusBox.packStart(statusLbl, true, true, 0);

        refreshBtn = new Button("刷新匯率");
        refreshBtn.addOnClicked((Button btn) { fetchRatesAsync(); });
        statusBox.packStart(refreshBtn, false, false, 0);

        fxBox.packStart(statusBox, false, false, 0);

        notebook.appendPage(fxBox, new Label("匯率轉換"));
    }

    void onConvert() {
        try {
            double amt = to!double(amountEntry.getText());
            string from = CURRENCIES[fromCbx.getActive()];
            string to = CURRENCIES[toCbx.getActive()];
            double result = fxConvert(amt, from, to, rates);
            resultLbl.setText(format!"結果：%.4f %s"(result, to));
        } catch (Exception e) {
            resultLbl.setText("錯誤：請輸入有效數字");
        }
    }

    void updateFxDisplay() {
        asOfLbl.setText("匯率版本：" ~ rates.asOf);
        if (rates.live) {
            statusLbl.setText("狀態：已更新（線上匯率）");
        } else {
            statusLbl.setText("狀態：使用離線匯率");
        }
    }

    void fetchRatesAsync() {
        statusLbl.setText("狀態：正在更新匯率...");

        // 在背景線程中獲取匯率
        new Thread({
            string err = "";
            Rates newRates;

            try {
                newRates = fetchRatesFromAPI();
            } catch (Exception e) {
                err = e.msg;
                newRates = defaultRates();
            }

            // 使用 Idle 在主線程中更新 UI
            new Idle({
                if (err.length) {
                    statusLbl.setText("狀態：更新失敗（使用離線匯率）。錯誤：" ~ err);
                } else {
                    rates = newRates;
                    asOfLbl.setText("匯率版本：" ~ rates.asOf ~ "（線上）");
                    statusLbl.setText("狀態：已更新。");
                }
                return false; // run once
            });
        }).start();
    }
}

int main(string[] args) {
    auto app = new App();
    app.run();
    return 0;
}
