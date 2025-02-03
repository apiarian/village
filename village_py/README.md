# village.py

A python implementation of the basic village webserver.

Since I'm currently most comfortable and productive in python, I figured I'd
hammer out a working skeleton of an app, and then explore other languages as
and when I can.

For now, in development, run the following in this directory:

```
gunicorn -w 4 -k gevent -b 127.0.0.1:5000 --access-logfile - app:app
```

We also need a *single threaded* internal chat server:

```
gunicorn -w 1 -k sync -b 127.0.0.1:54321 --access-logfile - chat_server:chat_app
```

# TODO:
- message attachments
- tags
- reactions
- figure out why we have a type issue with posts
