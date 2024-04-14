import hashlib
import os
from typing import NewType, Optional

from pydantic import BaseModel, Field

Username = NewType("Username", str)


class User(BaseModel):
    username: Username = Field(pattern=r"^[a-zA-Z0-9_]+$")
    display_name: str
    password_salt: bytes = Field(repr=False)
    encrypted_password: bytes = Field(repr=False)
    new_password_required: bool
    image_filename: str | None
    image_thumbnail: str | None

    @classmethod
    def create_new_user(
        cls, *, username: Username, display_name: str, password: str
    ) -> "User":
        password_salt = cls._generate_salt()
        encrypted_password = cls._encrypt_password(
            password=password, salt=password_salt
        )

        return User(
            username=username,
            display_name=display_name,
            password_salt=password_salt,
            encrypted_password=encrypted_password,
            new_password_required=True,
            image_filename=None,
            image_thumbnail=None,
        )

    def check_password(self, *, password: str) -> bool:
        return (
            self._encrypt_password(
                password=password,
                salt=self.password_salt,
            )
            == self.encrypted_password
        )

    def update_password(self, *, current_password: str, new_password: str):
        assert self.check_password(password=current_password)

        self._force_update_password(new_password=new_password)

    def _force_update_password(self, *, new_password: str):
        self.encrypted_password = self._encrypt_password(
            password=new_password,
            salt=self.password_salt,
        )

    @classmethod
    def _generate_salt(cls) -> bytes:
        return os.urandom(64)

    @classmethod
    def _encrypt_password(cls, *, password: str, salt: bytes) -> bytes:
        return hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=16384,
            r=8,
            p=1,
            dklen=32,
        )
