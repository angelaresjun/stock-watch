;;; stock-watch-config.el --- Configuration for stock-watch -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; User options and faces for stock-watch.

;;; Code:

(defgroup stock-watch nil
  "Realtime A-share watcher."
  :prefix "stock-watch-"
  :group 'applications)

(defcustom stock-watch-symbols
  '("600151" "600580" "601216" "000678" "002475" "002651" "002366")
  "Stocks to watch.

Only 6-digit stock codes are required.  Market prefixes are inferred:
6/9 -> sh, 0/2/3 -> sz, 4/8 -> bj.  Prefixed codes such as sh600151
are also accepted."
  :type '(repeat string)
  :group 'stock-watch)

(defcustom stock-watch-refresh-interval 5
  "Refresh interval in seconds."
  :type 'integer
  :group 'stock-watch)

(defcustom stock-watch-alert-threshold-pct 3.0
  "Alert threshold by absolute percentage change."
  :type 'float
  :group 'stock-watch)

(defcustom stock-watch-buffer-name "*Stock Watch*"
  "Name of stock watch buffer."
  :type 'string
  :group 'stock-watch)

(defcustom stock-watch-enable-alert t
  "Whether to ring the Emacs bell when a stock newly crosses the alert threshold."
  :type 'boolean
  :group 'stock-watch)

(defcustom stock-watch-kline-days 15
  "Number of trading days to show in the K-line chart."
  :type 'integer
  :group 'stock-watch)

(defcustom stock-watch-ma-periods '(5 10 15 20 30 60)
  "Moving-average periods to draw in the K-line chart."
  :type '(repeat integer)
  :group 'stock-watch)

(defcustom stock-watch-ma-sample-count 60
  "Number of recent moving-average sample points to draw."
  :type 'integer
  :group 'stock-watch)

(defun stock-watch--ma-history-days ()
  "Return the daily K-line records needed for configured moving averages."
  (if stock-watch-ma-periods
      (+ stock-watch-ma-sample-count
         (apply #'max stock-watch-ma-periods)
         -1)
    0))

(defcustom stock-watch-kline-buffer-name "*Stock Watch K-Line*"
  "Name of stock watch K-line buffer."
  :type 'string
  :group 'stock-watch)

(defcustom stock-watch-intraday-buffer-name "*Stock Watch Intraday*"
  "Name of stock watch intraday chart buffer."
  :type 'string
  :group 'stock-watch)

(defcustom stock-watch-intraday-interval 5
  "Interval in minutes for intraday charts."
  :type 'integer
  :group 'stock-watch)

(defcustom stock-watch-intraday-datalen 600
  "Number of recent intraday records to fetch before filtering by day."
  :type 'integer
  :group 'stock-watch)

(defface stock-watch-up-face
  '((t :foreground "red" :weight bold))
  "Face for rising stocks."
  :group 'stock-watch)

(defface stock-watch-down-face
  '((t :foreground "green" :weight bold))
  "Face for falling stocks."
  :group 'stock-watch)

(defface stock-watch-alert-face
  '((t :foreground "red" :weight bold :inverse-video t))
  "Face for stocks that cross the alert threshold."
  :group 'stock-watch)

(defface stock-watch-error-face
  '((t :foreground "orange red" :weight bold))
  "Face for fetch or parse errors."
  :group 'stock-watch)

(provide 'stock-watch-config)

;;; stock-watch-config.el ends here
