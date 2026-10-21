"""Bounded image decoding shared by live frames and reference uploads."""

import base64
import binascii
import hashlib
import io
import struct
import warnings
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageOps

MAX_IMAGE_BYTES = 393_216
MAX_BASE64_CHARS = 524_288
MAX_PIXELS = 921_600


class ImageError(ValueError):
    """Invalid or unsupported image, with a payload-free error message."""


@dataclass(frozen=True)
class DecodedImage:
    rgb: np.ndarray
    pixel_sha256: str


@dataclass(frozen=True)
class ReferenceImage:
    jpeg_bytes: bytes
    rgb: np.ndarray
    pixel_sha256: str


def _dimensions(width: int, height: int) -> None:
    if not (32 <= width <= 1280 and 32 <= height <= 720 and width * height <= MAX_PIXELS):
        raise ImageError("Invalid image dimensions")


def validate_rgb(rgb: np.ndarray) -> None:
    if (
        not isinstance(rgb, np.ndarray)
        or rgb.dtype != np.uint8
        or rgb.ndim != 3
        or rgb.shape[2] != 3
        or not rgb.flags.c_contiguous
    ):
        raise ImageError("Expected contiguous RGB uint8 pixels")
    _dimensions(rgb.shape[1], rgb.shape[0])


def pixel_hash(rgb: np.ndarray) -> str:
    validate_rgb(rgb)
    digest = hashlib.sha256(struct.pack(">II", rgb.shape[1], rgb.shape[0]))
    digest.update(memoryview(rgb))
    return digest.hexdigest()


def decode_image(data: bytes, *, admin: bool = False) -> DecodedImage:
    if not isinstance(data, bytes) or not 0 < len(data) <= MAX_IMAGE_BYTES:
        raise ImageError("Invalid image byte size")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as header:
                if header.format not in ({"JPEG", "PNG"} if admin else {"JPEG"}):
                    raise ImageError("Unsupported image format")
                _dimensions(*header.size)
                if getattr(header, "is_animated", False) or getattr(header, "n_frames", 1) != 1:
                    raise ImageError("Animated images are not supported")
                if header.format == "JPEG" and not data.endswith(b"\xff\xd9"):
                    raise ImageError("Truncated image")
                header.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                if admin:
                    image = ImageOps.exif_transpose(image)
                _dimensions(*image.size)
                rgb = np.array(image.convert("RGB"), dtype=np.uint8, order="C", copy=True)
        rgb.setflags(write=False)
        return DecodedImage(rgb, pixel_hash(rgb))
    except ImageError:
        raise
    except (
        OSError,
        ValueError,
        SyntaxError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        raise ImageError("Invalid image") from None


def _base64_bytes(value: str) -> bytes:
    if not isinstance(value, str) or not 0 < len(value) <= MAX_BASE64_CHARS:
        raise ImageError("Invalid base64 image size")
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        raise ImageError("Invalid base64 image") from None
    if not 0 < len(data) <= MAX_IMAGE_BYTES:
        raise ImageError("Invalid image byte size")
    return data


def decode_ws_image(image_b64: str) -> DecodedImage:
    return decode_image(_base64_bytes(image_b64))


def decode_depth_png(png_b64: str) -> np.ndarray:
    data = _base64_bytes(png_b64)
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[8:16] != b"\x00\x00\x00\x0dIHDR":
        raise ImageError("Invalid depth PNG header")
    width, height, bits, color, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", data[16:29]
    )
    _dimensions(width, height)
    if bits != 16 or color != 0 or compression != 0 or filtering != 0 or interlace not in {0, 1}:
        raise ImageError("Depth requires a 16-bit grayscale PNG")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as header:
                if header.format != "PNG" or getattr(header, "n_frames", 1) != 1:
                    raise ImageError("Invalid depth PNG")
                header.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                pixels = np.asarray(image)
                if (
                    pixels.shape != (height, width)
                    or pixels.dtype.kind not in "ui"
                    or pixels.dtype.itemsize < 2
                    or pixels.min() < 0
                    or pixels.max() > 65535
                ):
                    raise ImageError("Invalid depth pixels")
                # Pillow may expose true 16-bit grayscale PNG as signed int32; cast losslessly.
                depth = np.array(pixels, dtype=np.uint16, order="C", copy=True)
        depth.setflags(write=False)
        return depth
    except ImageError:
        raise
    except (
        OSError,
        ValueError,
        SyntaxError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        raise ImageError("Invalid depth PNG") from None


def canonical_reference(data: bytes) -> ReferenceImage:
    decoded = decode_image(data, admin=True)
    buffer = io.BytesIO()
    Image.fromarray(decoded.rgb).save(buffer, format="JPEG", quality=90, exif=b"")
    jpeg = buffer.getvalue()
    stored = decode_image(jpeg)
    # The dedupe hash describes upload pixels; inference uses the exact stored JPEG.
    return ReferenceImage(jpeg, stored.rgb, decoded.pixel_sha256)
