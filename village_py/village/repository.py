import os
import uuid
from zoneinfo import ZoneInfo

import yaml

from village.models.users import Username
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

    def user_calendar_uuid(self, username: Username) -> str:
        user_calendar_uuids_file = os.path.join(
            self._base_path, "user_calendar_uuids.yaml"
        )
        if os.path.exists(user_calendar_uuids_file):
            with open(user_calendar_uuids_file, "rt") as f:
                user_calendar_uuids = yaml.full_load(f) or {}
        else:
            user_calendar_uuids = {}

        if username not in user_calendar_uuids:
            user_calendar_uuids[username] = str(uuid.uuid4())

            with open(user_calendar_uuids_file, "wt") as f:
                yaml.dump(user_calendar_uuids, f)

        return user_calendar_uuids[username]

    def user_calendar_uuid_exists(self, user_calendar_uuid: str) -> bool:
        user_calendar_uuids_file = os.path.join(
            self._base_path, "user_calendar_uuids.yaml"
        )
        if not os.path.exists(user_calendar_uuids_file):
            return False
        with open(user_calendar_uuids_file, "rt") as f:
            user_calendar_uuids = yaml.full_load(f) or {}
            return user_calendar_uuid in user_calendar_uuids.values()

    @property
    def settings_file(self) -> str:
        return os.path.join(self._base_path, "settings.yaml")

    def available_reactions(self) -> list[str]:
        with open(self.settings_file, "rt") as f:
            settings = yaml.full_load(f)
            return settings["available_reactions"]

    def display_timezone(self) -> ZoneInfo:
        with open(self.settings_file, "rt") as f:
            settings = yaml.full_load(f)
            return ZoneInfo(settings["display_timezone"])
