import os

from village.models.users import User, Username
from village.repositories.yaml_and_text import YAMLandText


class UserDoesNotExistException(Exception):
    pass


class UsersRepository(YAMLandText):
    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "users")

    def load_all(self) -> list[User]:
        return [self.load(username=username) for username in self._load_all_usernames()]

    def load(self, *, username: Username) -> User:
        self.must_exist(username=username)

        return self._data_to_object(
            self._load_raw_data(full_path=self._path_for_username(username=username))
        )

    def load_content(self, *, username: Username) -> str:
        self.must_exist(username=username)

        return self._load_raw_content(
            full_path=self._path_for_username(username=username),
        )

    def create_new(self, *, user: User) -> None:
        try:
            self.load(username=user.username)

            raise Exception(f"This user already exists: {user.username}")

        except UserDoesNotExistException:
            self.write(user=user, content="")

    def write(self, *, user: User, content: str) -> None:
        self._write_data_and_content(
            full_path=self._path_for_username(username=user.username),
            data=self._object_to_data(user),
            content=content,
        )

    def must_exist(self, *, username: Username) -> None:
        if not os.path.exists(self._path_for_username(username=username)):
            raise UserDoesNotExistException(f"{username} could not be found")

    def _path_for_username(self, *, username: Username) -> str:
        return os.path.join(self.path, username + self.YAML_SUFFIX)

    def _data_to_object(self, data: dict) -> User:
        return User.model_validate(data)

    def _object_to_data(self, user: User) -> dict:
        d = user.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d

    def _load_all_usernames(self) -> list[Username]:
        return [
            Username(username)
            for username, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self.path)
                if entry.is_file()
            )
        ]
