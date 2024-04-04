import os
from typing import Optional
from models.users import User, Username
import yaml


class DoesNotExistException(Exception):
    pass

class Repository:
    def __init__(self, base_path: str) -> None:
        self._base_path = os.path.abspath(base_path)
        if not os.path.exists(self._base_path):
            raise Exception(f"{self._base_path} does not exist")

        self._users: dict[Username, User] = {}

    @property
    def _users_path(self) -> str:
        return os.path.join(self._base_path, "users/")

    def _ensure_users_path(self) -> None:
        os.makedirs(self._users_path, exist_ok=True)

    def _user_path(self, *, username: Username) -> str:
        return os.path.join(self._users_path, username + ".yaml")

    def load_user(self, *, username: Username) -> User:
        raise NotImplementedError

    def get_user(self, *, username: Username) -> User:
        raise NotImplementedError

    def create_user(self, *, user: User) -> None:
        if os.path.exists(self._user_path(username=user.username)):
            raise Exception(f"This user already exists: {self.load_user(username=user.username)}")

        self._ensure_users_path()

        with open(self._user_path(username=user.username), "wt", encoding="utf-8") as f:
            user_dict = user.dict()
            for field in ("password_salt", "encrypted_password"):
                user_dict[field] = user_dict[field].hex()
            yaml.dump(user_dict, f)

        self._cache_user(user=user)

    def _cache_user(self, *, user: User) -> None:
        self._users[user.username] = user


    def update_user(self, *, user: User) -> None:
        raise NotImplementedError
