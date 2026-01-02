# run as `poetry run python -m village.scripts.initialize_repository`
import os

from village import our_calendar
from village.models.users import User
from village.repositories.users import UserDoesNotExistException
from village.repository import Repository


def main() -> None:
    repository = Repository(os.path.expanduser("~/test-repository"))

    try:
        repository.users.must_exist(username=our_calendar.CALENDAR_USERNAME)
    except UserDoesNotExistException:
        calendar_user = User.create_new_user(
            username=our_calendar.CALENDAR_USERNAME,
            display_name="Calendar Bot",
        )

        print(calendar_user)

        repository.users.create_new(user=calendar_user)


if __name__ == "__main__":
    main()
