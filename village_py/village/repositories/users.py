import os
import yaml
from village.models.users import User, Username

from village.repositories.base import FilesRepository


class UserDoesNotExistException(Exception):
    pass


class UsersRepository(FilesRepository):
    YAML_SUFFIX = ".yaml"

    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "users")

    def load_all_users(self) -> list[User]:
        return [
            self.load_user(username=username) for username in self._load_all_usernames()
        ]

    def _load_all_usernames(self) -> list[Username]:
        return [
            Username(username)
            for username, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self.path)
                if entry.is_file()
            )
        ]

    def load_user(self, *, username: Username) -> User:
        self.must_exist(username=username)

        return self._data_to_object(self._load_data(username=username))

    def load_user_content(self, *, username: Username) -> str:
        self.must_exist(username=username)

        return self._load_content(username=username)

    def create_new_user(self, *, user: User) -> None:
        self._ensure_path_exists()

        try:
            self.load_user(username=user.username)
        except UserDoesNotExistException:
            self.write_user(user=user, content="")

        raise Exception(
            f"This user already exists: {self.load_user(username=user.username)}"
        )

    def write_user(self, *, user: User, content: str) -> None:
        self._ensure_path_exists()

        with open(self._path_for_username(username=user.username), "wt") as f:
            yaml.dump(self._object_to_data(user), f)

            f.write(self.CONTENT_SEPARATOR)

            f.write(content)

    def _load_content(self, *, username: Username) -> str:
        with open(self._path_for_username(username=username), "rt") as f:
            for line in f:
                if line == self.CONTENT_SEPARATOR:
                    break

            return "".join(f)

    def must_exist(self, *, username: Username) -> None:
        if not os.path.exists(self._path_for_username(username=username)):
            raise UserDoesNotExistException(f"{username} could not be found")

    def _path_for_username(self, *, username: Username) -> str:
        return os.path.join(self.path, username + self.YAML_SUFFIX)

    CONTENT_SEPARATOR = "------\n"

    def _load_data(self, *, username: Username) -> dict:
        with open(self._path_for_username(username=username), "rt") as f:
            yaml_lines = []
            for line in f:
                if line == self.CONTENT_SEPARATOR:
                    break
                yaml_lines.append(line)

            return yaml.full_load("".join(yaml_lines))

    def _data_to_object(self, data: dict) -> User:
        for field in ("password_salt", "encrypted_password"):
            data[field] = bytes.fromhex(data[field])

        return User.model_validate(data)

    def _object_to_data(self, user: User) -> dict:
        d = user.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d
