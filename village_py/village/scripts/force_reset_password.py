import os
from getpass import getpass

from village.models.users import User, Username
from village.repository import Repository


def main() -> None:
    repository = Repository.from_env()

    username = input("username: ")

    auth = repository.auth.load(username=Username(username))

    password = getpass("password: ")
    if not password:
        raise Exception("password must not be blank")

    confirm_password = getpass("confirm password: ")
    if password != confirm_password:
        raise Exception("passwords do not match")

    auth._force_update_password(new_password=password)
    auth.new_password_required = True

    repository.auth.write(
        auth=auth, content=repository.auth.load_content(username=auth.username)
    )


if __name__ == "__main__":
    main()
