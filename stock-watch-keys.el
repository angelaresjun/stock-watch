;;; stock-watch-keys.el --- Key bindings for stock-watch -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Joshua
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Keymaps and key-binding helpers for stock-watch.

;;; Code:

(require 'tabulated-list)

(declare-function stock-watch-refresh "stock-watch-core")
(declare-function stock-watch-show-kline "stock-watch-core")
(declare-function stock-watch-quit "stock-watch-core")
(declare-function stock-watch-show-intraday-at-point "stock-watch-core")

(defvar stock-watch-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "g") #'stock-watch-refresh)
    (define-key map (kbd "k") #'stock-watch-show-kline)
    (define-key map (kbd "RET") #'stock-watch-show-kline)
    (define-key map (kbd "C-c C-k") #'stock-watch-show-kline)
    (define-key map (kbd "q") #'stock-watch-quit)
    map)
  "Keymap for `stock-watch-mode'.")

(defvar stock-watch-kline-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'stock-watch-show-intraday-at-point)
    (define-key map (kbd "m") #'stock-watch-show-intraday-at-point)
    (define-key map (kbd "C-c C-m") #'stock-watch-show-intraday-at-point)
    map)
  "Keymap for `stock-watch-kline-mode'.")

(defun stock-watch-keys--setup-viper (bindings)
  "Install Viper local key BINDINGS for the current buffer when available."
  (when (fboundp 'viper-add-local-keys)
    (dolist (state '(vi-state insert-state emacs-state))
      (with-demoted-errors "stock-watch Viper key setup failed: %S"
        (viper-add-local-keys state bindings)))))

(defun stock-watch-keys-setup-main ()
  "Install stock watch main-buffer keys for the current buffer."
  (stock-watch-keys--setup-viper
   '(("C-c C-k" . stock-watch-show-kline))))

(defun stock-watch-keys-setup-kline ()
  "Install stock watch K-line-buffer keys for the current buffer."
  (stock-watch-keys--setup-viper
   '(("C-c C-m" . stock-watch-show-intraday-at-point))))

(define-derived-mode stock-watch-kline-mode special-mode "Stock-Watch-KLine"
  "Major mode for stock K-line charts.

Move point to a date row and press \\<stock-watch-kline-mode-map>\\[stock-watch-show-intraday-at-point]
to show the intraday chart for that day."
  (stock-watch-keys-setup-kline))

(provide 'stock-watch-keys)

;;; stock-watch-keys.el ends here
