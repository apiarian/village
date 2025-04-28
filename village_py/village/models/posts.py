import os
from datetime import datetime
from enum import Enum
from typing import Literal, NewType, Union

from pydantic import BaseModel

from village.models.users import Username

PostID = NewType("PostID", str)


class BasePost(BaseModel):
    id: PostID
    author: Username
    timestamp: datetime
    context: list[PostID]


class Message(BasePost):
    type: Literal["message"] = "message"
    title: str
    upload_filename: str | None
    replaces: PostID | None

    def upload_is_image(self) -> bool:
        if not self.upload_filename:
            return False

        _, extension = os.path.splitext(self.upload_filename)
        return any(
            extension.endswith(suffix)
            for suffix in (
                "jpg",
                "jpeg",
                "gif",
                "png",
            )
        )


class ThreadVisibility(BasePost):
    type: Literal["thread_visibility"] = "thread_visibility"
    visible: bool


class ThreadScopeOption(Enum):
    LOCAL = "local"
    PUBLIC = "public"


class ThreadScope(BasePost):
    type: Literal["thread_scope"] = "thread_scope"
    scope: ThreadScopeOption


class ThreadTags(BasePost):
    type: Literal["thread_tags"] = "thread_tags"
    added_tags: list[str]
    removed_tags: list[str]


class Reactions(BasePost):
    type: Literal["reactions"] = "reactions"
    reacts_to: PostID
    added_reactions: list[str]
    removed_reactions: list[str]


Post = Union[Message, ThreadVisibility, ThreadScope, ThreadTags, Reactions]
