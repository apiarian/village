import os
from getpass import getpass

from village.models.users import User, Username
from village.repository import Repository


def main() -> None:
    repository = Repository(os.path.expanduser("~/test-repository"))

    username = input("username: ")

    user = repository.users.load_user(username=Username(username))

    password = getpass("password: ")
    if not password:
        raise Exception("password must not be blank")

    confirm_password = getpass("confirm password: ")
    if password != confirm_password:
        raise Exception("passwords do not match")

    user._force_update_password(new_password=password)
    user.new_password_required = True

    repository.users.write_user(
        user=user, content=repository.users.load_user_content(username=user.username)
    )


if __name__ == "__main__":
    main()
