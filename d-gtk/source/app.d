module app;

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
import gtk.Alignment;
import glib.Idle; // for scheduling UI updates from background thread

immutable string[] CURRENCIES = ["USD","EUR","JPY","CNY","MYR","TWD","SGD","GBP"];

struct Rates {
    // 以 USD 為基準：1 USD = rate[currency]
    double[string] rate;
    string asOf; // 顯示版本/日期或來源
    bool live;   // 是否為線上取得
}

Rates defaultRates() {
    Rates r;
    r.asOf = "offline defaults";
    r.live = false;
    r.rate = [
        "USD": 1.0,
        "TWD": 32.50,
        "MYR": 4.50,
        "JPY": 155.00,
        "EUR": 0.90,
        "GBP": 0.76,
        "SGD": 1.35,
        "CNY": 7.10,
    ];
    return r;
}

// 呼叫 exchangerate.host （免 API key）
// GET https://api.exchangerate.host/latest?base=USD&symbols=USD,EUR,JPY,CNY,MYR,TWD,SGD,GBP
Rates fetchRatesFromAPI() {
    auto url = "https://api.exchangerate.host/latest?base=USD&symbols=" ~ CURRENCIES.join(",");
    string body = cast(string)get(url);
    auto j = parseJSON(body);
    Rates r;
    r.live = true;

    if (j.type != JSONType.object) throw new Exception("Unexpected JSON");
    auto obj = j.object;
    string dateStr;
    if ("date" in obj) {
        dateStr = obj["date"].str;
    } else if ("time_last_update_utc" in obj) {
        dateStr = obj["time_last_update_utc"].str;
    } else {
        dateStr = Clock.currTime().toISOExtString();
    }
    r.asOf = "exchangerate.host " ~ dateStr;

    if (!("rates" in obj) || obj["rates"].type != JSONType.object)
        throw new Exception("No rates object");

    auto ratesObj = obj["rates"].object;
    foreach (cur; CURRENCIES) {
        if (cur in ratesObj) {
            r.rate[cur] = ratesObj[cur].floating;
        }
    }
    // 確保 USD 存在且為 1.0（API 以 base=USD 時應為 1）
    r.rate["USD"] = 1.0;
    return r;
}

// 將任意兩種幣別互轉：amount * (USD->to) / (USD->from)
double fxConvert(double amount, string from, string to, in Rates r) {
    enforce(from in r.rate, "未知幣別: " ~ from);
    enforce(to in r.rate, "未知幣別: " ~ to);
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
        win = new Window("D 計算機（含匯率轉換・自動抓取）");
        win.setDefaultSize(380, 500);
        win.addOnDestroy((Widget w) { Main.quit(); });

        // 初始化計算器
        calc = new Calculator();

        notebook = new Notebook();
        win.add(notebook);

        buildCalcTab();
        buildFxTab();

        win.showAll();

        // 開啟後自動抓取匯率（背景執行）
        fetchRatesAsync();

        Main.run();
    }

    void buildCalcTab() {
        auto vbox = new Box(Orientation.VERTICAL, 6);
        vbox.setMarginTop(8);
        vbox.setMarginBottom(8);
        vbox.setMarginStart(8);
        vbox.setMarginEnd(8);

        calcDisplay = new Entry();
        calcDisplay.setEditable(false);
        calcDisplay.setAlignment(Align.FILL);
        calcDisplay.setHexpand(true);
        calcDisplay.setText("0");
        vbox.packStart(calcDisplay, false, false, 0);

        auto grid = new Grid();
        grid.setRowSpacing(6);
        grid.setColumnSpacing(6);
        vbox.packStart(grid, true, true, 0);

        string[][] rows = [
            ["C", "⌫", "/", "*"],
            ["7", "8", "9", "-"],
            ["4", "5", "6", "+"],
            ["1", "2", "3", "="],
            ["0", "."]
        ];

        void addBtn(string label, int r, int c, int w=1, int h=1) {
            auto b = new Button(label);
            b.addOnClicked((Button btn) { onCalcPress(label); });
            grid.attach(b, c, r, w, h);
        }

        foreach (r, row; rows) {
            foreach (c, text; row) {
                if (r == 4 && text == "0") { addBtn(text, cast(int)r, 0, 2, 1); }
                else if (r == 4 && text == ".") { addBtn(text, cast(int)r, 2, 1, 1); }
                else addBtn(text, cast(int)r, cast(int)c, 1, 1);
            }
        }

        notebook.appendPage(vbox, new Label("計算機"));
    }

    void onCalcPress(string label) {
        switch (label) {
            case "C":
                calc.clear();
                updateCalcDisplay();
                break;
            case "⌫":
                calc.backspace();
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
            default:
                if ((label >= "0" && label <= "9") || label == ".") {
                    calc.inputDigit(label);
                    updateCalcDisplay();
                }
                break;
        }
    }

    void updateCalcDisplay() {
        calcDisplay.setText(calc.display());
    }

    void buildFxTab() {
        rates = defaultRates();

        auto vbox = new Box(Orientation.VERTICAL, 8);
        vbox.setMarginTop(8);
        vbox.setMarginBottom(8);
        vbox.setMarginStart(8);
        vbox.setMarginEnd(8);

        auto amtRow = new Box(Orientation.HORIZONTAL, 6);
        amtRow.packStart(new Label("金額:"), false, false, 0);
        amountEntry = new Entry();
        amountEntry.setPlaceholderText("例如 100");
        amtRow.packStart(amountEntry, true, true, 0);
        vbox.packStart(amtRow, false, false, 0);

        auto curRow = new Box(Orientation.HORIZONTAL, 6);
        fromCbx = new ComboBoxText();
        toCbx   = new ComboBoxText();

        foreach (k; CURRENCIES) {
            fromCbx.appendText(k);
            toCbx.appendText(k);
        }
        fromCbx.setActive(0); // USD
        toCbx.setActive(5);   // TWD (索引依 CURRENCIES 順序)

        curRow.packStart(new Label("從:"), false, false, 0);
        curRow.packStart(fromCbx, true, true, 0);
        curRow.packStart(new Label("到:"), false, false, 0);
        curRow.packStart(toCbx, true, true, 0);
        vbox.packStart(curRow, false, false, 0);

        auto btnRow = new Box(Orientation.HORIZONTAL, 6);
        auto convertBtn = new Button("轉換");
        convertBtn.addOnClicked((Button btn) { onConvert(); });
        swapBtn = new Button("⇄ 交換");
        swapBtn.addOnClicked((Button btn) {
            auto fi = fromCbx.getActive();
            auto ti = toCbx.getActive();
            fromCbx.setActive(ti);
            toCbx.setActive(fi);
        });
        refreshBtn = new Button("↻ 更新匯率");
        refreshBtn.addOnClicked((Button btn) { fetchRatesAsync(); });
        btnRow.packStart(convertBtn, false, false, 0);
        btnRow.packStart(swapBtn, false, false, 0);
        btnRow.packStart(refreshBtn, false, false, 0);
        vbox.packStart(btnRow, false, false, 0);

        resultLbl = new Label("結果：—");
        vbox.packStart(resultLbl, false, false, 0);

        asOfLbl = new Label("匯率版本：" ~ rates.asOf ~ "（離線）");
        vbox.packStart(asOfLbl, false, false, 0);

        statusLbl = new Label("");
        vbox.packEnd(statusLbl, false, false, 0);

        notebook.appendPage(vbox, new Label("匯率轉換"));
    }

    void onConvert() {
        auto amtText = amountEntry.getText().strip;
        if (amtText.length == 0) { resultLbl.setText("結果：請輸入金額"); return; }
        double amt;
        try {
            amt = to!double(amtText);
        } catch (Exception e) {
            resultLbl.setText("結果：金額格式錯誤");
            return;
        }
        auto from = fromCbx.getActiveText();
        auto to   = toCbx.getActiveText();
        try {
            double result = fxConvert(amt, from, to, rates);
            resultLbl.setText(format!"結果：%.4f %s"(result, to));
        } catch (Exception e) {
            resultLbl.setText("結果：" ~ e.msg);
        }
    }

    void fetchRatesAsync() {
        statusLbl.setText("狀態：正在從 exchangerate.host 取得最新匯率…");
        // 背景 thread 抓取，完成後用 Idle.add 回主緒更新 GUI
        new Thread({
            Rates newRates;
            string err;
            try {
                newRates = fetchRatesFromAPI();
            } catch (Exception e) {
                err = e.msg;
            }
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
    new App();
    return 0;
}