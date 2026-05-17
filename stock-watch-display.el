;;; stock-watch-display.el --- Display helpers for stock-watch -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Table, K-line and intraday rendering for stock-watch.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'stock-watch-config)
(require 'stock-watch-fetch)
(require 'stock-watch-keys)

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

(defun stock-watch--label (code &optional name)
  "Return display label for stock CODE and optional NAME."
  (if (and name (not (string-empty-p name)))
      (format "%s (%s)" name (stock-watch-normalize-code code))
    (stock-watch-normalize-code code)))

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

(defun stock-watch--volume-height (volume maximum rows)
  "Scale VOLUME against MAXIMUM to a bar height under ROWS."
  (if (or (<= maximum 0) (<= volume 0))
      0
    (max 1 (ceiling (* (/ volume (float maximum)) rows)))))

(defun stock-watch--render-volume-bars (candles)
  "Render volume bars for K-line CANDLES."
  (let* ((rows 4)
         (volumes (mapcar (lambda (candle) (plist-get candle :volume)) candles))
         (maximum (apply #'max volumes)))
    (insert "  Volume │ ")
    (dotimes (row rows)
      (when (> row 0)
        (insert "         │ "))
      (let ((threshold (- rows row)))
        (dolist (candle candles)
          (let* ((open (plist-get candle :open))
                 (close (plist-get candle :close))
                 (volume (plist-get candle :volume))
                 (height (stock-watch--volume-height volume maximum rows))
                 (face (if (>= close open)
                           'stock-watch-up-face
                         'stock-watch-down-face)))
            (insert "  " (propertize (if (>= height threshold) "█" " ")
                                      'face face)
                    "  "))))
      (insert "\n"))
    (insert "         └")
    (dotimes (_ (length candles))
      (insert "─────"))
    (insert "\n          ")
    (dolist (candle candles)
      (insert (format "%5s" (substring (plist-get candle :day) 5))))
    (insert (format "\n          Max volume: %s\n"
                    (stock-watch--format-number maximum)))))

(defun stock-watch--render-kline-chart (code candles &optional name)
  "Render a K-line chart for CODE from CANDLES.
Use NAME in the chart title if it is non-nil."
  (let* ((rows 16)
         (highs (mapcar (lambda (candle) (plist-get candle :high)) candles))
         (lows (mapcar (lambda (candle) (plist-get candle :low)) candles))
         (maximum (apply #'max highs))
         (minimum (apply #'min lows))
         (last-close (plist-get (car (last candles)) :close)))
    (insert (format "%s  %d-day K-line  Last close: %.2f\n\n"
                    (stock-watch--label code name) (length candles) last-close))
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
    (stock-watch--render-volume-bars candles)
    (insert "\n")
    (insert "Move point to a date row and press C-c C-m, RET, or m for intraday chart.\n\n")
    (insert "Date        Open    High     Low   Close        Volume  Volume Bar\n")
    (dolist (candle candles)
      (let ((day (plist-get candle :day)))
        (insert
         (propertize
          (format "%s  %6.2f  %6.2f  %6.2f  %6.2f  %12s  %s\n"
                  day
                  (plist-get candle :open)
                  (plist-get candle :high)
                  (plist-get candle :low)
                  (plist-get candle :close)
                  (stock-watch--format-number
                   (plist-get candle :volume))
                  (make-string
                   (stock-watch--volume-height
                    (plist-get candle :volume)
                    (apply #'max
                           (mapcar (lambda (item)
                                     (plist-get item :volume))
                                   candles))
                    12)
                   ?█))
          'stock-watch-code code
          'stock-watch-name name
          'stock-watch-date day
          'mouse-face 'highlight
          'help-echo "C-c C-m, RET, or m: show intraday chart"))))))

(defun stock-watch--line-property (property)
  "Return text PROPERTY from the current line."
  (or (get-text-property (point) property)
      (save-excursion
        (beginning-of-line)
        (get-text-property (point) property))))

(defun stock-watch--render-intraday-chart (code date bars &optional name)
  "Render an intraday line chart for CODE on DATE from BARS.
Use NAME in the chart title if it is non-nil."
  (let* ((rows 14)
         (closes (mapcar (lambda (bar) (plist-get bar :close)) bars))
         (maximum (apply #'max closes))
         (minimum (apply #'min closes))
         (last-close (car (last closes))))
    (insert (format "%s  %s  %d-minute intraday  Last: %.2f\n\n"
                    (stock-watch--label code name)
                    date stock-watch-intraday-interval last-close))
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

(defun stock-watch--display-kline (code candles &optional name)
  "Display K-line CANDLES for CODE.
Use NAME in the chart title if it is non-nil."
  (let ((buffer (get-buffer-create stock-watch-kline-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (setq buffer-read-only nil)
        (erase-buffer)
        (if candles
            (stock-watch--render-kline-chart code candles name)
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

(defun stock-watch--display-intraday (code date bars &optional name)
  "Display intraday BARS for CODE on DATE.
Use NAME in the chart title if it is non-nil."
  (let ((buffer (get-buffer-create stock-watch-intraday-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (setq buffer-read-only nil)
        (erase-buffer)
        (stock-watch--render-intraday-chart code date bars name)
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

(provide 'stock-watch-display)

;;; stock-watch-display.el ends here
