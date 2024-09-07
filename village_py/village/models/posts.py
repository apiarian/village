from typing import NewType
from datetime import datetime
from village.models.users import Username
from pydantic import BaseModel


PostID = NewType("PostID", str)


class Post(BaseModel):
    id: PostID
    author: Username
    timestamp: datetime
    title: str
    context: list[PostID]
    upload_filename: str | None
