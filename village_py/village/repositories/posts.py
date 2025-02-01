import os
from collections import defaultdict

import yaml

from village.models.posts import Message, Post, PostID, ThreadVisibility
from village.repositories.yaml_and_text import YAMLandText


class PostsRepository(YAMLandText):
    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "posts")

    def new_post_id(self) -> PostID:
        filename = self._new_unique_filename(suffix=self.YAML_SUFFIX)

        return PostID(filename[: len(filename) - len(self.YAML_SUFFIX)])

    def create(self, *, post: Post, content: str) -> None:
        path = self._path_for_post(post_id=post.id)
        if os.path.exists(path):
            raise Exception("This post already exists")

        self._write_data_and_content(
            full_path=path,
            data=self._object_to_data(post),
            content=content,
        )

    def load(self, *, post_id: PostID) -> Post:
        self._post_must_exist(post_id=post_id)

        return self._data_to_object(
            self._load_raw_data(
                full_path=self._path_for_post(post_id=post_id),
            )
        )

    def all_posts(self) -> dict[PostID, Post]:
        return {
            p.id: p
            for p in (self.load(post_id=post_id) for post_id in self._all_post_ids())
        }

    def load_content(self, *, post_id: PostID) -> str:
        self._post_must_exist(post_id=post_id)

        return self._load_raw_content(
            full_path=self._path_for_post(post_id=post_id),
        )

    def _path_for_post(self, *, post_id: PostID) -> str:
        return os.path.join(self.path, post_id + self.YAML_SUFFIX)

    def _data_to_object(self, data: dict) -> Post:
        type_map: dict[str, type[Post]] = {
            "message": Message,
            "thread_visibility": ThreadVisibility,
        }
        return type_map[data["type"]].model_validate(data)

    def _object_to_data(self, post: Post) -> dict:
        return post.dict()

    def _post_must_exist(self, *, post_id: PostID):
        if not os.path.exists(self._path_for_post(post_id=post_id)):
            raise Exception(f"{post_id} could not be found")

    def _all_post_ids(self) -> list[PostID]:
        return [
            PostID(post_id)
            for post_id, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self.path)
                if entry.is_file()
            )
        ]
