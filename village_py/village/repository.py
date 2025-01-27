import os

from village.repositories.auth import AuthRepository
from village.repositories.posts import PostsRepository
from village.repositories.uploads import UploadsRepository
from village.repositories.users import UsersRepository


class Repository:
    def __init__(self, base_path: str) -> None:
        self._base_path = os.path.abspath(base_path)
        if not os.path.exists(self._base_path):
            raise Exception(f"{self._base_path} does not exist")

        self.users = UsersRepository(self._base_path)
        self.auth = AuthRepository(self._base_path)
        self.uploads = UploadsRepository(self._base_path)
        self.posts = PostsRepository(self._base_path)
