;;; riece-message.el --- generate and display message line
;; Copyright (C) 1999-2003 Daiki Ueno

;; Author: Daiki Ueno <ueno@unixuser.org>
;; Keywords: message

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

(require 'riece-identity)
(require 'riece-channel)
(require 'riece-user)
(require 'riece-display)
(require 'riece-misc)

(defgroup riece-message nil
  "Messages"
  :tag "Message"
  :prefix "riece-"
  :group 'riece)

(defcustom riece-message-make-open-bracket-function
  #'riece-message-make-open-bracket
  "Function which makes `open-bracket' string for each message."
  :type 'function
  :group 'riece-message)

(defcustom riece-message-make-close-bracket-function
  #'riece-message-make-close-bracket
  "Function which makes `close-bracket' string for each message."
  :type 'function
  :group 'riece-message)

(defcustom riece-message-make-name-function
  #'riece-message-make-name
  "Function which makes local identity for each message."
  :type 'function
  :group 'riece-message)

(defcustom riece-message-make-global-name-function
  #'riece-message-make-global-name
  "Function which makes global identity for each message."
  :type 'function
  :group 'riece-message)

(defun riece-message-make-open-bracket (message)
  "Make `open-bracket' string for MESSAGE."
  (if (riece-message-own-p message)
      ">"
    (if (eq (riece-message-type message) 'notice)
	"{"
      (if (riece-message-private-p message)
	  "="
	(if (riece-message-external-p message)
	    "("
	  "<")))))

(defun riece-message-make-close-bracket (message)
  "Make `close-bracket' string for MESSAGE."
  (if (riece-message-own-p message)
      "<"
    (if (eq (riece-message-type message) 'notice)
	"}"
      (if (riece-message-private-p message)
	  "="
	(if (riece-message-external-p message)
	    ")"
	  ">")))))

(defun riece-message-make-name (message)
  "Make local identity for MESSAGE."
  (if (riece-message-private-p message)
      (if (riece-message-own-p message)
	  (riece-decode-identity (riece-message-target message) t)
	(riece-decode-identity (riece-message-speaker message) t))
    (riece-decode-identity (riece-message-speaker message) t)))

(defun riece-message-make-global-name (message)
  "Make global identity for MESSAGE."
  (if (riece-message-private-p message)
      (if (riece-message-own-p message)
	  (riece-decode-identity (riece-message-target message) t)
	(riece-decode-identity (riece-message-speaker message) t))
    (concat (riece-decode-identity (riece-message-target message) t) ":"
	    (riece-decode-identity (riece-message-speaker message) t))))

(defun riece-message-buffer (message)
  "Return the buffer where MESSAGE should appear."
  (let ((target (if (riece-message-private-p message)
		    (if (riece-message-own-p message)
			(riece-message-target message)
		      (riece-message-speaker message))
		  (riece-message-target message))))
    (unless (riece-identity-member target riece-current-channels)
      (riece-join-channel target)
      ;; If you are not joined any channel,
      ;; switch to the target immediately.
      (unless riece-current-channel
	(riece-switch-to-channel target))
      (riece-redisplay-buffers))
    (riece-channel-buffer-name target)))

(defun riece-message-parent-buffers (message buffer)
  "Return the parents of BUFFER where MESSAGE should appear.
Normally they are *Dialogue* and/or *Others*."
  (if (riece-message-own-p message)
      riece-dialogue-buffer
    (if (and buffer (riece-frozen buffer)) ;the message might not be
					   ;visible in buffer's window
	(list riece-dialogue-buffer riece-others-buffer)
      (if (and riece-current-channel	;the message is not sent to
					;the current channel
	       (if (riece-message-private-p message)
		   (not (riece-identity-equal
			 (riece-message-speaker message)
			 riece-current-channel))
		 (not (riece-identity-equal
		       (riece-message-target message)
		       riece-current-channel))))
	  (list riece-dialogue-buffer riece-others-buffer)
	riece-dialogue-buffer))))

(defun riece-display-message (message)
  "Display MESSAGE object."
  (let ((open-bracket
	 (funcall riece-message-make-open-bracket-function message))
	(close-bracket
	 (funcall riece-message-make-close-bracket-function message))
	(name
	 (funcall riece-message-make-name-function message))
	(global-name
	 (funcall riece-message-make-global-name-function message))
	(buffer (riece-message-buffer message))
	(server-name (riece-identity-server (riece-message-speaker message)))
	parent-buffers)
    (when (and buffer
	       (riece-message-own-p message)
	       (riece-own-frozen buffer))
      (with-current-buffer buffer
	(setq riece-freeze nil))
      (riece-update-status-indicators))
    (setq parent-buffers (riece-message-parent-buffers message buffer))
    (riece-insert buffer
		  (concat open-bracket name close-bracket
			  " " (riece-message-text message) "\n"))
    (riece-insert parent-buffers
		  (if (equal server-name "")
		      (concat open-bracket global-name close-bracket
			      " " (riece-message-text message) "\n")
		     (concat open-bracket global-name close-bracket
			     " " (riece-message-text message)
			     " (from " server-name ")\n")))
    (run-hook-with-args 'riece-after-display-message-functions message)))

(defun riece-make-message (speaker target text &optional type own-p)
  "Make an instance of message object.
Arguments are appropriate to the sender, the receiver, and text
content, respectively.
Optional 4th argument TYPE specifies the type of the message.
Currently possible values are `action' and `notice'.
Optional 5th argument is the flag to indicate that this message is not
from the network."
  (vector speaker target text type own-p))

(defun riece-message-speaker (message)
  "Return the sender of MESSAGE."
  (aref message 0))

(defun riece-message-target (message)
  "Return the receiver of MESSAGE."
  (aref message 1))

(defun riece-message-text (message)
  "Return the text part of MESSAGE."
  (aref message 2))

(defun riece-message-type (message)
  "Return the type of MESSAGE.
Currently possible values are `action' and `notice'."
  (aref message 3))

(defun riece-message-own-p (message)
  "Return t if MESSAGE is not from the network."
  (aref message 4))

(defun riece-message-private-p (message)
  "Return t if MESSAGE is a private message."
  (not (or (riece-channel-p (riece-identity-prefix
			     (riece-message-speaker message)))
	   (riece-channel-p (riece-identity-prefix
			     (riece-message-target message))))))

(defun riece-message-external-p (message)
  "Return t if MESSAGE is from outside the channel."
  (not (riece-identity-member
	(riece-message-speaker message)
	(let ((target (riece-message-target message)))
	  (riece-with-identity-buffer target
	    (mapcar
	     (lambda (user)
	       (riece-make-identity user riece-server-name))
	     (riece-channel-get-users (riece-identity-prefix target))))))))

(defun riece-own-channel-message (message &optional channel type)
  "Display MESSAGE as you sent to CHNL."
  (riece-display-message
   (riece-make-message (riece-current-nickname)
		       (or channel riece-current-channel)
		       message type t)))

(provide 'riece-message)

;;; riece-message.el ends here
