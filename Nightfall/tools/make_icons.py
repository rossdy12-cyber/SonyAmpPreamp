from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'packages/mobile/assets'
size = 1024
image = Image.new('RGB', (size, size), '#0C0D0E')
d = ImageDraw.Draw(image)
gold = '#C3A16A'
d.arc((218, 146, 806, 734), 180, 360, fill=gold, width=11)
d.line((218, 440, 218, 827), fill=gold, width=11)
d.line((806, 440, 806, 827), fill=gold, width=11)
d.line((179, 827, 845, 827), fill=gold, width=11)
d.arc((252, 180, 772, 700), 180, 360, fill='#68563C', width=5)
d.line((252, 440, 252, 791), fill='#68563C', width=5)
d.line((772, 440, 772, 791), fill='#68563C', width=5)
d.line((252, 791, 772, 791), fill='#68563C', width=5)
d.ellipse((364, 333, 654, 623), fill=gold)
d.ellipse((435, 289, 692, 550), fill='#0C0D0E')
d.line((512, 650, 512, 711), fill=gold, width=4)
d.polygon([(512, 725), (526, 739), (512, 753), (498, 739)], fill=gold)
image.save(root / 'icon.png')
image.save(root / 'adaptive-icon.png')
image.resize((64, 64)).save(root / 'favicon.png')
splash = Image.new('RGB', (1284, 2778), '#0C0D0E')
mark = image.resize((400, 400))
splash.paste(mark, ((1284-400)//2, (2778-400)//2))
splash.save(root / 'splash-icon.png')
print('Nightfall icon and splash assets generated.')