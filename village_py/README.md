# village.py

A python implementation of the basic village webserver.

Since I'm currently most comfortable and productive in python, I figured I'd
hammer out a working skeleton of an app, and then explore other languages as
and when I can.

For now, in development, run the following in this directory:

```
gunicorn -w 4 -k gevent -b 127.0.0.1:5000 --access-logfile - app:app
```

There's a `run-dev-pi.sh` which helpfully handles all of that
correctly.

Here's a helpful bit of elisp to hup the main server's gunicorn
(useful when updating the "static" stuff like templates and css.)

```elisp
(defun hup-local-village ()
  (interactive)
  (let ((gunicorn-id
	 (string-trim (shell-command-to-string "ps -fC gunicorn | grep 5000 | awk '{print $2}'"))))
    (signal-process gunicorn-id 'HUP t)
    (message "Sent HUP to %s" gunicorn-id)))
	
(global-set-key (kbd "C-c v h") 'hup-local-village)
```

# TODO:
- switch from markdown to a smaller, more secure, subset
- calendar template
- thread permissions should probably be in the threads model
- multiple villages on the same app, probably using separate
  repositories
- emoji and timezone in a top level repository settings.yaml
- also include a code of conduct and about details that can be read
  from file instead of being hard-coded
- deploy for my gaming folks
