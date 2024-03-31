(ql:quickload "hunchentoot")

(defvar *acceptor* (make-instance 'hunchentoot:easy-acceptor :port 4242))

(setf (hunchentoot:acceptor-document-root *acceptor*) "/var/www/village.megamicron.net/html/")

(hunchentoot:start *acceptor*)
(hunchentoot:stop *acceptor*)

(hunchentoot:define-easy-handler (say-yo :uri "/yo") (name)
  (setf (hunchentoot:content-type*) "text/plain")
  (format nil "Hey~@[ ~A~]!" name))
