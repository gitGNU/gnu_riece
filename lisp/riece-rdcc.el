;;; riece-rdcc.el --- ruby implementation of DCC add-on
;; Copyright (C) 1998-2003 Daiki Ueno

;; Author: Daiki Ueno <ueno@unixuser.org>
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

;;; Code:

(defgroup riece-rdcc nil
  "DCC implementation using ruby"
  :prefix "riece-"
  :group 'riece)

(defcustom riece-rdcc-server-address "127.0.0.1"
  "Local address of the DCC server.
Only used for sending files."
  :type 'vector
  :group 'riece-rdcc)

(defvar riece-rdcc-requests nil)

(defvar riece-rdcc-request-user nil)
(defvar riece-rdcc-request-file nil)
(defvar riece-rdcc-request-size nil)

(defun riece-rdcc-server-filter (process input)
  (save-excursion
    (set-buffer (process-buffer process))
    (goto-char (point-max))
    (insert input)
    (goto-char (point-min))
    (while (and (not (eobp))
		(looking-at "\\([0-9]+\\)\n"))
      (message "Sending %s...(%s/%d)"
	       riece-rdcc-request-file
	       (match-string 1) riece-rdcc-request-size)
      (forward-line))
    (unless (eobp)
      (delete-region (point-min) (point)))))

(defun riece-rdcc-server-sentinel (process status)
  (with-current-buffer (process-buffer process)
    (message "Sending %s...done" riece-rdcc-request-file))
  (kill-buffer (process-buffer process))
  (delete-process process))

(defun riece-command-dcc-send (user file)
  (interactive
   (let ((completion-ignore-case t))
     (unless riece-rdcc-server-address
       (error "Set riece-rdcc-server-address to your host"))
     (list (completing-read
	    "User: "
	    (mapcar #'list (riece-get-users-on-server)))
	   (expand-file-name (read-file-name "File: ")))))
  (let ((process
	 (start-process "DCC" " *DCC*" "ruby" "-rsocket")))
    (process-send-string process (concat "\
server = TCPServer.new('" riece-rdcc-server-address "', 0)
puts(\"#{server.addr[3].split(/\\./).collect{|c| c.to_i}.pack('cccc').unpack('N')[0]} #{server.addr[1]}\")
session = server.accept
if session
  total = 0
  File.open('" file "') {|file|
    while (bytes = file.read(1024))
      total += bytes.length
      puts(\"#{total}\")
      session.write(bytes)
    end
  }
  session.close
end
"))
    (process-send-eof process)
    (save-excursion
      (set-buffer (process-buffer process))
      (while (and (eq (process-status process) 'run)
		  (progn
		    (goto-char (point-min))
		    (not (looking-at "\\([0-9]+\\) \\([0-9]+\\)"))))
	(accept-process-output))
      (if (eq (process-status process) 'run)
	  (let ((address (match-string 1))
		(port (match-string 2)))
	    (erase-buffer)
	    (make-local-variable 'riece-rdcc-request-size)
	    (setq riece-rdcc-request-file file
		  riece-rdcc-request-size (nth 7 (file-attributes file)))
	    (set-buffer-modified-p nil)
	    (set-process-filter process #'riece-rdcc-server-filter)
	    (set-process-sentinel process #'riece-rdcc-server-sentinel)
	    (riece-send-string
	     (format "PRIVMSG %s :\1DCC SEND %s %s %s %d\1\r\n"
		     user (file-name-nondirectory file)
		     address port
		     riece-rdcc-request-size)))))))

(defun riece-rdcc-filter (process input)
  (save-excursion
    (set-buffer (process-buffer process))
    (goto-char (point-max))
    (insert input)
    (message "Receiving %s from %s...(%d/%d)"
	     (file-name-nondirectory buffer-file-name)
	     riece-rdcc-request-user
	     (1- (point))
	     riece-rdcc-request-size)))

(defun riece-rdcc-sentinel (process status)
  (save-excursion
    (set-buffer (process-buffer process))
    (unless (= (buffer-size) riece-rdcc-request-size)
      (error "Premature end of file"))
    (message "Receiving %s from %s...done"
	     (file-name-nondirectory buffer-file-name)
	     riece-rdcc-request-user)
    (let ((coding-system-for-write 'binary))
      (save-buffer))))

(defun riece-rdcc-decode-address (address)
  (with-temp-buffer
    (call-process "ruby" nil t nil "-e" (concat "\
puts(\"#{" address " >> 24 & 0xFF}.#{" address " >> 16 & 0xFF}.#{" address " >> 8 & 0xFF}.#{" address " & 0xFF}\")"))
    (buffer-substring (point-min) (1- (point-max)))))

(defun riece-command-dcc-receive (request file)
  (interactive
   (progn
     (unless riece-rdcc-requests
       (error "No request"))
     (list
      (if (= (length riece-rdcc-requests) 1)
	  (car riece-rdcc-requests)
	(with-output-to-temp-buffer "*Help*"
	  (let ((requests riece-rdcc-requests)
		(index 1))
	    (while requests
	      (princ (format "%2d: %s %s (%d bytes)\n"
			     index
			     (car (car requests))
			     (nth 1 (car requests))
			     (nth 4 (car requests))))
	      (setq index (1+ index)
		    requests (cdr requests)))))
	(let ((number (read-string "Request#: ")))
	  (unless (string-match "^[0-9]+$" number)
	    (error "Not a number"))
	  (if (or (> (setq number (string-to-number number))
		     (length riece-rdcc-requests))
		  (< number 1))
	      (error "Invalid number"))
	  (nth (1- number) riece-rdcc-requests)))
      (expand-file-name (read-file-name "Save as: ")))))
  (let* (selective-display
	 (coding-system-for-read 'binary)
	 (coding-system-for-write 'binary)
	 (process (open-network-stream
		   "DCC" " *DCC*"
		   (riece-rdcc-decode-address (nth 2 request))
		   (nth 3 request))))
    (setq riece-rdcc-requests (delq request riece-rdcc-requests))
    (with-current-buffer (process-buffer process)
      (set-buffer-multibyte nil)
      (buffer-disable-undo)
      (setq buffer-file-name file)
      (make-local-variable 'riece-rdcc-request-user)
      (setq riece-rdcc-request-user (car request))
      (make-local-variable 'riece-rdcc-request-size)
      (setq riece-rdcc-request-size (nth 4 request)))
    (set-process-filter process #'riece-rdcc-filter)
    (set-process-sentinel process #'riece-rdcc-sentinel)))

(defun riece-handle-dcc-request (prefix target message)
  (let ((case-fold-search t))
    (when (string-match
	   "SEND \\([^ ]+\\) \\([^ ]+\\) \\([^ ]+\\) \\([^ ]+\\)"
	   message)
      (let ((file (match-string 1 message))
	    (address (match-string 2 message))
	    (port (string-to-number (match-string 3 message)))
	    (size (string-to-number (match-string 4 message)))
	    (buffer (if (riece-channel-p target)
			(cdr (riece-identity-assoc-no-server
			      (riece-make-identity target)
			      riece-channel-buffer-alist))))
	    (user (riece-prefix-nickname prefix)))
	(setq riece-rdcc-requests
	      (cons (list user file address port size)
		    riece-rdcc-requests))
	(riece-insert-change buffer (format "DCC SEND from %s\n" user))
	(riece-insert-change
	 (if (and riece-channel-buffer-mode
		  (not (eq buffer riece-channel-buffer)))
	     (list riece-dialogue-buffer riece-others-buffer)
	   riece-dialogue-buffer)
	 (concat
	  (riece-concat-server-name
	   (format "DCC SEND from %s (%s) to %s"
		   user
		   (riece-strip-user-at-host
		    (riece-prefix-user-at-host prefix))
		   target))
	  "\n")))
      t)))

(defun riece-rdcc-requires ()
  '(riece-ctcp))

(defvar riece-dialogue-mode-map)
(defun riece-rdcc-insinuate ()
  (add-hook 'riece-ctcp-dcc-request-hook 'riece-handle-dcc-request)
  (define-key riece-dialogue-mode-map "\C-ds" 'riece-command-dcc-send)
  (define-key riece-dialogue-mode-map "\C-dr" 'riece-command-dcc-receive))

(provide 'riece-rdcc)

;;; riece-rdcc.el ends here
