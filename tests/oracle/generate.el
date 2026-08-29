;;; generate.el --- emit artist.nvim oracle fixtures -*- lexical-binding: t -*-

(require 'json)
(load-file (expand-file-name "artist.el" default-directory))

(defun artist-nvim--buffer-lines ()
  (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n" t))

(defun artist-nvim--case (name operation artist-operation from to &optional variables)
  (with-temp-buffer
    (artist-mode 1)
    (dolist (binding variables)
      (set (make-local-variable (car binding)) (cdr binding)))
    (funcall artist-operation
             (1- (cadr from)) (1- (car from))
             (1- (cadr to)) (1- (car to)))
    (prog1 `((name . ,name)
             (operation . ,operation)
             (from . ,(vconcat from))
             (to . ,(vconcat to))
             (lines . ,(vconcat (artist-nvim--buffer-lines))))
      (artist-mode -1))))

(let ((fixtures
       (list
        (artist-nvim--case "horizontal" "line" 'artist-draw-line '(1 1) '(1 5))
        (artist-nvim--case "vertical" "line" 'artist-draw-line '(1 1) '(3 1))
        (artist-nvim--case "shallow-octant" "line" 'artist-draw-line '(1 1) '(3 8))
        (artist-nvim--case "rectangle" "rectangle" 'artist-draw-rect '(1 1) '(3 5)))))
  (princ (json-encode fixtures))
  (terpri))

;;; generate.el ends here
