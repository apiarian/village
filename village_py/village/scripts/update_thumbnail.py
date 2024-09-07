import os

from PIL import Image

from village.models.users import User, Username
from village.repository import Repository
from village.images.thumbnails import make_and_save_thumbnail


def main() -> None:
    repository = Repository(os.path.expanduser("~/test-repository"))

    username = Username(input("username: ").strip())

    user = repository.load_user(username=username)

    assert user.image_filename
    img = Image.open(repository.upload_path_for(filename=user.image_filename))
    img.load()
    print(img.size)

    _, extension = os.path.splitext(user.image_filename)
    new_thumbnail_filename = repository.new_upload_filename(suffix=extension)
    make_and_save_thumbnail(
        img, repository.upload_path_for(filename=new_thumbnail_filename)
    )

    user.image_thumbnail = new_thumbnail_filename
    print(new_thumbnail_filename)
    repository.update_user(user=user)


if __name__ == "__main__":
    main()
