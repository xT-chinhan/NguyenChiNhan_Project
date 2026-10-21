import base64
import io
import struct
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

from navcore.vision.images import (
    MAX_BASE64_CHARS,
    MAX_IMAGE_BYTES,
    ImageError,
    canonical_reference,
    decode_depth_png,
    decode_image,
    decode_ws_image,
    pixel_hash,
    validate_rgb,
)


def image_bytes(format="JPEG", size=(64, 32), *, orientation=None):
    pixels = np.zeros((size[1], size[0], 3), dtype=np.uint8)
    pixels[:, : size[0] // 2] = (210, 70, 10)
    pixels[:, size[0] // 2 :] = (20, 30, 190)
    image = Image.fromarray(pixels)
    kwargs = {}
    if orientation is not None:
        exif = Image.Exif()
        exif[274] = orientation
        kwargs["exif"] = exif
    output = io.BytesIO()
    image.save(output, format=format, **kwargs)
    return output.getvalue()


class ImagesTest(unittest.TestCase):
    def depth_bytes(self, pixels):
        buffer = io.BytesIO()
        Image.fromarray(pixels).save(buffer, format="PNG")
        return buffer.getvalue()

    def test_depth_preserves_true_16bit_grayscale_samples(self):
        pixels = np.zeros((32, 64), np.uint16)
        pixels[0, :6] = [0, 1, 255, 256, 1000, 65535]
        decoded = decode_depth_png(base64.b64encode(self.depth_bytes(pixels)).decode())
        self.assertEqual(decoded.dtype, np.uint16)
        self.assertTrue(decoded.flags.c_contiguous)
        self.assertFalse(decoded.flags.writeable)
        np.testing.assert_array_equal(decoded, pixels)

    def test_depth_rejects_8bit_color_truncated_and_oversized_headers(self):
        valid = self.depth_bytes(np.ones((32, 64), np.uint16))
        oversized = bytearray(valid)
        oversized[16:24] = struct.pack(">II", 100000, 100000)
        for data in (
            self.depth_bytes(np.ones((32, 64), np.uint8)),
            image_bytes("PNG"),
            image_bytes(),
            valid[:25],
            valid[:-15],
            bytes(oversized),
            b"x" * (MAX_IMAGE_BYTES + 1),
        ):
            with self.assertRaises(ImageError):
                decode_depth_png(base64.b64encode(data).decode())
        with self.assertRaises(ImageError):
            decode_depth_png("data:image/png;base64,abcd")

    def test_decode_is_canonical_and_ws_does_not_rotate(self):
        encoded = image_bytes(orientation=6)
        live = decode_ws_image(base64.b64encode(encoded).decode())
        admin = decode_image(encoded, admin=True)
        self.assertEqual(live.rgb.shape, (32, 64, 3))
        self.assertEqual(admin.rgb.shape, (64, 32, 3))
        np.testing.assert_array_equal(admin.rgb, np.rot90(live.rgb, k=3))
        self.assertEqual(live.rgb.dtype, np.uint8)
        self.assertTrue(live.rgb.flags.c_contiguous)
        self.assertFalse(live.rgb.flags.writeable)
        self.assertEqual(len(live.pixel_sha256), 64)

    def test_reference_uses_stored_jpeg_and_pre_jpeg_dedupe_hash(self):
        original = image_bytes("PNG", orientation=6)
        upload = decode_image(original, admin=True)
        reference = canonical_reference(original)
        self.assertEqual(reference.pixel_sha256, upload.pixel_sha256)
        np.testing.assert_array_equal(reference.rgb, decode_image(reference.jpeg_bytes).rgb)
        self.assertFalse(reference.rgb.flags.writeable)
        with Image.open(io.BytesIO(reference.jpeg_bytes)) as stored:
            self.assertEqual(stored.format, "JPEG")
            self.assertFalse(stored.getexif())

    def test_invalid_base64_and_payload_size(self):
        for value in (
            "",
            "data:image/jpeg;base64,xxx",
            "/etc/passwd",
            "https://x/image",
            "%%%%",
            "a\na",
            "é",
            "a" * (MAX_BASE64_CHARS + 1),
            None,
        ):
            with self.subTest(value=str(value)[:20]), self.assertRaises(ImageError):
                decode_ws_image(value)
        for data in (b"", b"x" * (MAX_IMAGE_BYTES + 1), b"not-an-image"):
            with self.assertRaises(ImageError):
                decode_image(data)

    def test_formats_dimensions_truncation_and_bomb(self):
        png = image_bytes("PNG")
        with self.assertRaises(ImageError):
            decode_image(png)
        self.assertEqual(decode_image(png, admin=True).rgb.shape, (32, 64, 3))
        for data in (
            image_bytes("GIF"),
            image_bytes(size=(1281, 32)),
            image_bytes(size=(64, 31)),
            image_bytes()[:-2],
            png[:-15],
        ):
            with self.assertRaises(ImageError):
                decode_image(data, admin=True)
        with patch.object(Image, "MAX_IMAGE_PIXELS", 1000), self.assertRaises(ImageError):
            decode_image(image_bytes())

    def test_animated_png_rejected(self):
        output = io.BytesIO()
        first = Image.new("RGB", (32, 32), "red")
        first.save(
            output,
            format="PNG",
            save_all=True,
            append_images=[Image.new("RGB", (32, 32), "blue")],
            duration=100,
        )
        with self.assertRaises(ImageError):
            decode_image(output.getvalue(), admin=True)

    def test_rgb_validation_and_hash_dimensions(self):
        rgb = np.zeros((32, 64, 3), np.uint8)
        self.assertNotEqual(pixel_hash(rgb), pixel_hash(rgb.reshape(64, 32, 3)))
        for invalid in (
            rgb.astype(np.float32),
            rgb[:, ::-1],
            rgb[:, :, 0],
            [],
            np.zeros((32, 32, 4), np.uint8),
        ):
            with self.assertRaises(ImageError):
                validate_rgb(invalid)


if __name__ == "__main__":
    unittest.main()
