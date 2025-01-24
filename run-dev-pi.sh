#! /bin/bash

# for use on a raspberry pi for local development. maybe other environments
# too.

set -e

trap cleanup INT

cd village_py/village

poetry run -- gunicorn -w 4 -k gevent -b 0.0.0.0:5000 --access-logfile - --reload app:app &
MAIN_PID=$!
echo "Started main server with PID $MAIN_PID"

poetry run -- gunicorn -w 1 -k sync -b 127.0.0.1:54321 --access-logfile - --reload chat_server:chat_app &
CHAT_PID=$!
echo "Started the chat server with PID $CHAT_PID"

cleanup() {
	echo "Cleaning up..."

	if kill -0 $MAIN_PID 2>/dev/null; then
		echo "Stopping main server..."
		kill -SIGINT $MAIN_PID
		wait $MAIN_PID
	fi

	if kill -0 $CHAT_PID 2>/dev/null; then
		echo "Stopping chat server..."
		kill -SIGINT $CHAT_PID
		wait $CHAT_PID
	fi

	echo "All Processes stopped."
	exit 0
}

while true; do
	if ! kill -0 $MAIN_PID 2>/dev/null; then
		echo "Main server has exited unexpectedly."
		cleanup
	fi

	if ! kill -0 $CHAT_PID 2>/dev/null; then
		echo "Chat server has exited unexpectedly."
		cleanup
	fi

	sleep 1
done
