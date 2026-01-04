import os

from PIL import Image

from village.images.thumbnails import make_and_save_thumbnail
from village.models.users import User, Username
from village.repository import Repository


def main() -> None:
    repository = Repository.from_env()

    username = Username(input("username: ").strip())

    user = repository.users.load(username=username)

    assert user.image_filename
    img = Image.open(repository.uploads.full_path_for(filename=user.image_filename))
    img.load()
    print(img.size)

    _, extension = os.path.splitext(user.image_filename)
    new_thumbnail_filename = repository.uploads.new_filename(suffix=extension)
    make_and_save_thumbnail(
        img, repository.uploads.full_path_for(filename=new_thumbnail_filename)
    )

    user.image_thumbnail = new_thumbnail_filename
    print(new_thumbnail_filename)
    repository.users.write(
        user=user, content=repository.users.load_content(username=user.username)
    )


if __name__ == "__main__":
    main()
