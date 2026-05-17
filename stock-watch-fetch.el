;;; stock-watch-fetch.el --- Fetch stock data for stock-watch -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Sina Finance data fetching and parsing for stock-watch.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'url)
(require 'stock-watch-config)

(defconst stock-watch--sina-url "https://hq.sinajs.cn/list=%s")

(defconst stock-watch--sina-kline-url
  "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=%s&scale=%d&ma=no&datalen=%d")

(defconst stock-watch--headers
  '(("Referer" . "https://finance.sina.com.cn")
    ("User-Agent" . "Mozilla/5.0")))

(defun stock-watch--infer-market-prefix (code)
  "Infer Sina market prefix from 6-digit CODE."
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

(defun stock-watch--fetch-kline (code callback &optional datalen)
  "Fetch K-line data for CODE and call CALLBACK with candles or error.

When DATALEN is non-nil, fetch that many daily records.  Otherwise fetch
enough records for both the visible K-line chart and configured moving
averages."
  (let* ((url (format stock-watch--sina-kline-url
                       (stock-watch-normalize-code code)
                       240
                       (or datalen
                           (max stock-watch-kline-days
                                (stock-watch--ma-history-days)))))
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

(provide 'stock-watch-fetch)

;;; stock-watch-fetch.el ends here
