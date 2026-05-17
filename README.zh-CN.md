# stock-watch.el

中文 | [English](README.md)

`stock-watch.el` 是一个轻量级 Emacs A 股行情查看插件。它从新浪财经获取实时行情，并在 Emacs 的 `tabulated-list-mode` 缓冲区中展示股票列表。

## 功能

- 在 Emacs 中实时查看 A 股行情表
- 不依赖额外 Emacs 包
- 支持 6 位股票代码，并自动推断市场前缀：
  - `6` / `9` -> `sh`
  - `0` / `2` / `3` -> `sz`
  - `4` / `8` -> `bj`
- 自动从行情接口获取股票名称
- 可配置刷新间隔
- 按 `g` 手动刷新
- 按 `k` 查看最近 10 个交易日 K 线图
- 在 K 线日期上按 `RET` 或 `m` 查看当天分时图
- 按 `q` 停止刷新并退出
- 高亮涨跌数值
- 支持涨跌幅阈值提醒

## 要求

- Emacs 27.1+
- 可以访问新浪财经行情接口：

```text
https://hq.sinajs.cn/list=...
```

## 安装

### 从包仓库安装

当 `stock-watch` 被 Emacs 包仓库收录后，可以这样安装：

```text
M-x package-refresh-contents
M-x package-install RET stock-watch RET
```

如果希望默认在 `list-packages` 中可见，应提交到 NonGNU ELPA。如果提交到 MELPA，用户需要先把 MELPA 加入 `package-archives`。

### 手动安装

克隆或下载本仓库，然后加入 Emacs 的 `load-path`：

```elisp
(add-to-list 'load-path "/path/to/stock-watch")
(require 'stock-watch)
```

### MELPA recipe

本仓库对应的 MELPA recipe：

```elisp
(stock-watch :fetcher github
             :repo "angelaresjun/stock-watch")
```

## 快速开始

```elisp
(setq stock-watch-symbols
      '("600151" "600580" "601216" "000678"
        "002475" "002651" "002366"))

(setq stock-watch-refresh-interval 5)

(stock-watch)
```

也可以交互式启动：

```text
M-x stock-watch
```

## 配置

### 自选股票

只需要填写 6 位股票代码：

```elisp
(setq stock-watch-symbols '("600151" "000678" "002475"))
```

也可以使用带市场前缀的代码：

```elisp
(setq stock-watch-symbols '("sh600151" "sz000678"))
```

### 刷新间隔

```elisp
(setq stock-watch-refresh-interval 5)
```

### 提醒阈值

当绝对涨跌幅大于或等于阈值时触发提醒：

```elisp
(setq stock-watch-alert-threshold-pct 3.0)
```

关闭提醒铃声：

```elisp
(setq stock-watch-enable-alert nil)
```

### K 线天数

```elisp
(setq stock-watch-kline-days 10)
```

### 分时图

分时图默认使用最近的 5 分钟记录生成：

```elisp
(setq stock-watch-intraday-interval 5)
(setq stock-watch-intraday-datalen 600)
```

### 缓冲区名称

```elisp
(setq stock-watch-buffer-name "*Stock Watch*")
(setq stock-watch-kline-buffer-name "*Stock Watch K-Line*")
(setq stock-watch-intraday-buffer-name "*Stock Watch Intraday*")
```

## 快捷键

| 按键 | 动作 |
| --- | --- |
| `g` | 立即刷新行情 |
| `k` | 查看当前行股票的 10 日 K 线图 |
| `q` | 停止刷新定时器并退出窗口 |

在 K 线图窗口中：

| 按键 | 动作 |
| --- | --- |
| `RET` / `m` | 查看当前日期的分时图 |
| `q` | 退出 K 线窗口 |

## 数据来源

插件使用新浪财经行情接口：

```text
https://hq.sinajs.cn/list=sh600151,sz000678
```

K 线图使用新浪财经日 K 线接口：

```text
https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=sh600151&scale=240&ma=no&datalen=10
```

分时图使用同一个接口的 5 分钟数据，并按所选日期过滤：

```text
https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=sh600151&scale=5&ma=no&datalen=600
```

接口响应为 GBK 编码，`stock-watch.el` 会自动解码。

新浪可能拒绝缺少合适请求头的请求，因此插件会发送：

```text
Referer: https://finance.sina.com.cn
User-Agent: Mozilla/5.0
```

## 显示内容

股票表包含：

```text
代码 | 名称 | 最新价 | 涨跌额 | 涨跌幅 | 成交量(手) | 成交额(万) | 更新时间
```

上涨显示为红色，下跌显示为绿色，达到提醒阈值的股票会额外高亮。

## 常见问题

### `No data`

可能原因：

- 股票代码无效
- 请求失败或超时
- 新浪财经临时拒绝请求
- 市场已收盘且上游接口不可用

### 中文乱码

新浪响应为 GBK 编码，插件会在内部自动解码。如果手动查看原始接口响应，请使用支持 GBK 转换的工具。

## 许可证

`stock-watch.el` 是自由软件，基于 GNU General Public License version 3 or later 发布。详见 [LICENSE](LICENSE)。
