# run as `poetry run python -m scripts.create_user`

import os
from getpass import getpass
from village.models.users import User, Username
from village.repository import Repository


def main() -> None:
    repository = Repository(os.path.expanduser("~/test-repository"))

    username = input("username: ")
    display_name = input("display name: ")

    password = getpass("password: ")
    if not password:
        raise Exception("password must not be blank")

    confirm_password = getpass("confirm password: ")
    if password != confirm_password:
        raise Exception("passwords do not match")

    user = User.create_new_user(
        username=Username(username),
        display_name=display_name,
        password=password,
    )

    print(user)

    repository.create_user(user=user)


if __name__ == "__main__":
    main()
