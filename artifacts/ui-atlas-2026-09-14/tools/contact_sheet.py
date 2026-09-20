from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
import json
out=Path(__file__).resolve().parents[1];rows=json.loads((out/'catalog.json').read_text())['screens'];font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',15)
for part in range(4):
 group=rows[part*12:(part+1)*12];canvas=Image.new('RGB',(1200,((len(group)+2)//3)*385),'#edf0e8');d=ImageDraw.Draw(canvas)
 for i,s in enumerate(group):
  im=Image.open(out/s['file']).convert('RGBA');im.thumbnail((390,343));x=i%3*400;y=i//3*385;bg=Image.new('RGB',im.size,'#101515');bg.paste(im,mask=im.getchannel('A'));canvas.paste(bg,(x+(400-im.width)//2,y));d.text((x+8,y+350),s['number']+' '+s['title'],font=font,fill='#182820')
 canvas.save(f'/tmp/halofold-contact-{part}.png')
canvas=Image.new('RGB',(1560,570),'#f3f2ee');d=ImageDraw.Draw(canvas);title=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',24)
for i,(key,label) in enumerate([('activity-main','活动'),('notes-main','便签'),('schedule-main','我的日程')]):
 d.text((i*520+25,15),label,font=title,fill='#263f32');im=Image.open(out/'screenshots'/f'{key}.png').convert('RGBA');im.thumbnail((500,480));bg=Image.new('RGB',im.size,'#f3f2ee');bg.paste(im,mask=im.getchannel('A'));canvas.paste(bg,(i*520+(520-im.width)//2,65))
canvas.save(out/'overview.png')
