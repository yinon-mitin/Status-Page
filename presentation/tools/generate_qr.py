"""Regenerate the local, high-contrast repository QR (not a runtime dependency).

Requires qrcode + Pillow. Quiet zone is four modules; no logo or gradients.
"""
from pathlib import Path
import qrcode

URL = 'https://github.com/yinon-mitin/Status-Page'
qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=20, border=4)
qr.add_data(URL)
qr.make(fit=True)
image = qr.make_image(fill_color='black', back_color='white')
target = Path(__file__).parents[1] / 'assets' / 'github-qr.png'
image.save(target)
print(f'{target}: {image.size}, encodes {URL}')
