from datetime import datetime
from typing import Literal, NewType, Union

from pydantic import BaseModel

from village.models.users import Username

PostID = NewType("PostID", str)


class BasePost(BaseModel):
    id: PostID
    author: Username
    timestamp: datetime


class Message(BasePost):
    type: Literal["message"] = "message"
    title: str
    context: list[PostID]
    upload_filename: str | None


Post = Union[Message]
