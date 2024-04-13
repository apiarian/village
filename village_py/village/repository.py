import os
from typing import Optional, Any, Tuple, Literal
from village.models.users import User, Username
import yaml
from contextlib import contextmanager


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

    @contextmanager
    def _open_user_file(
        self, *, username: Username, mode: Literal["rt"] | Literal["wt"]
    ):
        with open(self._user_path(username=username), mode, encoding="utf-8") as f:
            yield f

    def _user_exists_in_repository(self, *, username: Username) -> bool:
        return os.path.exists(self._user_path(username=username))

    def _user_must_exist(self, *, username: Username):
        if not self._user_exists_in_repository(username=username):
            raise DoesNotExistException(f"{username} could not be found")

    def load_user(self, *, username: Username) -> User:
        self._user_must_exist(username=username)

        with self._open_user_file(username=username, mode="rt") as f:
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
        self._user_must_exist(username=username)

        with self._open_user_file(username=username, mode="rt") as f:
            _, content = self._load_yaml_prefix_and_content(f)

            return content

    def _write_user(
        self, *, username: Username, user: User | None, content: str | None
    ) -> None:
        if self._user_exists_in_repository(username=username):
            with self._open_user_file(username=username, mode="rt") as f:
                current_data, current_content = self._load_yaml_prefix_and_content(f)
        else:
            current_data, current_content = None, None

        if user is not None:
            new_data: dict | None = self._user_to_dict(user=user)
        else:
            new_data = current_data

        if content is not None:
            new_content: str | None = content
        else:
            new_content = current_content

        if new_data is None or new_content is None:
            raise Exception(f"missing data or content: {new_data}; {new_content}")

        with self._open_user_file(username=username, mode="wt") as f:
            self._write_yaml_prefix_and_content(f=f, data=new_data, content=new_content)

    def create_user(self, *, user: User) -> None:
        if self._user_exists_in_repository(username=user.username):
            raise Exception(
                f"This user already exists: {self.load_user(username=user.username)}"
            )

        self._write_user(username=user.username, user=user, content="")
        self._cache_user(user=user)

    def update_user(self, *, user: User) -> None:
        self._ensure_users_path()

        self._write_user(username=user.username, user=user, content=None)
        self._cache_user(user=user)

    def update_user_content(self, *, username: Username, content: str) -> None:
        self._user_must_exist(username=username)

        self._write_user(username=username, user=None, content=content)

    def _user_to_dict(self, *, user: User) -> dict[str, Any]:
        d = user.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d

    def _cache_user(self, *, user: User) -> None:
        self._users[user.username] = user

    CONTENT_SEPARATOR = "------\n"

    def _load_yaml_prefix_and_content(self, f) -> Tuple[dict, str]:
        yaml_lines: list[str] = []
        content_lines: list[str] = []
        care_about_separator = True

        target = yaml_lines
        for line in f:
            if care_about_separator and line == self.CONTENT_SEPARATOR:
                target = content_lines
                care_about_separator = False
                continue
            target.append(line)

        return yaml.full_load("".join(yaml_lines)), "".join(content_lines)

    def _write_yaml_prefix_and_content(self, *, f, data: dict, content: str):
        yaml.dump(data, f)

        f.write(self.CONTENT_SEPARATOR)
        f.write(content)
