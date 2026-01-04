# run as `poetry run python -m village.scripts.initialize_repository`
import os
from textwrap import dedent

import yaml

from village import our_calendar
from village.models.users import User
from village.repositories.users import UserDoesNotExistException
from village.repository import Repository


def main() -> None:
    repository = Repository.from_env()

    try:
        repository.users.must_exist(username=our_calendar.CALENDAR_USERNAME)
    except UserDoesNotExistException:
        calendar_user = User.create_new_user(
            username=our_calendar.CALENDAR_USERNAME,
            display_name="Calendar Bot",
        )

        print(calendar_user)

        repository.users.create_new(user=calendar_user)

    base_settings = {
        "admin_username": "al",
        "available_reactions": ["😀", "😟", "👍", "👎", "👀"],
        "display_timezone": "America/New_York",
    }

    if os.path.exists(repository.settings_file):
        with open(repository.settings_file, "rt") as f:
            settings = yaml.safe_load(f) or {}
    else:
        settings = base_settings

    for k, v in base_settings.items():
        if k not in settings:
            settings[k] = v

    with open(repository.settings_file, "wt") as f:
        yaml.dump(settings, f)

    if not os.path.exists(repository.public_about_file):
        with open(repository.public_about_file, "wt") as f:
            f.write(
                dedent(
                    """\
                    A place to hang out with friends on the internet.
                    """
                )
            )

    if not os.path.exists(repository.private_about_file):
        with open(repository.private_about_file, "wt") as f:
            f.write(
                dedent(
                    """\
                    # Code of Conduct
                    Don't be a jerk.
                    """
                )
            )


if __name__ == "__main__":
    main()
