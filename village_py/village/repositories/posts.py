import os
from collections import defaultdict

import yaml

from village.models.posts import Post, PostID
from village.repositories.yaml_and_text import YAMLandText


class PostsRepository(YAMLandText):
    def __init__(self, base_path: str) -> None:
        super().__init__(base_path, "posts")

    def new_post_id(self) -> PostID:
        filename = self._new_unique_filename(suffix=self.YAML_SUFFIX)

        return PostID(filename[: len(filename) - len(self.YAML_SUFFIX)])

    def create_post(self, *, post: Post, content: str) -> None:
        path = self._path_for_post(post_id=post.id)
        if os.path.exists(path):
            raise Exception("This post already exists")

        self._write_data_and_content(
            full_path=path,
            data=self._object_to_data(post),
            content=content,
        )

    def load_all_top_level_posts(self) -> list[Post]:
        return [p for p in self._all_posts().values() if not p.context]

    def load_post(self, *, post_id: PostID) -> Post:
        self._post_must_exist(post_id=post_id)

        return self._data_to_object(self._load_data(post_id=post_id))

    def load_post_content(self, *, post_id: PostID) -> str:
        self._post_must_exist(post_id=post_id)

        return self._load_content(post_id=post_id)

    def _load_data(self, *, post_id: PostID) -> dict:
        return self._load_raw_data(
            full_path=self._path_for_post(post_id=post_id),
        )

    def _load_content(self, *, post_id: PostID) -> str:
        return self._load_raw_content(
            full_path=self._path_for_post(post_id=post_id),
        )

    def _path_for_post(self, *, post_id: PostID) -> str:
        return os.path.join(self.path, post_id + self.YAML_SUFFIX)

    def _data_to_object(self, data: dict) -> Post:
        return Post.model_validate(data)

    def _object_to_data(self, post: Post) -> dict:
        return post.dict()

    def _post_must_exist(self, *, post_id: PostID):
        if not os.path.exists(self._path_for_post(post_id=post_id)):
            raise Exception(f"{post_id} could not be found")

    def _all_posts(self) -> dict[PostID, Post]:
        return {
            p.id: p
            for p in (
                self.load_post(post_id=post_id) for post_id in self._all_post_ids()
            )
        }

    def _all_post_ids(self) -> list[PostID]:
        return [
            PostID(post_id)
            for post_id, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self.path)
                if entry.is_file()
            )
        ]

    def load_posts(self, *, top_post_id: PostID) -> list[Post]:
        all_posts = self._all_posts()

        post_backlinks: dict[PostID, set[PostID]] = defaultdict(set)

        for post in all_posts.values():
            for context_id in post.context:
                post_backlinks[context_id].add(post.id)

        sorted_post_backlinks = {
            parent_post_id: sorted(
                backlink_ids, key=lambda post_id: all_posts[post_id].timestamp
            )
            for parent_post_id, backlink_ids in post_backlinks.items()
        }

        related_post_ids = []
        posts_to_check = [top_post_id]
        while posts_to_check:
            post_id = posts_to_check.pop(0)
            if post_id not in related_post_ids:
                related_post_ids.append(post_id)
            for post_backlink_id in sorted_post_backlinks.get(post_id, []):
                posts_to_check.append(post_backlink_id)

        return list(all_posts[post_id] for post_id in related_post_ids)
