import os
import uuid
from contextlib import contextmanager

from village.repositories.base import FilesRepository


class UploadsRepository(FilesRepository):
    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "uploads")

    def full_path_for(self, *, filename: str) -> str:
        return os.path.join(self._path, filename)

    def new_filename(self, *, suffix: str) -> str:
        return self._new_unique_filename(suffix=suffix)
