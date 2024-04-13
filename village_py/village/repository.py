import os
from typing import Optional, Any, Tuple
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

    def load_all_users(self) -> list[User]:
        return [
            self.load_user(username=username) for username in self._load_all_usernames()
        ]

    def _load_all_usernames(self) -> list[Username]:
        return [
            Username(username)
            for username, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self._users_path)
                if entry.is_file()
            )
        ]

    def load_user(self, *, username: Username) -> User:
        if not self._user_exists_in_repository(username=username):
            raise DoesNotExistException(f"{username} could not be found")

        with open(self._user_path(username=username), "rt", encoding="utf-8") as f:
            data, _ = self._load_yaml_prefix_and_content(f)

        for field in ("password_salt", "encrypted_password"):
            data[field] = bytes.fromhex(data[field])

        user = User.model_validate(data)

        self._cache_user(user=user)

        return user

    def get_user(self, *, username: Username) -> User:
        if username in self._users:
            return self._users[username]

        return self.load_user(username=username)

    def load_user_content(self, *, username: Username) -> str:
        if not self._user_exists_in_repository(username=username):
            raise DoesNotExistException(f"{username} could not be found")

        with open(self._user_path(username=username), "rt", encoding="utf-8") as f:
            _, content = self._load_yaml_prefix_and_content(f)

            return content

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

        if self._user_exists_in_repository(username=user.username):
            with open(self._user_path(username=user.username), "rt", encoding="utf-8") as f:
                _, content = self._load_yaml_prefix_and_content(f)
        else:
            content = ""

        with open(self._user_path(username=user.username), "wt", encoding="utf-8") as f:
            self._write_yaml_prefix_and_content(f=f, data=self._user_to_dict(user=user), content=content)

        self._cache_user(user=user)

    def update_user_content(self, *, username: Username, content: str) -> None:
        self._ensure_users_path()

        if not self._user_exists_in_repository(username=username):
            raise Exception("This user does not exist yet: {username}")

        with open(self._user_path(username=username), "rt", encoding="utf-8") as f:
            data, _ = self._load_yaml_prefix_and_content(f)

        with open(self._user_path(username=username), "wt", encoding="utf-8") as f:
            self._write_yaml_prefix_and_content(f=f, data=data, content=content)

    def _user_to_dict(self, *, user: User) -> dict[str, Any]:
        d = user.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d

    def _cache_user(self, *, user: User) -> None:
        self._users[user.username] = user

    def _load_yaml_prefix_and_content(self, f) -> Tuple[dict, str]:
        yaml_lines: list[str] = []
        content_lines: list[str] = []
        care_about_separator = True

        target = yaml_lines
        for line in f:
            if care_about_separator and line == "------\n":
                target = content_lines
                care_about_separator = False
                continue
            target.append(line)

        return yaml.full_load("".join(yaml_lines)), "".join(content_lines)

    def _write_yaml_prefix_and_content(self, *, f, data: dict, content: str):
        yaml.dump(data, f)

        f.write("------\n")
        f.write(content)
