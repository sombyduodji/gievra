#!/usr/bin/env python3
"""Treeni-ilmoituksen taustakuvat (note_bg_gym/run/walk/other.png, 960×400) android/app/src/main/res/drawable-nodpi/.

Alkuperä: piirretty tällä skriptillä (Pillow) Gievraa varten 2026-11-13; ei kolmannen osapuolen kuvia, fontteja eikä
metatietoja. Lisenssi sama kuin sovelluksella (GPL-3.0-or-later). Aja repon juuresta: python3 tools/make_note_bg.py
"""
import os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from PIL import Image, ImageDraw, ImageFilter
import math, random
W,H=960,400
def base(c1,c2):
    im=Image.new('RGB',(W,H)); d=ImageDraw.Draw(im)
    for x in range(W):
        t=x/W; d.line([(x,0),(x,H)],fill=tuple(int(c1[i]*(1-t)+c2[i]*t) for i in range(3)))
    return im
def save(im,name):
    im=im.filter(ImageFilter.GaussianBlur(1.2))
    im.save(f'android/app/src/main/res/drawable-nodpi/{name}.png',optimize=True)
random.seed(4)
# Sali: tummanpunainen, levypainot
im=base((40,14,12),(78,22,18)); ov=Image.new('RGBA',(W,H)); d=ImageDraw.Draw(ov)
for cx,cy,r in [(760,200,150),(640,200,120),(860,90,70)]:
    d.ellipse([cx-r,cy-r,cx+r,cy+r],outline=(255,255,255,26),width=22)
    d.ellipse([cx-r*0.18,cy-r*0.18,cx+r*0.18,cy+r*0.18],fill=(255,255,255,22))
d.rectangle([420,190,960,210],fill=(255,255,255,18))
im=Image.alpha_composite(im.convert('RGBA'),ov).convert('RGB'); save(im,'note_bg_gym')
# Juoksu: tummanvihreä, kiemurteleva polku
im=base((10,36,22),(16,70,40)); ov=Image.new('RGBA',(W,H)); d=ImageDraw.Draw(ov)
for k,a in [(0,40),(30,22),(60,14)]:
    pts=[(x, 230+70*math.sin(x/140+k/20)-x*0.12+k) for x in range(0,W+10,8)]
    d.line(pts,fill=(255,255,255,a),width=10,joint='curve')
im=Image.alpha_composite(im.convert('RGBA'),ov).convert('RGB'); save(im,'note_bg_run')
# Kävely: tumma turkoosi, askeleet
im=base((8,34,40),(14,62,70)); ov=Image.new('RGBA',(W,H)); d=ImageDraw.Draw(ov)
for i in range(9):
    x=420+i*62; y=300-i*24+(14 if i%2 else -14)
    d.ellipse([x,y,x+26,y+40],fill=(255,255,255,30)); d.ellipse([x+4,y-18,x+22,y-4],fill=(255,255,255,26))
im=Image.alpha_composite(im.convert('RGBA'),ov).convert('RGB'); save(im,'note_bg_walk')
# Muu: tummansininen, pehmeät aallot
im=base((14,20,46),(26,40,86)); ov=Image.new('RGBA',(W,H)); d=ImageDraw.Draw(ov)
for k in range(5):
    pts=[(x, 120+k*55+22*math.sin(x/90+k)) for x in range(400,W+10,8)]
    d.line(pts,fill=(255,255,255,18+k*3),width=6)
im=Image.alpha_composite(im.convert('RGBA'),ov).convert('RGB'); save(im,'note_bg_other')
