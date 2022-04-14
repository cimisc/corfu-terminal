;;; corfu-popup.el --- Corfu popup on terminal -*- lexical-binding: t -*-

;; Copyright (C) 2022 Akib Azmain Turja.

;; Author: Akib Azmain Turja <akib@disroot.org>
;; Created: 2022-04-11
;; Version: 0.1
;; Package-Requires: ((emacs "27.1") corfu popon)
;; Keywords: convenience
;; Homepage: https://codeberg.org/akib/emacs-corfu-popup

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Corfu uses child frames to display candidates.  This makes Corfu
;; unusable on terminal.  This package replaces that with popup/popon,
;; which works everywhere.  Use M-x corfu-popup-mode to enable.  You'll
;; probably want to enable it only on terminal.  In that case, put the
;; following it your init file:

;;   (unless (display-graphic-p)
;;     (corfu-popup-mode +1))

;;; Code:

(require 'subr-x)
(require 'corfu)
(require 'popon "/home/akib/projects/emacs-popon/popon.el")

(declare-function corfu--auto-tick "corfu") ;; OK, byte-compiler?

(defvar corfu-popup--popon nil
  "Popon object.")

(defvar corfu-popup--last-position nil
  "Position of last popon, and some data is to make sure that's valid.")

(defun corfu-popup--popup-hide ()
  "Hide popup."
  (when corfu-popup--popon
    (setq corfu-popup--popon (popon-kill corfu-popup--popon))))

(defun corfu-popup--popup-show (pos off width lines &optional curr lo bar)
  "Show popup at OFF columns before POS.

Show LINES, a list of lines.  Highlight CURRth line as current selection.
Show a vertical scroll bar of size BAR + 1 from LOth line."
  (corfu-popup--popup-hide)  ; Hide the popup first.
  (let* ((bar-width (if (display-graphic-p)
                        (ceiling (* (default-font-width) corfu-bar-width))
                      (ceiling corfu-bar-width)))
         (margin-left-width (if (display-graphic-p)
                                (ceiling (* (default-font-width)
                                            corfu-left-margin-width))
                              (ceiling corfu-left-margin-width)))
         (margin-right-width (max (if (display-graphic-p)
                                      (ceiling
                                       (* (default-font-width)
                                          corfu-right-margin-width))
                                    (ceiling corfu-right-margin-width))
                                  bar-width))
         (scroll-bar (when (< 0 bar-width)
                       (if (display-graphic-p)
                           (concat
                            (propertize " " 'display
                                        `(space
                                          :width (,(- margin-right-width
                                                      bar-width))))
                            (propertize " " 'display
                                        `(space :width (,bar-width))
                                        'face 'corfu-bar))
                         (concat
                          (make-string (- margin-right-width bar-width) ? )
                          (propertize (make-string bar-width ? ) 'face
                                      'corfu-bar)))))
         (margin-left (when (< 0 margin-left-width)
                        (if (display-graphic-p)
                            (propertize " " 'display
                                        `(space
                                          :width (,margin-left-width)))
                          (make-string margin-left-width ? ))))
         (margin-right (when (< 0 margin-right-width)
                         (if (display-graphic-p)
                             (propertize " " 'display
                                         `(space
                                           :width (,margin-right-width)))
                           (make-string margin-right-width ? ))))
         (popon-pos (if (equal (cdr corfu-popup--last-position)
                               (list pos (window-start)
                                     (buffer-modified-tick)))
                        (car corfu-popup--last-position)
                      (let ((pos (popon-x-y-at-pos pos)))
                        (cons (max 0 (- (car pos) off))
                              (if (and (< (floor (window-screen-lines))
                                          (+ (cdr pos) (length lines)))
                                       (>= (cdr pos) 8))
                                  (- (cdr pos) 8)
                                (1+ (cdr pos))))))))
    (setq corfu-popup--last-position
          (list popon-pos pos (window-start) (buffer-modified-tick)))
    (setq corfu-popup--popon
          (popon-create
           (cons
            (string-join
             (seq-map-indexed
              (lambda (line line-number)
                (let ((str (concat
                            margin-left line
                            (make-string (- width (string-width line)) ? )
                            (if (and lo (<= lo line-number (+ lo bar)))
                                scroll-bar
                              margin-right))))
                  (add-face-text-property 0 (length str)
                                          (if (eq line-number curr)
                                              'corfu-current
                                            'corfu-default)
                                          t str)
                  str))
              lines)
             "\n")
            (if (display-graphic-p)
                (+ width (round (/ (+ margin-left-width margin-right-width)
                                   (frame-char-width))))
              (+ width margin-left-width margin-right-width)))
           popon-pos))
    nil))

;; NOTE: Just to remove the hardcoded `display-graphic-p' call.
(defun corfu-popup--auto-post-command ()
  "Post command hook which initiates auto completion."
  (when corfu--auto-timer
    (cancel-timer corfu--auto-timer)
    (setq corfu--auto-timer nil))
  (when (and (not completion-in-region-mode)
             (not defining-kbd-macro)
             (corfu--match-symbol-p corfu-auto-commands this-command))
    (setq corfu--auto-timer
          (run-at-time corfu-auto-delay nil
                       #'corfu--auto-complete (corfu--auto-tick)))))

;; NOTE: Just to remove the hardcoded `display-graphic-p' call.
(defun corfu-popup--in-region (beg end table &optional pred)
  "Corfu completion in region function.
See `completion-in-region' for the arguments BEG, END, TABLE, PRED."
  (barf-if-buffer-read-only)
  (when completion-in-region-mode (corfu-quit))
  (let* ((pt (max 0 (- (point) beg)))
         (str (buffer-substring-no-properties beg end))
         (before (substring str 0 pt))
         (metadata (completion-metadata before table pred))
         (exit (plist-get completion-extra-properties :exit-function))
         (threshold (completion--cycle-threshold metadata))
         (completion-in-region-mode-predicate
          (or completion-in-region-mode-predicate (lambda () t))))
    (pcase (completion-try-completion str table pred pt metadata)
      ('nil (corfu--message "No match") nil)
      ('t
       (goto-char end)
       (corfu--message "Sole match")
       (when exit (funcall exit str 'finished))
       t)
      (`(,newstr . ,newpt)
       (pcase-let ((`(,base ,candidates ,total . ,_)
                    (corfu--recompute-candidates str pt table pred)))
         (setq beg (copy-marker beg)
               end (copy-marker end t)
               completion-in-region--data (list beg end table pred))
         (unless (equal str newstr)
           (completion--replace beg end (concat newstr)))
         (goto-char (+ beg newpt))
         (if (= total 1)
             (when exit
               (funcall exit newstr
                        (if (eq (try-completion (car candidates) table pred) t)
                            'finished 'exact)))
           (if (not (and threshold (or (eq threshold t) (>= threshold total))))
               (corfu--setup)
             (corfu--cycle-candidates total candidates (+ base beg) end)
             (unless (equal (completion-boundaries
                             (buffer-substring-no-properties beg end)
                             table pred "") '(0 . 0))
               (corfu--setup)))))
       t))))

(define-minor-mode corfu-popup-mode
  "Corfu popup on terminal."
  nil nil nil
  :global t
  (if corfu-popup-mode
      (progn
        (advice-add #'corfu--popup-show :override
                    #'corfu-popup--popup-show)
        (advice-add #'corfu--popup-hide :override
                    #'corfu-popup--popup-hide)
        (advice-add #'corfu--auto-post-command :override
                    #'corfu-popup--auto-post-command)
        (advice-add #'corfu--in-region :override
                    #'corfu-popup--in-region))
    (advice-remove #'corfu--popup-show #'corfu-popup--popup-show)
    (advice-remove #'corfu--popup-hide #'corfu-popup--popup-hide)
    (advice-remove #'corfu--auto-post-command #'corfu-popup--auto-post-command)
    (advice-remove #'corfu--in-region #'corfu-popup--in-region)))

(provide 'corfu-popup)
;;; corfu-popup.el ends here
