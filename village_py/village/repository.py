import os
import uuid
from contextlib import contextmanager
from collections import defaultdict
from typing import Any, Literal, Optional, Tuple

import yaml

from village.models.users import User, Username
from village.repositories.users import UsersRepository
from village.repositories.users import UserDoesNotExistException
from village.repositories.uploads import UploadsRepository
from village.repositories.posts import PostsRepository


class DoesNotExistException(Exception):
    pass


class Repository:
    def __init__(self, base_path: str) -> None:
        self._base_path = os.path.abspath(base_path)
        if not os.path.exists(self._base_path):
            raise Exception(f"{self._base_path} does not exist")

        self.users = UsersRepository(self._base_path)
        self.uploads = UploadsRepository(self._base_path)
        self.posts = PostsRepository(self._base_path)
