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

(defun stock-watch--insert-title (title)
  "Insert a chart TITLE with a simple underline."
  (insert title "\n"
          (make-string (string-width title) ?=)
          "\n\n"))

(defun stock-watch--insert-section-title (title)
  "Insert a section TITLE."
  (insert title "\n"
          (make-string (string-width title) ?-)
          "\n"))

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

(defun stock-watch--index-summary (indices)
  "Return a compact propertized summary for INDICES."
  (if indices
      (mapconcat
       (lambda (index)
         (let* ((name (plist-get index :name))
                (price (plist-get index :price))
                (change (plist-get index :change))
                (pct (plist-get index :pct-change))
                (error (plist-get index :error))
                (face (if error
                          'stock-watch-error-face
                        (stock-watch--quote-face pct))))
           (if error
               (format "%s: %s" name error)
             (format "%s %.2f %s"
                     name
                     price
                     (propertize
                      (format "%s %.2f%%"
                              (stock-watch--signed-number change)
                              pct)
                      'face face)))))
       indices
       " | ")
    "No indices"))

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
    (stock-watch--insert-section-title "Volume")
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

(defun stock-watch--last-n (items n)
  "Return the last N ITEMS."
  (let ((length (length items)))
    (if (<= length n)
        items
      (nthcdr (- length n) items))))

(defun stock-watch--ma-value-at (candles index period)
  "Return moving-average value for CANDLES at INDEX over PERIOD days."
  (when (>= (1+ index) period)
    (let ((sum 0.0))
      (dotimes (offset period)
        (setq sum (+ sum
                     (plist-get (nth (- index offset) candles) :close))))
      (/ sum period))))

(defun stock-watch--ma-series (candles period)
  "Return moving-average series for CANDLES using PERIOD days."
  (let (values)
    (dotimes (index (length candles))
      (push (stock-watch--ma-value-at candles index period) values))
    (nreverse values)))

(defun stock-watch--ma-samples (candles period)
  "Return recent moving-average samples for CANDLES and PERIOD."
  (cl-remove-if-not
   #'numberp
   (stock-watch--last-n
    (stock-watch--ma-series candles period)
    stock-watch-ma-sample-count)))

(defun stock-watch--ma-marker (period)
  "Return chart marker for moving-average PERIOD."
  (cdr (or (assoc period '((5 . "5")
                           (10 . "A")
                           (15 . "B")
                           (20 . "C")
                           (30 . "D")
                            (60 . "S")))
            (cons period "*"))))

(defun stock-watch--ma-face (period)
  "Return face for moving-average PERIOD."
  (cdr (or (assoc period '((5 . stock-watch-ma5-face)
                           (10 . stock-watch-ma10-face)
                           (15 . stock-watch-ma15-face)
                           (20 . stock-watch-ma20-face)
                           (30 . stock-watch-ma30-face)
                           (60 . stock-watch-ma60-face)))
           (cons period 'bold))))

(defun stock-watch--ma-point-row (value minimum maximum rows)
  "Scale moving-average VALUE between MINIMUM and MAXIMUM to ROWS."
  (stock-watch--scale-price value minimum maximum rows))

(defun stock-watch--grid-set (grid row column char face)
  "Set GRID at ROW and COLUMN to CHAR with FACE.
Existing cells keep their current marker to avoid noisy overlap glyphs."
  (when (and (<= 0 row)
             (< row (length grid))
             (<= 0 column)
             (< column (length (aref grid row))))
    (let ((line (aref grid row)))
      (unless (aref line column)
        (aset line column (cons char face))))))

(defun stock-watch--draw-ma-segment
    (grid index previous-index row previous-row marker face step)
  "Draw one moving-average segment on GRID.
INDEX and PREVIOUS-INDEX are sample positions.  ROW and PREVIOUS-ROW are
their scaled row positions.  MARKER identifies the moving average.  FACE
colors the segment, and STEP is the number of text columns between two samples."
  (let* ((from-column (* previous-index step))
         (to-column (* index step))
         (span (max 1 (- to-column from-column)))
         (line-char (cond
                     ((< row previous-row) ?/)
                     ((> row previous-row) ?\\)
                     (t ?─))))
    (dotimes (offset (1+ span))
      (let* ((column (+ from-column offset))
             (ratio (/ offset (float span)))
             (line-row (round (+ previous-row
                                  (* ratio (- row previous-row))))))
        (stock-watch--grid-set grid line-row column line-char face)))
    (stock-watch--grid-set grid previous-row from-column marker face)
    (stock-watch--grid-set grid row to-column marker face)))

(defun stock-watch--draw-ma-series
    (grid values minimum maximum rows marker face step)
  "Draw moving-average VALUES on GRID.
MINIMUM and MAXIMUM define the y-axis scale with ROWS rows.  MARKER identifies
the moving-average line.  FACE colors it, and STEP is the horizontal text
scale."
  (let ((previous-index nil)
        (previous-row nil))
    (cl-loop for value in values
             for index from 0
             do
             (when (numberp value)
               (let ((row (stock-watch--ma-point-row
                           value minimum maximum rows)))
                 (if previous-index
                     (stock-watch--draw-ma-segment
                      grid index previous-index row previous-row marker face step)
                   (stock-watch--grid-set grid row (* index step) marker face))
                 (setq previous-index index
                       previous-row row))))))

(defun stock-watch--render-ma-lines
    (series minimum maximum sample-count rows)
  "Render moving-average SERIES as continuous lines.
MINIMUM and MAXIMUM define the y-axis scale.  SAMPLE-COUNT is the number of
points on the x-axis and ROWS is the chart height."
  (let* ((step 3)
         (width (1+ (* (1- sample-count) step)))
         (grid (make-vector rows nil)))
    (dotimes (row rows)
      (aset grid row (make-vector width nil)))
    (dolist (entry series)
      (stock-watch--draw-ma-series
       grid
       (cdr entry)
       minimum
       maximum
       rows
       (string-to-char (stock-watch--ma-marker (car entry)))
       (stock-watch--ma-face (car entry))
       step))
    (dotimes (row rows)
      (let ((price (if (= maximum minimum)
                       maximum
                     (- maximum (* (/ (- maximum minimum) (float (1- rows)))
                                   row)))))
        (insert (format "%8.2f │ " price))
        (dotimes (column width)
          (let ((cell (aref (aref grid row) column)))
            (insert (if cell
                        (propertize (char-to-string (car cell))
                                    'face (cdr cell))
                      " "))))
        (insert "\n")))
    (insert "         └")
    (dotimes (_ width)
      (insert "─"))
    (insert "\n")))

(defun stock-watch--render-ma-chart (candles)
  "Render moving-average chart for CANDLES."
  (let* ((series-by-period
          (mapcar
           (lambda (period)
             (cons period (stock-watch--ma-samples candles period)))
           stock-watch-ma-periods))
          (complete-series
           (cl-remove-if
            (lambda (entry)
              (null (cdr entry)))
            series-by-period))
          (sample-count
           (if complete-series
               (min stock-watch-ma-sample-count
                    (apply #'max (mapcar (lambda (entry)
                                           (length (cdr entry)))
                                         complete-series)))
             0))
          (aligned-series
           (mapcar
            (lambda (entry)
              (let* ((values (stock-watch--last-n (cdr entry) sample-count))
                     (padding (- sample-count (length values))))
                (cons (car entry) (append (make-list padding nil) values))))
            complete-series))
          (drawable-series
           (cl-remove-if
            (lambda (entry)
              (< (cl-count-if #'numberp (cdr entry)) 2))
            aligned-series))
          (single-point-series
           (cl-remove-if-not
            (lambda (entry)
              (= (cl-count-if #'numberp (cdr entry)) 1))
            aligned-series))
          (all-values (cl-remove-if-not
                       #'numberp
                       (apply #'append (mapcar #'cdr drawable-series)))))
    (stock-watch--insert-section-title "Moving averages")
    (if (not all-values)
        (insert "Not enough historical data to draw lines.\n")
      (let* ((rows 12)
             (minimum (apply #'min all-values))
             (maximum (apply #'max all-values))
             (dates (stock-watch--last-n
                      (mapcar (lambda (candle) (plist-get candle :day)) candles)
                      sample-count)))
        (insert (if (= sample-count stock-watch-ma-sample-count)
                    (format "%d samples, %d/%d history days\n"
                            sample-count
                            (length candles)
                            (stock-watch--ma-history-days))
                  (format "%d available samples; target %d, %d/%d history days\n"
                          sample-count
                          stock-watch-ma-sample-count
                          (length candles)
                          (stock-watch--ma-history-days))))
        (when (< (length candles) (stock-watch--ma-history-days))
          (insert (format "Warning: only %d K-line records were supplied; MA%d needs %d records for %d samples.\n"
                          (length candles)
                           (apply #'max stock-watch-ma-periods)
                           (stock-watch--ma-history-days)
                           stock-watch-ma-sample-count)))
        (insert "Legend: ")
        (dolist (entry drawable-series)
          (insert (propertize (stock-watch--ma-marker (car entry))
                              'face (stock-watch--ma-face (car entry)))
                  (format "=MA%d " (car entry))))
        (insert "(overlaps keep the first drawn line)\n")
        (when single-point-series
          (insert "Skipped single-point averages: ")
          (dolist (entry single-point-series)
            (insert (format "MA%d " (car entry))))
          (insert "(need at least 2 points to draw a line)\n"))
        (stock-watch--render-ma-lines
         drawable-series minimum maximum sample-count rows)
        (insert "          ")
        (let ((first-date (substring (car dates) 5))
              (last-date (substring (car (last dates)) 5)))
          (insert first-date
                  (make-string (max 1 (- (1+ (* (1- sample-count) 3))
                                          (length first-date)
                                          (length last-date)))
                               ?\s)
                  last-date))
        (insert "\n\n")
        (dolist (entry drawable-series)
          (insert (format "MA%-2d "
                           (car entry)))
          (dolist (value (cdr entry))
            (insert (if (numberp value)
                        (format " %5.2f" value)
                      "     -")))
          (insert "\n"))))))

(defun stock-watch--render-kline-chart (code candles &optional name)
  "Render a K-line chart for CODE from CANDLES.
Use NAME in the chart title if it is non-nil."
  (let* ((visible-candles (stock-watch--last-n candles stock-watch-kline-days))
         (rows 16)
         (highs (mapcar (lambda (candle) (plist-get candle :high)) visible-candles))
         (lows (mapcar (lambda (candle) (plist-get candle :low)) visible-candles))
         (maximum (apply #'max highs))
         (minimum (apply #'min lows))
         (last-close (plist-get (car (last visible-candles)) :close)))
    (stock-watch--insert-title
     (format "%s - K-line chart" (stock-watch--label code name)))
    (insert (format "Visible days: %d  History days: %d  Last close: %.2f\n\n"
                    (length visible-candles) (length candles) last-close))
    (stock-watch--insert-section-title "Candlesticks")
    (dotimes (row rows)
      (let ((price (if (= maximum minimum)
                       maximum
                     (- maximum (* (/ (- maximum minimum) (float (1- rows)))
                                   row)))))
        (insert (format "%8.2f │ " price))
        (dolist (candle visible-candles)
          (insert "  " (stock-watch--render-candle-row
                        row candle minimum maximum rows)
                  "  "))
        (insert "\n")))
    (insert "         └")
    (dotimes (_ (length visible-candles))
      (insert "─────"))
    (insert "\n          ")
    (dolist (candle visible-candles)
      (insert (format "%5s" (substring (plist-get candle :day) 5))))
    (insert "\n\n")
    (stock-watch--render-volume-bars visible-candles)
    (insert "\n")
    (stock-watch--render-ma-chart candles)
    (insert "\n")
    (insert "Move point to a date row and press C-c C-m, RET, or m for intraday chart.\n\n")
    (stock-watch--insert-section-title "Daily data")
    (insert "Date        Open    High     Low   Close        Volume  Volume Bar\n")
    (dolist (candle visible-candles)
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
                                   visible-candles))
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
    (stock-watch--insert-title
     (format "%s - %s intraday chart" (stock-watch--label code name) date))
    (insert (format "Interval: %d minutes  Last: %.2f\n\n"
                    stock-watch-intraday-interval last-close))
    (stock-watch--insert-section-title "Intraday prices")
    (dotimes (row rows)
      (let ((price (if (= maximum minimum)
                       maximum
                     (- maximum (* (/ (- maximum minimum) (float (1- rows)))
                                   row)))))
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
