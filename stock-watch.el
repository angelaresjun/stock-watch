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

(defconst stock-watch--module-files
  '("stock-watch-config.el"
    "stock-watch-fetch.el"
    "stock-watch-keys.el"
    "stock-watch-display.el"
    "stock-watch-core.el")
  "Stock-watch module files loaded by the package entry point.")

(defun stock-watch--load-modules ()
  "Load stock-watch modules in dependency order."
  (let* ((entry-file (or load-file-name buffer-file-name))
         (directory (and entry-file (file-name-directory entry-file))))
    (if (and directory
             (cl-every (lambda (module)
                         (file-exists-p (expand-file-name module directory)))
                       stock-watch--module-files))
        (dolist (module stock-watch--module-files)
          (load (expand-file-name module directory) nil nil))
      (require 'stock-watch-core))))

(stock-watch--load-modules)

(declare-function stock-watch-start "stock-watch-core")
(declare-function stock-watch--kline-history-days "stock-watch-core")

;;;###autoload
(defun stock-watch-reload ()
  "Reload stock-watch source modules from the current package directory."
  (interactive)
  (stock-watch--load-modules)
  (message "stock-watch reloaded; K-line fetch will request %d history days"
           (stock-watch--kline-history-days)))

;;;###autoload
(defalias 'stock-watch #'stock-watch-start)

(provide 'stock-watch)

;;; stock-watch.el ends here
