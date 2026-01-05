from pydantic import BaseModel

from village.models.posts import PostID
from village.models.users import Username


class UserHistory(BaseModel):
    username: Username
    last_seen_context: dict[PostID, list[PostID]]
