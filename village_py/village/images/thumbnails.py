from typing import Optional
from PIL.Image import Image, Resampling
from PIL.ImageOps import exif_transpose

THUMBNAIL_SIZE = (64, 64)


def make_and_save_thumbnail(img: Image, filename: str) -> None:
    thumbnail, extra_frames = make_thumbnail(img)

    with open(filename, "wb") as f:
        if extra_frames:
            thumbnail.save(
                f, format=img.format, save_all=True, append_images=extra_frames
            )
        else:
            thumbnail.save(f, format=img.format)


def make_thumbnail(img: Image) -> tuple[Image, Optional[list[Image]]]:
    if not hasattr(img, "n_frames"):
        return _make_simple_thumbnail(img), None

    else:
        return _make_multiframe_thumbnail(img)


def _make_simple_thumbnail(img: Image) -> Image:
    thumbnail = exif_transpose(img, in_place=False)
    assert thumbnail

    square_dim = min(thumbnail.width, thumbnail.height)
    if thumbnail.width == square_dim and thumbnail.height == square_dim:
        left, right, top, bottom = 0, thumbnail.width, 0, thumbnail.height

    elif thumbnail.width == square_dim:
        left, right = 0, thumbnail.width

        extra = thumbnail.height - square_dim
        assert extra > 0
        half_extra = int(extra / 2)

        top, bottom = half_extra, thumbnail.height - extra + half_extra

    elif thumbnail.height == square_dim:
        top, bottom = 0, thumbnail.height

        extra = thumbnail.width - square_dim
        assert extra > 0
        half_extra = int(extra / 2)

        left, right = half_extra, thumbnail.width - extra + half_extra

    else:
        raise Exception("but how?")

    thumbnail = thumbnail.crop((left, top, right, bottom))

    thumbnail.thumbnail(THUMBNAIL_SIZE, resample=Resampling.LANCZOS)

    return thumbnail


def _make_multiframe_thumbnail(img: Image) -> tuple[Image, list[Image]]:
    thumbnail = _make_simple_thumbnail(img)

    extra_frames = []
    assert hasattr(img, "n_frames")
    for frame in range(1, img.n_frames):
        img.seek(frame)
        extra_frames.append(_make_simple_thumbnail(img))

        if len(extra_frames) > 1000:
            break

    return thumbnail, extra_frames
