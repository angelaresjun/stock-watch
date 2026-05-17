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

(require 'stock-watch-core)

;;;###autoload
(defalias 'stock-watch #'stock-watch-start)

(provide 'stock-watch)

;;; stock-watch.el ends here
