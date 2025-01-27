from typing import NewType

from pydantic import BaseModel, Field

Username = NewType("Username", str)


class User(BaseModel):
    username: Username = Field(pattern=r"^[a-zA-Z0-9_]+$")
    display_name: str
    image_filename: str | None
    image_thumbnail: str | None

    @classmethod
    def create_new_user(
        cls,
        *,
        username: Username,
        display_name: str,
    ) -> "User":
        return User(
            username=username,
            display_name=display_name,
            image_filename=None,
            image_thumbnail=None,
        )
