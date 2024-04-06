import os
from typing import Optional, Any
from .models.users import User, Username
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
        if not self._user_exists_in_repository(username=username):
            raise DoesNotExistException(f"{username} could not be found")

        with open(self._user_path(username=username), "rt", encoding="utf-8") as f:
            data = yaml.full_load(f)

        for field in ("password_salt", "encrypted_password"):
            data[field] = bytes.fromhex(data[field])

        user = User.model_validate(data)

        self._cache_user(user=user)

        return user

    def get_user(self, *, username: Username) -> User:
        if username in self._users:
            return self._users[username]

        return self.load_user(username=username)

    def _user_exists_in_repository(self, *, username: Username) -> bool:
        return os.path.exists(self._user_path(username=username))

    def create_user(self, *, user: User) -> None:
        if self._user_exists_in_repository(username=user.username):
            raise Exception(
                f"This user already exists: {self.load_user(username=user.username)}"
            )

        self.update_user(user=user)

    def update_user(self, *, user: User) -> None:
        self._ensure_users_path()

        with open(self._user_path(username=user.username), "wt", encoding="utf-8") as f:
            yaml.dump(self._user_to_dict(user=user), f)

        self._cache_user(user=user)

    def _user_to_dict(self, *, user: User) -> dict[str, Any]:
        d = user.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d

    def _cache_user(self, *, user: User) -> None:
        self._users[user.username] = user
