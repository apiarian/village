import json
import os
import time
from typing import NamedTuple, List

from flask import Flask, jsonify, request

chat_app = Flask(__name__)
chat_app.secret_key = os.environ["CHAT_FLASK_SECRET_KEY"].encode("utf-8")


repository = os.path.expanduser("~/test-repository")


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


class MessageList:
    def __init__(self) -> None:
        self._count_limit = 100
        self._time_limit_microseconds = 1_000_000 * 60 * 60
        self._messages: List[Message] = []
        self._filename = os.path.join(repository, "messages.json")

    def all(self):
        yield from self._messages

    def max_timestamp_microseconds(self) -> int:
        if not self._messages:
            return 0

        return max(message.timestamp_microseconds for message in self._messages)

    def cleanup(self) -> None:
        if len(self._messages) > self._count_limit:
            self._messages = self._messages[-self._count_limit:]

        self._messages = [
            message
            for message in self._messages
            if message.timestamp_microseconds > (
                (time.time() * 1_000_000) - self._time_limit_microseconds
            )
        ]

    def append(self, message: Message) -> None:
        self._messages.append(message)
        self.cleanup()
        self.dump_to_file()

    def dump_to_file(self) -> None:
        with open(self._filename, "wt") as f:
            json.dump([m.as_dict() for m in self._messages], f)

    def load_from_file(self) -> None:
        if not os.path.exists(self._filename):
            return

        with open(self._filename, "rt") as f:
            for m in json.load(f):
                self.append(Message(**m))


messages = MessageList()
messages.load_from_file()


@chat_app.route("/messages", methods=["GET"])
def list_messages():
    global messages
    messages.cleanup()

    try:
        since = int(request.args.get("since_microseconds"))
    except:
        since = 0

    return jsonify(
        [
            message.as_dict()
            for message in messages.all()
            if message.timestamp_microseconds > since
        ]
    )


@chat_app.route("/add_message", methods=["POST"])
def add_message():
    global messages
    messages.cleanup()

    data = request.get_json()

    author = data["author"]
    message = data["message"]

    timestamp_microseconds = int(time.time() * 1_000_000)

    max_timestamp_microseconds = messages.max_timestamp_microseconds()
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

    try:
        since = int(request.args.get("since_microseconds"))
    except:
        since = 0

    return jsonify(
        [
            message.as_dict()
            for message in messages.all()
            if message.timestamp_microseconds > since
        ]
    )
