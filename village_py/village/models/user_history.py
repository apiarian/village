from pydantic import BaseModel, Field

from village.models.posts import PostID
from village.models.users import Username


class UserHistory(BaseModel):
    username: Username = Field(pattern=r"^[a-z0-9_]+$")
    last_seen_context: dict[PostID, list[PostID]]
