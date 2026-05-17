;;; stock-watch.el --- Real-time A-share watcher -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua

;; Author: Joshua
;; Assisted-by: GitHub Copilot CLI:gpt-5.5
;; Maintainer: Joshua
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools
;; URL: https://github.com/angelaresjun/stock-watch
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A lightweight Emacs stock watcher for A-shares using Sina Finance.
;;
;; Usage:
;;
;;   (setq stock-watch-symbols '("600151" "600580" "601216" "000678"))
;;   M-x stock-watch

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'tabulated-list)
(require 'url)

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

(defcustom stock-watch-kline-days 10
  "Number of trading days to show in the K-line chart."
  :type 'integer
  :group 'stock-watch)

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

(defconst stock-watch--sina-url "https://hq.sinajs.cn/list=%s")

(defconst stock-watch--sina-kline-url
  "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=%s&scale=%d&ma=no&datalen=%d")

(defconst stock-watch--headers
  '(("Referer" . "https://finance.sina.com.cn")
    ("User-Agent" . "Mozilla/5.0")))

(defvar stock-watch--timer nil)
(defvar stock-watch--quotes nil)
(defvar stock-watch--alerted-codes nil)
(defvar stock-watch--last-update nil)

(defvar stock-watch-kline-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'stock-watch-show-intraday-at-point)
    (define-key map (kbd "m") #'stock-watch-show-intraday-at-point)
    map)
  "Keymap for `stock-watch-kline-mode'.")

(define-derived-mode stock-watch-kline-mode special-mode "Stock-Watch-KLine"
  "Major mode for stock K-line charts.

Move point to a date row and press \\<stock-watch-kline-mode-map>\\[stock-watch-show-intraday-at-point]
to show the intraday chart for that day.")

(defun stock-watch--infer-market-prefix (code)
  "Infer Sina market prefix from 6-digit stock CODE."
  (cond
   ((string-match-p "\\`[69]" code) "sh")
   ((string-match-p "\\`[023]" code) "sz")
   ((string-match-p "\\`[48]" code) "bj")
   (t (user-error "Cannot infer market prefix from stock code: %s" code))))

(defun stock-watch-normalize-code (code)
  "Normalize stock CODE to Sina format, such as sh600151."
  (let* ((raw (downcase (string-trim (format "%s" code))))
         (prefix nil)
         (bare raw))
    (when (string-match "\\`\\(sh\\|sz\\|bj\\)\\([0-9]+\\)\\'" raw)
      (setq prefix (match-string 1 raw)
            bare (match-string 2 raw)))
    (unless (and (string-match-p "\\`[0-9]\\{6\\}\\'" bare))
      (user-error "Stock code must be 6 digits or prefixed with sh/sz/bj: %s" code))
    (concat (or prefix (stock-watch--infer-market-prefix bare)) bare)))

(defun stock-watch--format-number (number)
  "Format integer NUMBER with comma separators."
  (let* ((integer (truncate number))
         (sign (if (< integer 0) "-" ""))
         (digits (number-to-string (abs integer)))
         chunks)
    (while (> (length digits) 3)
      (push (substring digits (- (length digits) 3)) chunks)
      (setq digits (substring digits 0 (- (length digits) 3))))
    (concat sign (string-join (cons digits chunks) ","))))

(defun stock-watch--quote-face (pct)
  "Return face for PCT."
  (cond
   ((>= (abs pct) stock-watch-alert-threshold-pct) 'stock-watch-alert-face)
   ((> pct 0) 'stock-watch-up-face)
   ((< pct 0) 'stock-watch-down-face)
   (t 'default)))

(defun stock-watch--signed-number (number &optional percent)
  "Format NUMBER with sign.  Add percent sign if PERCENT is non-nil."
  (format "%s%.2f%s" (if (> number 0) "+" "") number (if percent "%" "")))

(defun stock-watch--current-code ()
  "Return the stock code at point, or prompt for one."
  (or (tabulated-list-get-id)
      (stock-watch-normalize-code
       (read-string "Stock code: " (car stock-watch-symbols)))))

(defun stock-watch--parse-line (line)
  "Parse one Sina response LINE and return a plist quote."
  (when (string-match "\\`var hq_str_\\([a-z][a-z][0-9]+\\)=\"\\(.*\\)\";?\\'" line)
    (let* ((code (match-string 1 line))
           (content (match-string 2 line))
           (parts (split-string content ",")))
      (when (>= (length parts) 10)
        (let* ((name (nth 0 parts))
               (prev-close (string-to-number (nth 2 parts)))
               (price (string-to-number (nth 3 parts)))
               (change (- price prev-close))
               (pct (if (zerop prev-close) 0.0 (* (/ change prev-close) 100.0)))
               (volume-shares (string-to-number (nth 8 parts)))
               (amount (string-to-number (nth 9 parts))))
          (when (and (not (string-empty-p name))
                     (> prev-close 0))
            (list :code code
                  :name name
                  :price price
                  :change change
                  :pct-change pct
                  :volume (/ volume-shares 100)
                  :amount amount
                  :time (format-time-string "%H:%M:%S"))))))))

(defun stock-watch--parse-response (body)
  "Parse Sina response BODY into quote plists."
  (let ((quotes-by-code (make-hash-table :test #'equal)))
    (dolist (line (split-string body "\n" t))
      (when-let* ((quote (stock-watch--parse-line (string-trim line))))
        (puthash (plist-get quote :code) quote quotes-by-code)))
    (mapcar
     (lambda (symbol)
       (let* ((code (stock-watch-normalize-code symbol))
              (quote (gethash code quotes-by-code)))
         (or quote
             (list :code code
                   :name code
                   :price 0.0
                   :change 0.0
                   :pct-change 0.0
                   :volume 0
                   :amount 0.0
                   :time (format-time-string "%H:%M:%S")
                   :error "No data"))))
     stock-watch-symbols)))

(defun stock-watch--fetch (callback)
  "Fetch quotes asynchronously and call CALLBACK with parsed quotes."
  (let* ((codes (mapconcat #'stock-watch-normalize-code stock-watch-symbols ","))
         (url (format stock-watch--sina-url codes))
         (url-request-extra-headers stock-watch--headers))
    (url-retrieve
     url
     (lambda (status)
       (let ((response-buffer (current-buffer)))
         (unwind-protect
             (if-let* ((error (plist-get status :error)))
                 (funcall callback (stock-watch--error-quotes (format "%s" error)))
               (goto-char (point-min))
               (if (not (re-search-forward "\r?\n\r?\n" nil t))
                   (funcall callback (stock-watch--error-quotes "Malformed HTTP response"))
                 (let* ((raw-body (buffer-substring-no-properties (point) (point-max)))
                        (body (decode-coding-string raw-body 'gbk)))
                   (funcall callback (stock-watch--parse-response body)))))
           (when (buffer-live-p response-buffer)
             (kill-buffer response-buffer)))))
      nil
      t)))

(defun stock-watch--alist-number (key alist)
  "Return numeric value for KEY in ALIST."
  (string-to-number (or (alist-get key alist nil nil #'eq) "0")))

(defun stock-watch--parse-kline-response (body)
  "Parse Sina K-line response BODY into candle plists."
  (let ((json-array-type 'list)
        (json-object-type 'alist)
        (json-key-type 'symbol))
    (mapcar
     (lambda (item)
       (list :day (alist-get 'day item)
             :open (stock-watch--alist-number 'open item)
             :high (stock-watch--alist-number 'high item)
             :low (stock-watch--alist-number 'low item)
             :close (stock-watch--alist-number 'close item)
             :volume (stock-watch--alist-number 'volume item)))
     (json-read-from-string body))))

(defun stock-watch--fetch-kline (code callback)
  "Fetch K-line data for CODE and call CALLBACK with candles or error."
  (let* ((url (format stock-watch--sina-kline-url
                      (stock-watch-normalize-code code)
                      240
                      stock-watch-kline-days))
         (url-request-extra-headers stock-watch--headers))
    (url-retrieve
     url
     (lambda (status)
       (let ((response-buffer (current-buffer)))
         (unwind-protect
             (if-let* ((error (plist-get status :error)))
                 (funcall callback nil (format "%s" error))
               (goto-char (point-min))
               (if (not (re-search-forward "\r?\n\r?\n" nil t))
                   (funcall callback nil "Malformed HTTP response")
                 (let* ((body (string-trim
                               (buffer-substring-no-properties
                                (point) (point-max)))))
                   (condition-case err
                       (let ((candles (stock-watch--parse-kline-response body)))
                         (if candles
                             (funcall callback candles nil)
                           (funcall callback nil "No K-line data")))
                     (error
                      (funcall callback nil (error-message-string err)))))))
           (when (buffer-live-p response-buffer)
             (kill-buffer response-buffer)))))
     nil
     t)))

(defun stock-watch--fetch-intraday (code date callback)
  "Fetch intraday data for CODE on DATE and call CALLBACK with bars or error."
  (let* ((url (format stock-watch--sina-kline-url
                      (stock-watch-normalize-code code)
                      stock-watch-intraday-interval
                      stock-watch-intraday-datalen))
         (url-request-extra-headers stock-watch--headers))
    (url-retrieve
     url
     (lambda (status)
       (let ((response-buffer (current-buffer)))
         (unwind-protect
             (if-let* ((error (plist-get status :error)))
                 (funcall callback nil (format "%s" error))
               (goto-char (point-min))
               (if (not (re-search-forward "\r?\n\r?\n" nil t))
                   (funcall callback nil "Malformed HTTP response")
                 (let* ((body (string-trim
                               (buffer-substring-no-properties
                                (point) (point-max)))))
                   (condition-case err
                       (let ((bars
                              (cl-remove-if-not
                               (lambda (bar)
                                 (stock-watch--intraday-bar-p bar date))
                               (stock-watch--parse-kline-response body))))
                         (if bars
                             (funcall callback bars nil)
                           (funcall callback nil
                                    (format "No intraday data for %s" date))))
                     (error
                      (funcall callback nil (error-message-string err)))))))
           (when (buffer-live-p response-buffer)
             (kill-buffer response-buffer)))))
     nil
     t)))

(defun stock-watch--intraday-bar-p (bar date)
  "Return non-nil if BAR is an intraday record for DATE."
  (let ((day (plist-get bar :day)))
    (and (stringp day)
         (>= (length day) 16)
         (string-prefix-p date day))))

(defun stock-watch--intraday-time (bar)
  "Return HH:MM from intraday BAR."
  (let ((day (plist-get bar :day)))
    (if (and (stringp day) (>= (length day) 16))
        (substring day 11 16)
      "--:--")))

(defun stock-watch--scale-price (price minimum maximum rows)
  "Scale PRICE between MINIMUM and MAXIMUM to a row index under ROWS."
  (if (= minimum maximum)
      (/ rows 2)
    (round (* (/ (- maximum price) (- maximum minimum))
              (1- rows)))))

(defun stock-watch--render-candle-row (row candle minimum maximum rows)
  "Render CANDLE at chart ROW using MINIMUM, MAXIMUM and ROWS."
  (let* ((open (plist-get candle :open))
         (close (plist-get candle :close))
         (high (plist-get candle :high))
         (low (plist-get candle :low))
         (high-row (stock-watch--scale-price high minimum maximum rows))
         (low-row (stock-watch--scale-price low minimum maximum rows))
         (open-row (stock-watch--scale-price open minimum maximum rows))
         (close-row (stock-watch--scale-price close minimum maximum rows))
         (body-top (min open-row close-row))
         (body-bottom (max open-row close-row))
         (face (if (>= close open) 'stock-watch-up-face 'stock-watch-down-face)))
    (cond
     ((and (<= body-top row) (<= row body-bottom))
      (propertize "█" 'face face))
     ((and (<= high-row row) (<= row low-row))
      (propertize "│" 'face face))
     (t " "))))

(defun stock-watch--render-kline-chart (code candles)
  "Render a K-line chart for CODE from CANDLES."
  (let* ((rows 16)
         (highs (mapcar (lambda (candle) (plist-get candle :high)) candles))
         (lows (mapcar (lambda (candle) (plist-get candle :low)) candles))
         (maximum (apply #'max highs))
         (minimum (apply #'min lows))
         (last-close (plist-get (car (last candles)) :close)))
    (insert (format "%s  %d-day K-line  Last close: %.2f\n\n"
                    code (length candles) last-close))
    (dotimes (row rows)
      (let ((price (- maximum (* (/ (- maximum minimum) (float (1- rows)))
                                 row))))
        (insert (format "%8.2f │ " price))
        (dolist (candle candles)
          (insert "  " (stock-watch--render-candle-row
                        row candle minimum maximum rows)
                  "  "))
        (insert "\n")))
    (insert "         └")
    (dotimes (_ (length candles))
      (insert "─────"))
    (insert "\n          ")
    (dolist (candle candles)
      (insert (format "%5s" (substring (plist-get candle :day) 5))))
    (insert "\n\n")
    (insert "Move point to a date row and press RET or m for intraday chart.\n\n")
    (insert "Date        Open    High     Low   Close        Volume\n")
    (dolist (candle candles)
      (let ((day (plist-get candle :day)))
        (insert
         (propertize
          (format "%s  %6.2f  %6.2f  %6.2f  %6.2f  %12s\n"
                  day
                  (plist-get candle :open)
                  (plist-get candle :high)
                  (plist-get candle :low)
                  (plist-get candle :close)
                  (stock-watch--format-number
                   (plist-get candle :volume)))
          'stock-watch-code code
          'stock-watch-date day
          'mouse-face 'highlight
          'help-echo "RET or m: show intraday chart"))))))

(defun stock-watch--line-property (property)
  "Return text PROPERTY from the current line."
  (or (get-text-property (point) property)
      (save-excursion
        (beginning-of-line)
        (get-text-property (point) property))))

(defun stock-watch--render-intraday-chart (code date bars)
  "Render an intraday line chart for CODE on DATE from BARS."
  (let* ((rows 14)
         (closes (mapcar (lambda (bar) (plist-get bar :close)) bars))
         (maximum (apply #'max closes))
         (minimum (apply #'min closes))
         (last-close (car (last closes))))
    (insert (format "%s  %s  %d-minute intraday  Last: %.2f\n\n"
                    code date stock-watch-intraday-interval last-close))
    (dotimes (row rows)
      (let ((price (- maximum (* (/ (- maximum minimum) (float (1- rows)))
                                 row))))
        (insert (format "%8.2f │ " price))
        (dolist (bar bars)
          (let* ((close (plist-get bar :close))
                 (bar-row (stock-watch--scale-price close minimum maximum rows)))
            (insert (propertize (if (= row bar-row) "●" " ")
                                'face (if (>= close (plist-get bar :open))
                                          'stock-watch-up-face
                                        'stock-watch-down-face)))))
        (insert "\n")))
    (insert "         └")
    (dotimes (_ (length bars))
      (insert "─"))
    (insert "\n          ")
    (let* ((first-time (stock-watch--intraday-time (car bars)))
           (last-time (stock-watch--intraday-time (car (last bars))))
           (space-count (max 1 (- (length bars) (length first-time) (length last-time)))))
      (insert first-time (make-string space-count ?\s) last-time))
    (insert "\n\n")
    (insert "Time   Open    High     Low   Close       Volume\n")
    (dolist (bar bars)
      (insert (format "%s  %6.2f  %6.2f  %6.2f  %6.2f  %11s\n"
                      (stock-watch--intraday-time bar)
                      (plist-get bar :open)
                      (plist-get bar :high)
                      (plist-get bar :low)
                      (plist-get bar :close)
                      (stock-watch--format-number
                       (plist-get bar :volume)))))))

(defun stock-watch--display-intraday (code date bars)
  "Display intraday BARS for CODE on DATE."
  (let ((buffer (get-buffer-create stock-watch-intraday-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (setq buffer-read-only nil)
        (erase-buffer)
        (stock-watch--render-intraday-chart code date bars)
        (goto-char (point-min))
        (special-mode)))
    (if-let* ((window (display-buffer
                       buffer
                       '((display-buffer-reuse-window
                          display-buffer-pop-up-window)))))
        (select-window window)
      (pop-to-buffer buffer))
    (message "Displayed intraday chart for %s %s in %s"
             code date stock-watch-intraday-buffer-name)))

(defun stock-watch-show-intraday-at-point ()
  "Show intraday chart for the K-line date at point."
  (interactive)
  (let ((code (stock-watch--line-property 'stock-watch-code))
        (date (stock-watch--line-property 'stock-watch-date)))
    (unless (and code date)
      (user-error "Move point to a date row first"))
    (message "Fetching intraday data for %s %s..." code date)
    (stock-watch--fetch-intraday
     code
     date
     (lambda (bars error)
       (if error
           (message "Failed to fetch intraday data for %s %s: %s"
                    code date error)
         (condition-case err
             (stock-watch--display-intraday code date bars)
           (error
            (message "Failed to display intraday data for %s %s: %s"
                     code date (error-message-string err)))))))))

(defun stock-watch--display-kline (code candles)
  "Display K-line CANDLES for CODE."
  (let ((buffer (get-buffer-create stock-watch-kline-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (setq buffer-read-only nil)
        (erase-buffer)
        (if candles
            (stock-watch--render-kline-chart code candles)
          (insert (format "No K-line data for %s\n" code)))
        (goto-char (point-min))
        (stock-watch-kline-mode)))
    (if-let* ((window (display-buffer
                       buffer
                       '((display-buffer-reuse-window
                          display-buffer-pop-up-window)))))
        (select-window window)
      (pop-to-buffer buffer))
    (message "Displayed K-line chart for %s in %s"
             code stock-watch-kline-buffer-name)))

(defun stock-watch-show-kline (code)
  "Show a recent K-line chart for CODE."
  (interactive (list (stock-watch--current-code)))
  (let ((normalized-code (stock-watch-normalize-code code)))
    (message "Fetching K-line data for %s..." normalized-code)
    (stock-watch--fetch-kline
     normalized-code
     (lambda (candles error)
       (if error
           (message "Failed to fetch K-line data for %s: %s"
                    normalized-code error)
         (condition-case err
             (stock-watch--display-kline normalized-code candles)
           (error
            (message "Failed to display K-line data for %s: %s"
                     normalized-code (error-message-string err)))))))))

(defun stock-watch--error-quotes (error)
  "Build placeholder quotes with ERROR."
  (mapcar
   (lambda (symbol)
     (let ((code (stock-watch-normalize-code symbol)))
       (list :code code
             :name code
             :price 0.0
             :change 0.0
             :pct-change 0.0
             :volume 0
             :amount 0.0
             :time (format-time-string "%H:%M:%S")
             :error error)))
   stock-watch-symbols))

(defun stock-watch--entry (quote)
  "Convert QUOTE plist to a `tabulated-list-mode' entry."
  (let* ((code (plist-get quote :code))
         (name (plist-get quote :name))
         (price (plist-get quote :price))
         (change (plist-get quote :change))
         (pct (plist-get quote :pct-change))
         (volume (plist-get quote :volume))
         (amount (plist-get quote :amount))
         (time (plist-get quote :time))
         (error (plist-get quote :error))
         (face (if error 'stock-watch-error-face (stock-watch--quote-face pct))))
    (list code
          (vector
           code
           name
           (if error
               (propertize error 'face 'stock-watch-error-face)
             (propertize (format "%.2f" price) 'face face))
           (if error
               "-"
             (propertize (stock-watch--signed-number change) 'face face))
           (if error
               "-"
             (propertize (stock-watch--signed-number pct t) 'face face))
           (stock-watch--format-number volume)
           (format "%.1f" (/ amount 10000.0))
           time))))

(defun stock-watch--refresh-buffer ()
  "Refresh the stock watch buffer from `stock-watch--quotes'."
  (when-let* ((buffer (get-buffer stock-watch-buffer-name)))
    (with-current-buffer buffer
      (setq tabulated-list-entries
            (mapcar #'stock-watch--entry stock-watch--quotes))
      (tabulated-list-print t)
      (setq header-line-format
            (format "Last update: %s | Interval: %ss | Alert: ±%.2f%% | g refresh | k K-line | q quit"
                    (or stock-watch--last-update "-")
                    stock-watch-refresh-interval
                    stock-watch-alert-threshold-pct)))))

(defun stock-watch--process-alerts (quotes)
  "Ring bell for newly alerted QUOTES."
  (when stock-watch-enable-alert
    (let* ((triggered
            (cl-remove-if-not
             (lambda (quote)
               (and (not (plist-get quote :error))
                    (>= (abs (plist-get quote :pct-change))
                        stock-watch-alert-threshold-pct)))
             quotes))
           (codes (mapcar (lambda (quote) (plist-get quote :code)) triggered))
           (new-codes (cl-set-difference codes stock-watch--alerted-codes :test #'equal)))
      (when new-codes
        (ding)
        (message "Stock alert: %s" (string-join new-codes ", ")))
      (setq stock-watch--alerted-codes codes))))

(defun stock-watch-refresh ()
  "Refresh stock quotes now."
  (interactive)
  (stock-watch--fetch
   (lambda (quotes)
     (setq stock-watch--quotes quotes
           stock-watch--last-update (format-time-string "%Y-%m-%d %H:%M:%S"))
     (stock-watch--process-alerts quotes)
     (stock-watch--refresh-buffer))))

(defun stock-watch-start ()
  "Start stock watcher and open `stock-watch-buffer-name'."
  (interactive)
  (let ((buffer (get-buffer-create stock-watch-buffer-name)))
    (with-current-buffer buffer
      (stock-watch-mode))
    (pop-to-buffer buffer))
  (stock-watch-refresh)
  (stock-watch-stop-timer)
  (setq stock-watch--timer
        (run-at-time stock-watch-refresh-interval
                     stock-watch-refresh-interval
                     #'stock-watch-refresh)))

(defun stock-watch-stop-timer ()
  "Stop the background refresh timer."
  (when (timerp stock-watch--timer)
    (cancel-timer stock-watch--timer)
    (setq stock-watch--timer nil)))

(defun stock-watch-stop ()
  "Stop stock watcher timer."
  (interactive)
  (stock-watch-stop-timer)
  (message "Stock watcher stopped"))

(defun stock-watch-quit ()
  "Stop stock watcher and kill current buffer."
  (interactive)
  (stock-watch-stop)
  (quit-window t))

;;;###autoload
(define-derived-mode stock-watch-mode tabulated-list-mode "Stock-Watch"
  "Major mode for watching A-share quotes."
  (setq tabulated-list-format
        [("代码" 10 t)
         ("名称" 12 t)
         ("最新价" 10 t)
         ("涨跌额" 10 t)
         ("涨跌幅" 10 t)
         ("成交量(手)" 14 t)
         ("成交额(万)" 14 t)
         ("更新时间" 10 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header)
  (local-set-key (kbd "g") #'stock-watch-refresh)
  (local-set-key (kbd "k") #'stock-watch-show-kline)
  (local-set-key (kbd "q") #'stock-watch-quit))

;;;###autoload
(defalias 'stock-watch #'stock-watch-start)

(provide 'stock-watch)

;;; stock-watch.el ends here
