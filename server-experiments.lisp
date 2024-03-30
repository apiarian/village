(asdf:operate 'asdf:load-op 'sb-fastcgi)
(sb-fastcgi:load-libfcgi "/usr/lib64/libfcgi.so.0.0.0")

(defun wsgi-app (env start-response)
  (funcall start-response "200 OK" '(("X-author" . "Who?")
                                     ("Content-Type" . "text/html")))
  (list "ENV (show in alist format): <br>" env))

(defun run-app ()
  (sb-fastcgi:socket-server-threaded
    (sb-fastcgi:make-serve-function #'wsgi-app)
    :inet-addr "127.0.0.1"
    :port 9000))

(run-app)
