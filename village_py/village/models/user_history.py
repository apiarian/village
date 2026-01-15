from pydantic import BaseModel

from village.models.posts import PostID
from village.models.users import Username, UsernameField


class UserHistory(BaseModel):
    username: Username = UsernameField
    last_seen_context: dict[PostID, list[PostID]]
