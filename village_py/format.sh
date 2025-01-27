#! /bin/bash

set -xe

poetry run -- mypy .
poetry run -- isort .
poetry run -- black .
