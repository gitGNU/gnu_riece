;;; riece-xemacs.el --- XEmacs specific functions
;; Copyright (C) 1998-2003 Daiki Ueno

;; Author: Daiki Ueno <ueno@unixuser.org>
;; Keywords: emulation

;; This file is part of Riece.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Code:

(defun riece-xemacs-hide-modeline ()
  "Remove modeline from current window."
  (set-specifier has-modeline-p nil (current-buffer)))

(when (featurep 'scrollbar)
  (defun riece-xemacs-hide-scrollbars ()
    (if (boundp 'horizontal-scrollbar-visible-p)
	(set-specifier horizontal-scrollbar-visible-p nil (current-buffer))
      (if (boundp 'scrollbar-height)
	  (set-specifier scrollbar-height 0 (current-buffer)))))
  (add-hook 'riece-user-list-mode-hook 'riece-xemacs-hide-scrollbars)
  (add-hook 'riece-channel-list-mode-hook 'riece-xemacs-hide-scrollbars))

(add-hook 'riece-user-list-mode-hook 'riece-xemacs-hide-modeline)
(add-hook 'riece-channel-list-mode-hook 'riece-xemacs-hide-modeline)

(defun riece-xemacs-mode-line-buffer-identification (line)
  "Decorate 1st	element	of `mode-line-buffer-identification' LINE.
Modify whole identification by side effect."
  (let ((id (car line)) chop)
    (if (and (stringp id) (string-match "^Riece:" id))
	(progn
	  (setq chop (match-end 0))
	  (nconc
	   (list
	    (cons (copy-extent modeline-buffer-id-left-extent)
		  (substring id 0 chop))
	    (cons (copy-extent modeline-buffer-id-right-extent)
		  (substring id chop)))
	   (cdr line)))
      line)))

(defun riece-xemacs-simplify-modeline-format ()
  "Remove unnecessary information from `modeline-format'."
  (setq modeline-format
	(remrassq 'modeline-modified
		  (delq 'modeline-multibyte-status
			(copy-sequence mode-line-format)))))

(defalias 'riece-mode-line-buffer-identification
  'riece-xemacs-mode-line-buffer-identification)

(defalias 'riece-simplify-mode-line-format
  'riece-xemacs-simplify-modeline-format)

(defalias 'riece-set-case-syntax-pair
  'put-case-table-pair)

;;; stolen (and renamed) from gnus-xmas.el.
;;; In GNU Emacs, user can intercept whole mouse tracking events by
;;; assigning [mouse-X].  In XEmacs, however, which causes different
;;; effect, that is, the command assigned to [mouse-X] only catches
;;; button-release events.
(defvar riece-mouse-2 [button2])

;;; popup-menu compatibility stuff, stolen (and renamed) from
;;; semi-def.el.
(defun riece-popup-menu-popup (menu event)
  (let ((response (get-popup-menu-response menu event)))
    (if response
	(funcall (event-function response) (event-object response)))))

(defalias 'riece-event-buffer 'event-buffer)
(defalias 'riece-event-point 'event-point)

;;; stolen (and renamed) from gnus-xmas.el.
(defalias 'riece-region-active-p 'region-active-p)

(provide 'riece-xemacs)

;;; riece-xemacs.el ends here
