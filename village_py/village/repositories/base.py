import os
import uuid


class FilesRepository:
    def __init__(self, base_path: str, suffix: str) -> None:
        self._path = os.path.abspath(os.path.join(base_path, suffix))

        self._ensure_path_exists()

    @property
    def path(self) -> str:
        return self._path

    def _ensure_path_exists(self) -> None:
        os.makedirs(self._path, exist_ok=True)

    def _full_path(self, *, filename: str) -> str:
        return os.path.join(self._path, filename)

    def _new_unique_filename(self, *, suffix: str) -> str:
        while True:
            filename = str(uuid.uuid4()) + suffix
            if not os.path.exists(self._full_path(filename=filename)):
                return filename
