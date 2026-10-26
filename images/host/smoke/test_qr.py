# Run by verify.sh beside test_xdist.py. segno and zxing-cpp are pinned so a
# consumer can check its own QR encoder against an independent encoder and an
# independent decoder, so the two are made to agree with each other here: segno
# encodes a string, zxing-cpp reads it back out of the pixels. An import alone
# would not do for zxing-cpp - its native part is what a wheel built for the wrong
# platform breaks, and only a decode runs it. The pixels go in as a memoryview of
# one byte per pixel, the way the consumer passes its screen snapshots, so neither
# numpy nor Pillow is needed - and neither is in this image.
import segno
import zxingcpp

TEXT = "WIFI:S:jethome-dev;T:WPA;P:smoke-check;;"


def test_segno_encodes_what_zxing_cpp_reads() -> None:
    rows = list(segno.make_qr(TEXT).matrix_iter(scale=4, border=4))
    width, height = len(rows[0]), len(rows)
    pixels = bytes(0 if dark else 255 for row in rows for dark in row)
    image = memoryview(pixels).cast("B", (height, width))
    found = [b.text for b in zxingcpp.read_barcodes(
        image, formats=zxingcpp.BarcodeFormat.QRCode)]
    assert found == [TEXT], found
