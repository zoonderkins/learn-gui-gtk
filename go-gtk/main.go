package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/diamondburned/gotk4/pkg/gio/v2"
	"github.com/diamondburned/gotk4/pkg/glib/v2"
	"github.com/diamondburned/gotk4/pkg/gtk/v4"
)

// 支援的貨幣
var currencies = []string{"USD", "EUR", "JPY", "CNY", "MYR", "TWD", "SGD", "GBP"}

// 匯率結構
type Rates struct {
	Rate map[string]float64 `json:"rates"`
	AsOf string             `json:"asOf"`
	Live bool               `json:"live"`
}

// 計算機結構
type Calculator struct {
	current       string
	accumulator   float64
	operator      rune
	justEvaluated bool
}

// 應用程序結構
type App struct {
	app      *gtk.Application
	window   *gtk.ApplicationWindow
	notebook *gtk.Notebook

	// 計算機頁面
	calcDisplay *gtk.Entry
	calc        *Calculator

	// 匯率頁面
	amountEntry *gtk.Entry
	fromCombo   *gtk.ComboBoxText
	toCombo     *gtk.ComboBoxText
	resultLabel *gtk.Label
	asOfLabel   *gtk.Label
	statusLabel *gtk.Label
	swapBtn     *gtk.Button
	refreshBtn  *gtk.Button
	rates       *Rates
}

// 預設匯率
func getDefaultRates() *Rates {
	return &Rates{
		Rate: map[string]float64{
			"USD": 1.0,
			"EUR": 0.85,
			"JPY": 110.0,
			"CNY": 6.5,
			"MYR": 4.2,
			"TWD": 28.0,
			"SGD": 1.35,
			"GBP": 0.75,
		},
		AsOf: "預設匯率（離線）",
		Live: false,
	}
}

// 計算機方法
func NewCalculator() *Calculator {
	return &Calculator{
		current:       "",
		accumulator:   0,
		operator:      0,
		justEvaluated: false,
	}
}

func (c *Calculator) Clear() {
	c.current = ""
	c.accumulator = 0
	c.operator = 0
	c.justEvaluated = false
}

func (c *Calculator) InputDigit(digit string) {
	if c.justEvaluated && (digit >= "0" && digit <= "9") {
		c.Clear()
	}
	if digit == "." && strings.Contains(c.current, ".") {
		return // 避免多個小數點
	}
	c.current += digit
}

func (c *Calculator) currentValue() float64 {
	if c.current == "" {
		return 0
	}
	val, err := strconv.ParseFloat(c.current, 64)
	if err != nil {
		return 0
	}
	return val
}

func (c *Calculator) applyPending() {
	x := c.currentValue()
	if c.operator == 0 {
		c.accumulator = x
	} else {
		switch c.operator {
		case '+':
			c.accumulator += x
		case '-':
			c.accumulator -= x
		case '*':
			c.accumulator *= x
		case '/':
			if x == 0 {
				c.accumulator = 0 // 避免除零錯誤
			} else {
				c.accumulator /= x
			}
		}
	}
	c.current = ""
}

func (c *Calculator) SetOperator(op rune) {
	if c.current == "" && c.operator != 0 {
		c.operator = op
		return
	}
	c.applyPending()
	c.operator = op
	c.justEvaluated = false
}

func (c *Calculator) Evaluate() float64 {
	c.applyPending()
	c.operator = 0
	c.justEvaluated = true
	return c.accumulator
}

func (c *Calculator) Backspace() {
	if len(c.current) > 0 {
		c.current = c.current[:len(c.current)-1]
	}
}

func (c *Calculator) Display() string {
	if c.current != "" {
		return c.current
	}
	return fmt.Sprintf("%.12g", c.accumulator)
}

// 匯率轉換
func convertCurrency(amount float64, from, to string, rates *Rates) float64 {
	if from == to {
		return amount
	}
	fromRate := rates.Rate[from]
	toRate := rates.Rate[to]
	return amount * (toRate / fromRate)
}

// 獲取線上匯率
func fetchRatesFromAPI() (*Rates, error) {
	// 嘗試主要 API
	url := "https://api.fixer.io/latest?base=USD&symbols=" + strings.Join(currencies, ",")

	resp, err := http.Get(url)
	if err != nil || resp.StatusCode != 200 {
		log.Printf("主 API 失敗，嘗試備用 API: %v", err)
		// 備用 API
		url = "https://api.exchangerate-api.com/v4/latest/USD"
		resp, err = http.Get(url)
		if err != nil {
			return nil, fmt.Errorf("所有 API 都失敗: %v", err)
		}
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	log.Printf("API 響應: %s", string(body)[:min(200, len(body))])

	var apiResponse map[string]interface{}
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, err
	}

	rates := &Rates{
		Rate: make(map[string]float64),
		Live: true,
	}

	// 處理日期
	if date, ok := apiResponse["date"].(string); ok {
		rates.AsOf = "線上匯率 " + date
	} else if timeLastUpdated, ok := apiResponse["time_last_updated"].(string); ok {
		rates.AsOf = "線上匯率 " + timeLastUpdated
	} else {
		rates.AsOf = "線上匯率 " + time.Now().Format("2006-01-02")
	}

	// 處理匯率數據
	var ratesData map[string]interface{}
	if r, ok := apiResponse["rates"].(map[string]interface{}); ok {
		ratesData = r
	} else if r, ok := apiResponse["conversion_rates"].(map[string]interface{}); ok {
		ratesData = r
	} else {
		return nil, fmt.Errorf("找不到匯率數據字段")
	}

	// 解析匯率
	defaultRates := getDefaultRates()
	for _, cur := range currencies {
		if val, ok := ratesData[cur]; ok {
			switch v := val.(type) {
			case float64:
				rates.Rate[cur] = v
			case int:
				rates.Rate[cur] = float64(v)
			case string:
				if f, err := strconv.ParseFloat(v, 64); err == nil {
					rates.Rate[cur] = f
				} else {
					rates.Rate[cur] = defaultRates.Rate[cur]
					log.Printf("警告：解析 %s 匯率失敗，使用預設值", cur)
				}
			default:
				rates.Rate[cur] = defaultRates.Rate[cur]
				log.Printf("警告：未知的 %s 匯率數據類型，使用預設值", cur)
			}
		} else {
			rates.Rate[cur] = defaultRates.Rate[cur]
			log.Printf("警告：未找到 %s 匯率，使用預設值", cur)
		}
		log.Printf("成功解析 %s 匯率：%.4f", cur, rates.Rate[cur])
	}

	return rates, nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// 創建新應用程序
func NewApp() *App {
	app := &App{
		calc:  NewCalculator(),
		rates: getDefaultRates(),
	}

	app.app = gtk.NewApplication("com.example.go-mac-calc-fx", gio.ApplicationFlagsNone)
	app.app.ConnectActivate(app.onActivate)

	return app
}

// 應用程序啟動
func (a *App) onActivate() {
	a.window = gtk.NewApplicationWindow(a.app)
	a.window.SetTitle("Go 計算機（含匯率轉換・自動抓取）")
	a.window.SetDefaultSize(380, 500)

	// 創建筆記本（標籤頁）
	a.notebook = gtk.NewNotebook()
	a.window.SetChild(a.notebook)

	// 構建計算機頁面
	a.buildCalcTab()

	// 構建匯率頁面
	a.buildFxTab()

	// 更新匯率顯示
	a.updateFxDisplay()

	// 顯示窗口
	a.window.Present()

	// 啟動後自動獲取匯率
	go a.fetchRatesAsync()
}

// 構建計算機頁面
func (a *App) buildCalcTab() {
	calcBox := gtk.NewBox(gtk.OrientationVertical, 5)
	calcBox.SetMarginTop(10)
	calcBox.SetMarginBottom(10)
	calcBox.SetMarginStart(10)
	calcBox.SetMarginEnd(10)

	// 顯示器
	a.calcDisplay = gtk.NewEntry()
	a.calcDisplay.SetText("0")
	a.calcDisplay.SetEditable(false)
	a.calcDisplay.SetAlignment(1.0) // 右對齊
	calcBox.Append(a.calcDisplay)

	// 按鈕網格
	grid := gtk.NewGrid()
	grid.SetRowSpacing(5)
	grid.SetColumnSpacing(5)
	calcBox.Append(grid)

	// 按鈕佈局
	layout := [][]string{
		{"C", "⌫", "", "/"},
		{"7", "8", "9", "*"},
		{"4", "5", "6", "-"},
		{"1", "2", "3", "+"},
		{"0", ".", "=", ""},
	}

	for r, row := range layout {
		for c, text := range row {
			if text == "" {
				continue
			}

			btn := gtk.NewButtonWithLabel(text)

			// 捕獲按鈕文字
			buttonText := text
			btn.ConnectClicked(func() {
				a.onCalcPress(buttonText)
			})

			if r == 4 && text == "0" {
				grid.Attach(btn, c, r, 2, 1) // "0" 按鈕佔兩列
			} else if r == 4 && text == "." {
				grid.Attach(btn, c, r, 1, 1)
			} else {
				grid.Attach(btn, c, r, 1, 1)
			}
		}
	}

	// 添加到筆記本
	calcLabel := gtk.NewLabel("計算機")
	a.notebook.AppendPage(calcBox, calcLabel)
}

// 計算機按鈕處理
func (a *App) onCalcPress(label string) {
	log.Printf("按鈕被按下：%s", label)

	switch label {
	case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".":
		a.calc.InputDigit(label)
		a.updateCalcDisplay()
	case "+", "-", "*", "/":
		a.calc.SetOperator(rune(label[0]))
		a.updateCalcDisplay()
	case "=":
		a.calc.Evaluate()
		a.updateCalcDisplay()
	case "C":
		a.calc.Clear()
		a.updateCalcDisplay()
	case "⌫":
		a.calc.Backspace()
		a.updateCalcDisplay()
	}
}

// 更新計算機顯示
func (a *App) updateCalcDisplay() {
	display := a.calc.Display()
	log.Printf("更新顯示：%s", display)
	a.calcDisplay.SetText(display)
}

// 構建匯率頁面
func (a *App) buildFxTab() {
	fxBox := gtk.NewBox(gtk.OrientationVertical, 10)
	fxBox.SetMarginTop(10)
	fxBox.SetMarginBottom(10)
	fxBox.SetMarginStart(10)
	fxBox.SetMarginEnd(10)

	// 金額輸入
	amountBox := gtk.NewBox(gtk.OrientationHorizontal, 5)
	amountLabel := gtk.NewLabel("金額：")
	a.amountEntry = gtk.NewEntry()
	a.amountEntry.SetText("100")
	amountBox.Append(amountLabel)
	amountBox.Append(a.amountEntry)
	fxBox.Append(amountBox)

	// 貨幣選擇
	currencyBox := gtk.NewBox(gtk.OrientationHorizontal, 5)

	a.fromCombo = gtk.NewComboBoxText()
	a.toCombo = gtk.NewComboBoxText()
	for _, cur := range currencies {
		a.fromCombo.AppendText(cur)
		a.toCombo.AppendText(cur)
	}
	a.fromCombo.SetActive(0) // USD
	a.toCombo.SetActive(1)   // EUR

	fromLabel := gtk.NewLabel("從：")
	currencyBox.Append(fromLabel)
	currencyBox.Append(a.fromCombo)

	// 交換按鈕
	a.swapBtn = gtk.NewButtonWithLabel("⇄")
	a.swapBtn.ConnectClicked(func() {
		fromActive := a.fromCombo.Active()
		toActive := a.toCombo.Active()
		a.fromCombo.SetActive(toActive)
		a.toCombo.SetActive(fromActive)
	})
	currencyBox.Append(a.swapBtn)

	toLabel := gtk.NewLabel("到：")
	currencyBox.Append(toLabel)
	currencyBox.Append(a.toCombo)

	fxBox.Append(currencyBox)

	// 轉換按鈕
	convertBtn := gtk.NewButtonWithLabel("轉換")
	convertBtn.ConnectClicked(func() {
		a.onConvert()
	})
	fxBox.Append(convertBtn)

	// 結果顯示
	a.resultLabel = gtk.NewLabel("結果：")
	a.resultLabel.SetXAlign(0.0)
	fxBox.Append(a.resultLabel)

	// 匯率信息
	a.asOfLabel = gtk.NewLabel("")
	a.asOfLabel.SetXAlign(0.0)
	fxBox.Append(a.asOfLabel)

	// 狀態和刷新
	statusBox := gtk.NewBox(gtk.OrientationHorizontal, 5)
	a.statusLabel = gtk.NewLabel("狀態：準備中")
	statusBox.Append(a.statusLabel)

	a.refreshBtn = gtk.NewButtonWithLabel("刷新匯率")
	a.refreshBtn.ConnectClicked(func() {
		go a.fetchRatesAsync()
	})
	statusBox.Append(a.refreshBtn)

	fxBox.Append(statusBox)

	// 添加到筆記本
	fxLabel := gtk.NewLabel("匯率轉換")
	a.notebook.AppendPage(fxBox, fxLabel)
}

// 匯率轉換處理
func (a *App) onConvert() {
	amountText := a.amountEntry.Text()
	amount, err := strconv.ParseFloat(amountText, 64)
	if err != nil {
		a.resultLabel.SetText("錯誤：請輸入有效數字")
		return
	}

	fromIndex := a.fromCombo.Active()
	toIndex := a.toCombo.Active()

	if fromIndex < 0 || toIndex < 0 || fromIndex >= len(currencies) || toIndex >= len(currencies) {
		a.resultLabel.SetText("錯誤：請選擇有效貨幣")
		return
	}

	from := currencies[fromIndex]
	to := currencies[toIndex]

	result := convertCurrency(amount, from, to, a.rates)
	a.resultLabel.SetText(fmt.Sprintf("結果：%.4f %s", result, to))
}

// 更新匯率顯示
func (a *App) updateFxDisplay() {
	a.asOfLabel.SetText("匯率版本：" + a.rates.AsOf)
	if a.rates.Live {
		a.statusLabel.SetText("狀態：已更新（線上匯率）")
	} else {
		a.statusLabel.SetText("狀態：使用離線匯率")
	}
}

// 異步獲取匯率
func (a *App) fetchRatesAsync() {
	// 在主線程中更新狀態
	glib.IdleAdd(func() bool {
		a.statusLabel.SetText("狀態：正在更新匯率...")
		return false
	})

	// 獲取匯率
	newRates, err := fetchRatesFromAPI()

	// 在主線程中更新 UI
	glib.IdleAdd(func() bool {
		if err != nil {
			log.Printf("獲取匯率失敗：%v", err)
			a.statusLabel.SetText("狀態：更新失敗（使用離線匯率）。錯誤：" + err.Error())
		} else {
			a.rates = newRates
			a.asOfLabel.SetText("匯率版本：" + a.rates.AsOf + "（線上）")
			a.statusLabel.SetText("狀態：已更新。")
		}
		return false
	})
}

// 運行應用程序
func (a *App) Run() int {
	return a.app.Run(nil)
}

// 主函數
func main() {
	app := NewApp()
	app.Run()
}
