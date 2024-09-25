import os
import time
import json
from flask import Flask, request, jsonify

chat_app = Flask(__name__)
chat_app.secret_key = os.environ["CHAT_FLASK_SECRET_KEY"].encode("utf-8")


messages: list[str] = []

@chat_app.route("/messages", methods=["GET"])
def list_messages():
    global messages

    return jsonify(messages)


@chat_app.route("/add_message", methods=["POST"])
def add_message():
    global messages

    message = request.get_json()["message"]

    messages.append(message)
    if len(messages) > 10:
        messages = messages[-10:]

    return jsonify({"result": "ok"})
