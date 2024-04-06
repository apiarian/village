import os
from getpass import getpass
from ..models.users import User, Username
from ..repository import Repository


def main() -> None:
    repository = Repository(os.path.expanduser("~/test-repository"))

    username = input("username: ")

    user = repository.load_user(username=Username(username))

    password = getpass("password: ")
    if not password:
        raise Exception("password must not be blank")

    confirm_password = getpass("confirm password: ")
    if password != confirm_password:
        raise Exception("passwords do not match")

    user._force_update_password(new_password=password)
    user.new_password_required = True

    repository.update_user(user=user)


if __name__ == "__main__":
    main()
