import os
import uuid
from contextlib import contextmanager
from collections import defaultdict
from typing import Any, Literal, Optional, Tuple

import yaml

from village.models.users import User, Username
from village.models.posts import Post, PostID


class DoesNotExistException(Exception):
    pass


class Repository:
    def __init__(self, base_path: str) -> None:
        self._base_path = os.path.abspath(base_path)
        if not os.path.exists(self._base_path):
            raise Exception(f"{self._base_path} does not exist")

        self._users: dict[Username, User] = {}
        self._posts: dict[PostID, Post] = {}

    @property
    def _users_path(self) -> str:
        return os.path.join(self._base_path, "users/")

    @property
    def uploads_path(self) -> str:
        return os.path.join(self._base_path, "uploads/")

    @property
    def _posts_path(self) -> str:
        return os.path.join(self._base_path, "posts/")

    def _ensure_users_path(self) -> None:
        os.makedirs(self._users_path, exist_ok=True)

    def _ensure_uploads_path(self) -> None:
        os.makedirs(self.uploads_path, exist_ok=True)

    def _ensure_posts_path(self) -> None:
        os.makedirs(self._posts_path, exist_ok=True)

    def _user_path(self, *, username: Username) -> str:
        return os.path.join(self._users_path, username + ".yaml")

    def upload_path_for(self, *, filename: str) -> str:
        return os.path.join(self.uploads_path, filename)

    def new_upload_filename(self, *, suffix: str) -> str:
        self._ensure_uploads_path()

        while True:
            filename = str(uuid.uuid4()) + suffix
            if not os.path.exists(self.upload_path_for(filename=filename)):
                return filename

    def new_post_id(self) -> PostID:
        self._ensure_posts_path()

        while True:
            post_id = PostID(str(uuid.uuid4()))
            if not self._post_exists_in_repository(post_id=post_id):
                return post_id

    @contextmanager
    def open_uploaded_file(self, *, filename: str, mode: Literal["rt"] | Literal["wt"]):
        with open(self.upload_path_for(filename=filename), mode) as f:
            yield f

    def load_all_users(self) -> list[User]:
        return [
            self.load_user(username=username) for username in self._load_all_usernames()
        ]

    def _load_all_usernames(self) -> list[Username]:
        return [
            Username(username)
            for username, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self._users_path)
                if entry.is_file()
            )
        ]

    @contextmanager
    def _open_user_file(
        self, *, username: Username, mode: Literal["rt"] | Literal["wt"]
    ):
        with open(self._user_path(username=username), mode, encoding="utf-8") as f:
            yield f

    def _user_exists_in_repository(self, *, username: Username) -> bool:
        return os.path.exists(self._user_path(username=username))

    def _user_must_exist(self, *, username: Username):
        if not self._user_exists_in_repository(username=username):
            raise DoesNotExistException(f"{username} could not be found")

    def load_user(self, *, username: Username) -> User:
        self._user_must_exist(username=username)

        with self._open_user_file(username=username, mode="rt") as f:
            data, _ = self._load_yaml_prefix_and_content(f)

        for field in ("password_salt", "encrypted_password"):
            data[field] = bytes.fromhex(data[field])

        user = User.model_validate(data)

        self._cache_user(user=user)

        return user

    def get_user(self, *, username: Username) -> User:
        if username in self._users:
            return self._users[username]

        return self.load_user(username=username)

    def load_user_content(self, *, username: Username) -> str:
        self._user_must_exist(username=username)

        with self._open_user_file(username=username, mode="rt") as f:
            _, content = self._load_yaml_prefix_and_content(f)

            return content

    def _write_user(
        self, *, username: Username, user: User | None, content: str | None
    ) -> None:
        if self._user_exists_in_repository(username=username):
            with self._open_user_file(username=username, mode="rt") as f:
                current_data, current_content = self._load_yaml_prefix_and_content(f)
        else:
            current_data, current_content = None, None

        if user is not None:
            new_data: dict | None = self._user_to_dict(user=user)
        else:
            new_data = current_data

        if content is not None:
            new_content: str | None = content
        else:
            new_content = current_content

        if new_data is None or new_content is None:
            raise Exception(f"missing data or content: {new_data}; {new_content}")

        with self._open_user_file(username=username, mode="wt") as f:
            self._write_yaml_prefix_and_content(f=f, data=new_data, content=new_content)

    def create_user(self, *, user: User) -> None:
        if self._user_exists_in_repository(username=user.username):
            raise Exception(
                f"This user already exists: {self.load_user(username=user.username)}"
            )

        self._write_user(username=user.username, user=user, content="")
        self._cache_user(user=user)

    def update_user(self, *, user: User) -> None:
        self._ensure_users_path()

        self._write_user(username=user.username, user=user, content=None)
        self._cache_user(user=user)

    def update_user_content(self, *, username: Username, content: str) -> None:
        self._user_must_exist(username=username)

        self._write_user(username=username, user=None, content=content)

    def _user_to_dict(self, *, user: User) -> dict[str, Any]:
        d = user.dict()
        for key, value in d.items():
            if isinstance(value, bytes):
                d[key] = value.hex()

        return d

    def _cache_user(self, *, user: User) -> None:
        self._users[user.username] = user

    CONTENT_SEPARATOR = "------\n"

    def _load_yaml_prefix_and_content(self, f) -> Tuple[dict, str]:
        yaml_lines: list[str] = []
        content_lines: list[str] = []
        care_about_separator = True

        target = yaml_lines
        for line in f:
            if care_about_separator and line == self.CONTENT_SEPARATOR:
                target = content_lines
                care_about_separator = False
                continue
            target.append(line)

        return yaml.full_load("".join(yaml_lines)), "".join(content_lines)

    def _write_yaml_prefix_and_content(self, *, f, data: dict, content: str):
        yaml.dump(data, f)

        f.write(self.CONTENT_SEPARATOR)
        f.write(content)

    def load_all_top_level_posts(self) -> list[Post]:
        self._populate_post_cache()

        return [
            p for p in self._posts.values()
            if not p.context
        ]

    def _populate_post_cache(self) -> None:
        self._posts = {
            p.id: p for p in (
                self.load_post(post_id=post_id)
                for post_id in self._load_all_post_ids()
            )
        }

    def _load_all_post_ids(self) -> list[PostID]:
        return [
            PostID(post_id)
            for post_id, _ in (
                os.path.splitext(os.path.basename(entry.name))
                for entry in os.scandir(self._posts_path)
                if entry.is_file()
            )
        ]

    def load_post(self, *, post_id: PostID) -> Post:
        self._post_must_exist(post_id=post_id)

        with self._open_post_file(post_id=post_id, mode="rt") as f:
            data, _ = self._load_yaml_prefix_and_content(f)

        post = Post.model_validate(data)

        return post

    @contextmanager
    def _open_post_file(
        self, *, post_id: PostID, mode: Literal["rt"] | Literal["wt"]
    ):
        with open(self._post_path(post_id=post_id), mode, encoding="utf-8") as f:
            yield f

    def _post_must_exist(self, *, post_id: PostID):
        if not self._post_exists_in_repository(post_id=post_id):
            raise DoesNotExistException(f"{post_id} could not be found")

    def _post_exists_in_repository(self, post_id: PostID) -> bool:
        return os.path.exists(self._post_path(post_id=post_id))

    def _post_path(self, post_id: PostID) -> str:
        return os.path.join(self._posts_path, post_id + ".yaml")

    def load_posts(self, top_post_id: PostID) -> list[Post]:
        self._populate_post_cache()

        return self._collect_post_tree(top_post_id=top_post_id)


    def _collect_post_tree(self, top_post_id: PostID) -> list[Post]:
        post_backlinks: dict[PostID, set[PostID]] = defaultdict(set)

        for post in self._posts.values():
            for context_id in post.context:
                post_backlinks[context_id].add(post.id)

        sorted_post_backlinks = {
            parent_post_id: sorted(
                backlink_ids,
                key=lambda post_id: self._posts[post_id].timestamp
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

        return list(self._posts[post_id] for post_id in related_post_ids)


    def load_post_content(self, *, post_id: PostID) -> str:
        self._post_must_exist(post_id=post_id)

        with self._open_post_file(post_id=post_id, mode="rt") as f:
            _, content = self._load_yaml_prefix_and_content(f)

            return content

    def create_post(self, *, post: Post, content: str) -> None:
        if self._post_exists_in_repository(post_id=post.id):
            raise Exception("This post already exists")

        with self._open_post_file(post_id=post.id, mode="wt") as f:
            self._write_yaml_prefix_and_content(f=f, data=self._post_to_dict(post=post), content=content)

    def _post_to_dict(self, *, post: Post) -> dict:
        d = post.dict()
        return d
