from typing import Optional

from PIL.Image import Image, Resampling
from PIL.ImageOps import exif_transpose

PREVIEW_MAX_DIMENSION = 1000


def make_and_save_preview(img: Image, filename: str) -> None:
    preview, extra_frames = make_preview(img)

    with open(filename, "wb") as f:
        if extra_frames:
            preview.save(
                f, format=img.format, save_all=True, append_images=extra_frames
            )
        else:
            preview.save(f, format=img.format)


def make_preview(img: Image) -> tuple[Image, Optional[list[Image]]]:
    if not hasattr(img, "n_frames"):
        return _make_simple_preview(img), None

    else:
        return _make_multiframe_preview(img)


def _make_simple_preview(img: Image) -> Image:
    preview = exif_transpose(img, in_place=False)
    assert preview

    if (
        preview.width <= PREVIEW_MAX_DIMENSION
        and preview.height <= PREVIEW_MAX_DIMENSION
    ):
        return preview

    scale = 1.0
    if preview.width > preview.height:
        scale = 1.0 * PREVIEW_MAX_DIMENSION / preview.width
    else:
        scale = 1.0 * PREVIEW_MAX_DIMENSION / preview.height

    return preview.resize(
        (int(preview.width * scale), int(preview.height * scale)),
        resample=Resampling.LANCZOS,
    )


def _make_multiframe_preview(img: Image) -> tuple[Image, list[Image]]:
    preview = _make_simple_preview(img)

    extra_frames = []
    assert hasattr(img, "n_frames")
    for frame in range(1, img.n_frames):
        img.seek(frame)
        extra_frames.append(_make_simple_preview(img))

        if len(extra_frames) > 100:
            break

    return preview, extra_frames
