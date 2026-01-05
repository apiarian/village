import os

from village.models.posts import PostID
from village.models.user_history import UserHistory
from village.models.users import Username
from village.repositories.yaml_and_text import YAMLandText


class UserHistoryRepository(YAMLandText):
    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "user_history")

    def load(self, *, username: Username) -> UserHistory | None:
        if not os.path.exists(self._path_for_username(username=username)):
            return None

        return self._data_to_object(
            self._load_raw_data(full_path=self._path_for_username(username=username))
        )

    def upsert_context(
        self, *, username: Username, thread: PostID, context: list[PostID]
    ) -> None:
        user_history = self.load(username=username) or UserHistory(
            username=username, last_seen_context={}
        )

        user_history.last_seen_context[thread] = context[:]

        self.write(user_history=user_history)

    def write(self, *, user_history: UserHistory) -> None:
        self._write_data_and_content(
            full_path=self._path_for_username(username=user_history.username),
            data=self._object_to_data(user_history),
            content="",
        )

    def _data_to_object(self, data: dict) -> UserHistory:
        return UserHistory.model_validate(data)

    def _object_to_data(self, user_history: UserHistory) -> dict:
        d = user_history.dict()
        return d

    def _path_for_username(self, *, username: Username) -> str:
        return os.path.join(self.path, username + self.YAML_SUFFIX)
