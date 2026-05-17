;;; stock-watch-core.el --- Core commands for stock-watch -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Core state, modes and interactive commands for stock-watch.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'stock-watch-config)
(require 'stock-watch-fetch)
(require 'stock-watch-display)
(require 'stock-watch-keys)

(defvar stock-watch--timer nil)
(defvar stock-watch--quotes nil)
(defvar stock-watch--indices nil)
(defvar stock-watch--alerted-codes nil)
(defvar stock-watch--last-update nil)

(defun stock-watch--quote-by-code (code)
  "Return the quote plist for CODE."
  (let ((normalized-code (stock-watch-normalize-code code)))
    (cl-find-if
     (lambda (quote)
       (equal (plist-get quote :code) normalized-code))
     stock-watch--quotes)))

(defun stock-watch--name-by-code (code)
  "Return the stock name for CODE, or nil if it is unavailable."
  (when-let* ((quote (stock-watch--quote-by-code code))
              (name (plist-get quote :name)))
    (unless (or (string-empty-p name)
                (equal name (plist-get quote :code)))
      name)))

(defun stock-watch--current-code ()
  "Return the stock code at point, or prompt for one."
  (or (tabulated-list-get-id)
      (stock-watch-normalize-code
       (read-string "Stock code: " (car stock-watch-symbols)))))

(defun stock-watch--kline-history-days ()
  "Return the number of daily records needed for K-line rendering."
  (max stock-watch-kline-days
       (stock-watch--ma-history-days)))

(defun stock-watch-show-intraday-at-point ()
  "Show intraday chart for the K-line date at point."
  (interactive)
  (let ((code (stock-watch--line-property 'stock-watch-code))
        (name (stock-watch--line-property 'stock-watch-name))
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
             (stock-watch--display-intraday code date bars name)
           (error
            (message "Failed to display intraday data for %s %s: %s"
                     code date (error-message-string err)))))))))

(defun stock-watch-show-kline (code)
  "Show a recent K-line chart for CODE."
  (interactive (list (stock-watch--current-code)))
  (let* ((normalized-code (stock-watch-normalize-code code))
         (name (stock-watch--name-by-code normalized-code))
         (history-days (stock-watch--kline-history-days)))
    (message "Fetching K-line data for %s (%d history days)..."
             normalized-code history-days)
    (stock-watch--fetch-kline
     normalized-code
     (lambda (candles error)
       (if error
           (message "Failed to fetch K-line data for %s: %s"
                    normalized-code error)
          (when (< (length candles) history-days)
            (message "Only fetched %d K-line records for %s; %d requested"
                     (length candles) normalized-code history-days))
          (condition-case err
              (stock-watch--display-kline normalized-code candles name)
            (error
             (message "Failed to display K-line data for %s: %s"
                      normalized-code (error-message-string err)))))))
     history-days))

(defun stock-watch--goto-entry (entry-id column)
  "Move point to ENTRY-ID and restore COLUMN when possible."
  (let ((position (point-min))
        found)
    (while (and (not found) (< position (point-max)))
      (when (equal (get-text-property position 'tabulated-list-id) entry-id)
        (setq found position))
      (let ((next-position
             (next-single-property-change
              position 'tabulated-list-id nil (point-max))))
        (setq position
              (if (= next-position position)
                  (1+ position)
                next-position))))
    (when found
      (goto-char found)
      (beginning-of-line)
      (move-to-column column))))

(defun stock-watch--refresh-buffer ()
  "Refresh the stock watch buffer from `stock-watch--quotes'."
  (when-let* ((buffer (get-buffer stock-watch-buffer-name)))
    (with-current-buffer buffer
      (let ((current-entry (tabulated-list-get-id))
            (current-column (current-column)))
        (setq tabulated-list-entries
              (mapcar #'stock-watch--entry stock-watch--quotes))
        (tabulated-list-print t)
        (let ((inhibit-read-only t))
          (goto-char (point-min))
          (insert
           (format "Indices: %s\nLast update: %s | Interval: %ss | Alert: ±%.2f%% | g refresh | C-c C-k K-line | q quit\n\n"
                   (stock-watch--index-summary stock-watch--indices)
                   (or stock-watch--last-update "-")
                   stock-watch-refresh-interval
                   stock-watch-alert-threshold-pct)))
        (when current-entry
          (stock-watch--goto-entry current-entry current-column))))))

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
  (stock-watch--fetch-market
   (lambda (quotes indices)
      (setq stock-watch--quotes quotes
            stock-watch--indices indices
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
  (stock-watch-keys-setup-main))

(provide 'stock-watch-core)

;;; stock-watch-core.el ends here
