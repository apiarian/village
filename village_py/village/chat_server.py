import json
import os
import time
from typing import NamedTuple

from flask import Flask, jsonify, request

chat_app = Flask(__name__)
chat_app.secret_key = os.environ["CHAT_FLASK_SECRET_KEY"].encode("utf-8")


class Message(NamedTuple):
    timestamp_microseconds: int
    author: str
    message: str

    def as_dict(self) -> dict:
        return {
            "timestamp_microseconds": self.timestamp_microseconds,
            "author": self.author,
            "message": self.message,
        }


messages: list[Message] = [
    Message(
        timestamp_microseconds=int(time.time() * 1_000_000),
        author="test",
        message="some message",
    ),
]


@chat_app.route("/messages", methods=["GET"])
def list_messages():
    global messages

    try:
        since = int(request.args.get("since_microseconds"))
    except:
        since = 0

    return jsonify(
        [
            message.as_dict()
            for message in messages
            if message.timestamp_microseconds > since or True
        ]
    )


@chat_app.route("/add_message", methods=["POST"])
def add_message():
    global messages

    data = request.get_json()

    author = data["author"]
    message = data["message"]

    timestamp_microseconds = int(time.time() * 1_000_000)

    max_timestamp_microseconds = (
        max(message.timestamp_microseconds for message in messages) if messages else 0
    )
    if timestamp_microseconds <= max_timestamp_microseconds:
        raise Exception(
            f"timestamp issue: {timestamp_microseconds} for max {max_timestamp_microseconds}"
        )

    messages.append(
        Message(
            timestamp_microseconds=timestamp_microseconds,
            author=author,
            message=message,
        )
    )
    if len(messages) > 10:
        messages = messages[-10:]

    try:
        since = int(request.args.get("since_microseconds"))
    except:
        since = 0

    return jsonify(
        [
            message.as_dict()
            for message in messages
            if message.timestamp_microseconds > since
        ]
    )
