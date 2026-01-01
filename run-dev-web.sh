#! /bin/bash

# for use on a web server with nginx backing it. maybe other environments too.

set -e

trap cleanup INT

cd village_py/village

poetry run -- gunicorn -w 4 -k gevent -b 127.0.0.1:5000 --access-logfile - --reload app:app &
MAIN_PID=$!
echo "Started main server with PID $MAIN_PID"

cleanup() {
	echo "Cleaning up..."

	if kill -0 $MAIN_PID 2>/dev/null; then
		echo "Stopping main server..."
		kill -SIGINT $MAIN_PID
		wait $MAIN_PID
	fi

	echo "All Processes stopped."
	exit 0
}

while true; do
	if ! kill -0 $MAIN_PID 2>/dev/null; then
		echo "Main server has exited unexpectedly."
		cleanup
	fi

	sleep 1
done

