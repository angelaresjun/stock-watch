;;; stock-watch.el --- Real-time A-share watcher in Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua

;; Author: Joshua
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

(defconst stock-watch--headers
  '(("Referer" . "https://finance.sina.com.cn")
    ("User-Agent" . "Mozilla/5.0")))

(defvar stock-watch--timer nil)
(defvar stock-watch--quotes nil)
(defvar stock-watch--alerted-codes nil)
(defvar stock-watch--last-update nil)

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
       (unwind-protect
           (if-let* ((error (plist-get status :error)))
               (funcall callback (stock-watch--error-quotes (format "%s" error)))
             (goto-char (point-min))
             (if (not (re-search-forward "\r?\n\r?\n" nil t))
                 (funcall callback (stock-watch--error-quotes "Malformed HTTP response"))
               (let* ((raw-body (buffer-substring-no-properties (point) (point-max)))
                      (body (decode-coding-string raw-body 'gbk)))
                 (funcall callback (stock-watch--parse-response body)))))
         (kill-buffer (current-buffer))))
     nil
     t)))

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
            (format "Last update: %s | Interval: %ss | Alert: ±%.2f%% | g refresh | q quit"
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
  (local-set-key (kbd "q") #'stock-watch-quit))

;;;###autoload
(defalias 'stock-watch #'stock-watch-start)

(provide 'stock-watch)

;;; stock-watch.el ends here
