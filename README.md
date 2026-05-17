# stock-watch.el

[中文](README.zh-CN.md) | English

`stock-watch.el` is a lightweight Emacs stock watcher for China A-shares. It fetches real-time quotes from Sina Finance and displays them in an Emacs `tabulated-list-mode` buffer.

## Features

- Real-time A-share quote table inside Emacs
- No external Emacs package dependencies
- Supports 6-digit stock codes and auto-infers market prefixes:
  - `6` / `9` -> `sh`
  - `0` / `2` / `3` -> `sz`
  - `4` / `8` -> `bj`
- Fetches stock names from the quote API automatically
- Configurable refresh interval
- Manual refresh with `g`
- Stop and quit with `q`
- Highlighted rise/fall values
- Threshold alert with Emacs bell

## Requirements

- Emacs 27.1+
- Network access to Sina Finance:

```text
https://hq.sinajs.cn/list=...
```

## Installation

### From package archives

Once `stock-watch` is accepted by an Emacs package archive, install it with:

```text
M-x package-refresh-contents
M-x package-install RET stock-watch RET
```

For default `list-packages` visibility, submit the package to NonGNU ELPA. For
MELPA, users need MELPA in `package-archives` first.

### Manual install

Clone or download this repository, then add it to your Emacs `load-path`:

```elisp
(add-to-list 'load-path "/path/to/stock-watch")
(require 'stock-watch)
```

### MELPA recipe

The MELPA recipe for this repository should be:

```elisp
(stock-watch :fetcher github
             :repo "angelaresjun/stock-watch"
             :files ("stock-watch.el"))
```

## Quick Start

```elisp
(setq stock-watch-symbols
      '("600151" "600580" "601216" "000678"
        "002475" "002651" "002366"))

(setq stock-watch-refresh-interval 5)

(stock-watch)
```

You can also start it interactively:

```text
M-x stock-watch
```

## Configuration

### Watched stocks

Only 6-digit stock codes are required:

```elisp
(setq stock-watch-symbols '("600151" "000678" "002475"))
```

Prefixed codes also work:

```elisp
(setq stock-watch-symbols '("sh600151" "sz000678"))
```

### Refresh interval

```elisp
(setq stock-watch-refresh-interval 5)
```

### Alert threshold

The alert is triggered when the absolute percentage change is greater than or equal to the threshold:

```elisp
(setq stock-watch-alert-threshold-pct 3.0)
```

Disable alert bell:

```elisp
(setq stock-watch-enable-alert nil)
```

### Buffer name

```elisp
(setq stock-watch-buffer-name "*Stock Watch*")
```

## Key Bindings

| Key | Action |
| --- | --- |
| `g` | Refresh quotes now |
| `q` | Stop the refresh timer and quit the window |

## Data Source

The plugin uses Sina Finance's quote endpoint:

```text
https://hq.sinajs.cn/list=sh600151,sz000678
```

The response is GBK encoded. `stock-watch.el` decodes it automatically.

Sina may reject requests without proper headers, so the plugin sends:

```text
Referer: https://finance.sina.com.cn
User-Agent: Mozilla/5.0
```

## Display

The stock table includes:

```text
代码 | 名称 | 最新价 | 涨跌额 | 涨跌幅 | 成交量(手) | 成交额(万) | 更新时间
```

Rising values are shown in red, falling values in green, and threshold alerts are highlighted.

## Troubleshooting

### `No data`

Possible reasons:

- The stock code is invalid
- The request failed or timed out
- Sina Finance temporarily rejected the request
- The market is closed and the upstream endpoint is unavailable

### Garbled Chinese text

The Sina response is GBK encoded. This plugin decodes it internally. If you inspect the raw endpoint manually, use a tool that supports GBK conversion.


## License

`stock-watch.el` is free software licensed under the GNU General Public License,
version 3 or later. See [LICENSE](LICENSE) for details.
