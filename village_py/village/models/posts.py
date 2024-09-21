from datetime import datetime
from typing import NewType

from pydantic import BaseModel

from village.models.users import Username

PostID = NewType("PostID", str)


class Post(BaseModel):
    id: PostID
    author: Username
    timestamp: datetime
    title: str
    context: list[PostID]
    upload_filename: str | None
