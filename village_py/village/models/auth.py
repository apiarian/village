import hashlib
import os

from pydantic import BaseModel, Field

from village.models.users import Username, UsernameField


class Auth(BaseModel):
    username: Username = UsernameField
    password_salt: bytes = Field(repr=False)
    encrypted_password: bytes = Field(repr=False)
    new_password_required: bool

    @classmethod
    def create_new_auth(cls, *, username: Username, password: str) -> "Auth":
        password_salt = cls._generate_salt()
        encrypted_password = cls._encrypt_password(
            password=password, salt=password_salt
        )

        return Auth(
            username=username,
            password_salt=password_salt,
            encrypted_password=encrypted_password,
            new_password_required=True,
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
