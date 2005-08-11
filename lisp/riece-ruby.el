;;; riece-ruby.el --- interact with Ruby interpreter
;; Copyright (C) 1998-2005 Daiki Ueno

;; Author: Daiki Ueno <ueno@unixuser.org>
;; Created: 1998-09-28
;; Keywords: IRC, riece

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

;;; Commentary:

;; riece-ruby.el is a library to interact with the Ruby interpreter.
;; It supports concurrent execution of Ruby programs in a single
;; session.  For example:
;; 
;; (riece-ruby-execute "sleep 30"); returns immediately
;; => "rubyserv0"
;;
;; (riece-ruby-execute "1 + 1")
;; => "rubyserv1"
;;
;; (riece-ruby-execute "\"")
;; => "rubyserv2"
;;
;; (riece-ruby-inspect "rubyserv0")
;; => ((OK nil) nil "running")
;;
;; (riece-ruby-inspect "rubyserv1")
;; => ((OK nil) "2" "finished")
;;
;; (riece-ruby-inspect "rubyserv2")
;; => ((OK nil) "(eval):1: unterminated string meets end of file" "exited")

;;; Code:

(defvar riece-ruby-command "ruby"
  "Command name for Ruby interpreter.")

(defvar riece-ruby-server-program "server.rb")

(defvar riece-ruby-process nil)

(defvar riece-ruby-lock nil)
(defvar riece-ruby-response nil)
(defvar riece-ruby-data nil)
(defvar riece-ruby-escaped-data nil)
(defvar riece-ruby-status-alist nil)

(defvar riece-ruby-output-handler-alist nil)
(defvar riece-ruby-exit-handler-alist nil)

(defun riece-ruby-substitute-variables (program variable value)
  (setq program (copy-sequence program))
  (let ((pointer program))
    (while pointer
      (setq pointer (memq variable program))
      (if pointer
	  (setcar pointer value)))
    program))

(defun riece-ruby-escape-data (data)
  (let ((index 0))
    (while (string-match "[%\r\n]+" data index)
      (setq data (replace-match
		  (mapconcat (lambda (c) (format "%%%02X" c))
			     (match-string 0 data) "")
		  nil nil data)
	    index (+ (match-end 0)
		     (* (- (match-end 0) (match-beginning 0)) 2))))
    data))

(defun riece-ruby-unescape-data (data)
  (let ((index 0))
    (while (string-match "%\\([0-9A-F][0-9A-F]\\)" data index)
      (setq data (replace-match
		  (read (concat "\"\\x" (match-string 1 data) "\""))
		  nil nil data)
	    index (- (match-end 0) 2)))
    data))

(defun riece-ruby-reset-process-buffer ()
  (save-excursion
    (set-buffer (process-buffer riece-ruby-process))
    (buffer-disable-undo)
    (make-local-variable 'riece-ruby-response)
    (setq riece-ruby-response nil)
    (make-local-variable 'riece-ruby-data)
    (setq riece-ruby-data nil)
    (make-local-variable 'riece-ruby-escaped-data)
    (setq riece-ruby-escaped-data nil)
    (make-local-variable 'riece-ruby-status-alist)
    (setq riece-ruby-status-alist nil)))

(defun riece-ruby-send-eval (program)
  (let* ((string (riece-ruby-escape-data program))
	 (length (- (length string) 998))
	 (index 0)
	 data)
    (while (< index length)
      (setq data (cons (substring string index (setq index (+ index 998)))
		       data)))
    (setq data (cons (substring string index) data)
	  data (nreverse data))
    (process-send-string riece-ruby-process "EVAL\r\n")
    (while data
      (process-send-string riece-ruby-process
			   (concat "D " (car data) "\r\n"))
      (setq data (cdr data)))
    (process-send-string riece-ruby-process "END\r\n")))

(defun riece-ruby-send-poll (name)
  (process-send-string riece-ruby-process
		       (concat "POLL " name "\r\n")))

(defun riece-ruby-send-exit (name)
  (process-send-string riece-ruby-process
		       (concat "EXIT " name "\r\n")))

(defun riece-ruby-filter (process input)
  (save-excursion
    (set-buffer (process-buffer process))
    (goto-char (point-max))
    (insert input)
    (goto-char (process-mark process))
    (beginning-of-line)
    (while (looking-at ".*\r\n")
      (if (looking-at "OK\\( \\(.*\\)\\)?\r")
	  (progn
	    (if riece-ruby-escaped-data
		(setq riece-ruby-data (mapconcat #'riece-ruby-unescape-data
						 riece-ruby-escaped-data "")))
	    (setq riece-ruby-escaped-data nil
		  riece-ruby-response (list 'OK (match-string 2))
		  riece-ruby-lock nil))
	(if (looking-at "ERR \\([0-9]+\\)\\( \\(.*\\)\\)?\r")
	    (progn
	      (setq riece-ruby-escaped-data nil
		    riece-ruby-response
		    (list 'ERR (string-to-number (match-string 2))
			  (match-string 3))
		    riece-ruby-lock nil))
	  (if (looking-at "D \\(.*\\)\r")
	      (setq riece-ruby-escaped-data (cons (match-string 1)
						  riece-ruby-escaped-data))
	    (if (looking-at "S \\(.*\\) \\(.*\\)\r")
		(progn
		  (setq riece-ruby-status-alist (cons (cons (match-string 1)
							    (match-string 2))
						      riece-ruby-status-alist))
		  (if (member (car (car riece-ruby-status-alist))
			      '("finished" "exited"))
		      (riece-ruby-run-exit-handler
		       (cdr (car riece-ruby-status-alist)))))
	      (if (looking-at "# output \\(.*\\) \\(.*\\)\r")
		  (let ((entry (assoc (match-string 1)
				      riece-ruby-output-handler-alist)))
		    (if entry
			(funcall (cdr entry) (match-string 2))))
		(if (looking-at "# exit \\(.*\\)\r")
		    (riece-ruby-run-exit-handler (match-string 1))))))))
      (forward-line))
    (set-marker (process-mark process) (point-marker))))

(defun riece-ruby-run-exit-handler (name)
  (let ((entry (assoc name riece-ruby-exit-handler-alist)))
    (if entry
	(progn
	  (funcall (cdr entry))
	  (setq riece-ruby-exit-handler-alist (delq entry))))))

(defun riece-ruby-sentinel (process status)
  (kill-buffer (process-buffer process)))

(defun riece-ruby-execute (program)
  (unless (and riece-ruby-process
	       (eq (process-status riece-ruby-process) 'run))
    (let (selective-display
	  (coding-system-for-write 'binary)
	  (coding-system-for-read 'binary))
      (setq riece-ruby-process
	    (start-process "riece-ruby" (generate-new-buffer " *Ruby*")
			   riece-ruby-command
			   (if (file-name-absolute-p riece-ruby-server-program)
			       riece-ruby-server-program
			     (expand-file-name
			      riece-ruby-server-program
			      (file-name-directory
			       (symbol-file 'riece-ruby-execute))))))
      (set-process-filter riece-ruby-process #'riece-ruby-filter)
      (set-process-sentinel riece-ruby-process #'riece-ruby-sentinel)))
  (save-excursion
    (set-buffer (process-buffer riece-ruby-process))
    (riece-ruby-reset-process-buffer)
    (make-local-variable 'riece-ruby-lock)
    (setq riece-ruby-lock t)
    (riece-ruby-send-eval program)
    (while riece-ruby-lock
      (accept-process-output riece-ruby-process))
    (if (eq (car riece-ruby-response) 'ERR)
	(error "Couldn't execute: %S" (cdr riece-ruby-response)))
    (cdr (assoc "name" riece-ruby-status-alist))))

(defun riece-ruby-inspect (name)
  (save-excursion
    (set-buffer (process-buffer riece-ruby-process))
    (riece-ruby-reset-process-buffer)
    (make-local-variable 'riece-ruby-lock)
    (setq riece-ruby-lock t)
    (riece-ruby-send-poll name)
    (while (null riece-ruby-response)
      (accept-process-output riece-ruby-process))
    (list riece-ruby-response
	  riece-ruby-data
	  riece-ruby-status-alist)))

(defun riece-ruby-clear (name)
  (save-excursion
    (set-buffer (process-buffer riece-ruby-process))
    (riece-ruby-reset-process-buffer)
    (make-local-variable 'riece-ruby-lock)
    (setq riece-ruby-lock t)
    (riece-ruby-send-exit name)
    (while (null riece-ruby-response)
      (accept-process-output riece-ruby-process))))

(defun riece-ruby-set-exit-handler (name handler)
  (let ((entry (assoc name riece-ruby-exit-handler-alist)))
    (if entry
	(setcdr entry handler)
      (setq riece-ruby-exit-handler-alist
	    (cons (cons name handler)
		  riece-ruby-exit-handler-alist)))
    ;;check if the program already exited
    (riece-ruby-inspect)))

(provide 'riece-ruby)

;;; riece-ruby.el ends here
