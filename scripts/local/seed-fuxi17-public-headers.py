#!/usr/bin/env python3
"""Reuse public source headers only after their cached Git blob hashes match."""
from pathlib import Path
import hashlib, json, shutil
old=Path('/home/xiaomi/up/UniXNU/out/fuxi/tree/.cache')
new=Path('/home/xiaomi/fuxi17-usb-local-20261102/UniXNU/out/fuxi/tree/.cache')
(new/'sources').mkdir(parents=True,exist_ok=True)
count=0
for name,relative,sub in [
 ('xnu-driverkit-10063.121.3.json','iokit/DriverKit',''),
 ('xnu-driverkit-crypto-10063.121.3.json','iokit/DriverKit','crypto'),
 ('xnu-trustcache-8796.101.5.json','EXTERNAL_HEADERS/TrustCache','')]:
    source=old/'sources'/name
    shutil.copy2(source,new/'sources'/name)
    for e in json.loads(source.read_text()):
        if e['type']!='file' or not e['name'].endswith('.h'):continue
        r=Path(relative)/sub/e['name'];p=old/'xnu-work'/r
        data=p.read_bytes()
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==e['sha'],str(p)
        dest=new/'xnu-work'/r;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);count+=1
print(f'Verified and reused {count} public Apple headers')
