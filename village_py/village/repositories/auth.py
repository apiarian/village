import os

from village.models.auth import Auth
from village.models.users import Username
from village.repositories.users import UserDoesNotExistException
from village.repositories.yaml_and_text import YAMLandText


class AuthRepository(YAMLandText):
    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "auth")

    def load(self, *, username: Username) -> Auth:
        self.must_exist(username=username)

        return self._data_to_object(
            self._load_raw_data(full_path=self._path_for_username(username=username))
        )

    def load_content(self, *, username: Username) -> str:
        self.must_exist(username=username)

        return self._load_raw_content(
            full_path=self._path_for_username(username=username),
        )

    def create_new(self, *, auth: Auth) -> None:
        try:
            self.load(username=auth.username)

            raise Exception(f"This user already exists: {auth.username}")

        except UserDoesNotExistException:
            self.write(auth=auth, content="")

    def write(self, *, auth: Auth, content: str) -> None:
        self._write_data_and_content(
            full_path=self._path_for_username(username=auth.username),
            data=self._object_to_data(auth),
            content=content,
        )

    def must_exist(self, *, username: Username) -> None:
        if not os.path.exists(self._path_for_username(username=username)):
            raise UserDoesNotExistException(f"{username} could not be found")

    def _path_for_username(self, *, username: Username) -> str:
        return os.path.join(self.path, username + self.YAML_SUFFIX)

    def _data_to_object(self, data: dict) -> Auth:
        for field in ("password_salt", "encrypted_password"):
            data[field] = bytes.fromhex(data[field])

        return Auth.model_validate(data)

    def _object_to_data(self, auth: Auth) -> dict:
        d = auth.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d
