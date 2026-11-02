#!/usr/bin/env python3
"""Pack a replacement FAT payload into the user's header-v3 UEFI template.

Keep BootShim, firmware volume, DTB, Android parameters and tiny ramdisk exact.
The payload must keep its original byte size, so firmware memory reservations
and BootShim's image size remain valid. This is a local template packer.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import struct
import zlib

def sha(data): return hashlib.sha256(data).hexdigest()
def aligned(n): return (n + 4095) & ~4095

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--template',type=Path,required=True)
p.add_argument('--ramdisk',type=Path,required=True,help='replacement FAT payload')
p.add_argument('-o','--output',type=Path,required=True)
a=p.parse_args()
old=a.template.read_bytes()
assert old[:8]==b'ANDROID!' and struct.unpack_from('<I',old,40)[0]==3
old_size,android_ramdisk=struct.unpack_from('<II',old,8)
assert struct.unpack_from('<I',old,20)[0]==1580
decoder=zlib.decompressobj(31)
raw=decoder.decompress(old[4096:4096+old_size])+decoder.flush()
tail=decoder.unused_data
assert decoder.eof and tail[:4]==bytes.fromhex('d00dfeed')
volumes=[];cursor=0
while True:
    at=raw.find(b'FAT32   ',cursor)
    if at<0:break
    cursor=at+1;base=at-82
    if base<0 or raw[base+510:base+512]!=b'\x55\xaa':continue
    bps=struct.unpack_from('<H',raw,base+11)[0]
    sectors=struct.unpack_from('<I',raw,base+32)[0]
    if bps==512 and sectors*bps>1048576 and base+sectors*bps==len(raw):
        volumes.append((base,sectors*bps))
assert len(volumes)==1,volumes
offset,size=volumes[0]
payload=a.ramdisk.read_bytes()
assert len(payload)==size,'Changing firmware memory reservation is not supported'
assert payload[510:512]==b'\x55\xaa' and payload[82:90]==b'FAT32   '
prefix=raw[:offset]
new_kernel=gzip.compress(prefix+payload,compresslevel=9,mtime=0)+tail
old_end=4096+aligned(old_size)
assert len(old)==old_end+aligned(android_ramdisk),'Unexpected Android trailer/signature'
android_section=old[old_end:]
header=bytearray(old[:4096]);struct.pack_into('<I',header,8,len(new_kernel))
result=bytes(header)+new_kernel+bytes(aligned(len(new_kernel))-len(new_kernel))+android_section
# Independently read back the packed Android kernel and gzip members.
reader=zlib.decompressobj(31)
check=reader.decompress(result[4096:4096+len(new_kernel)])+reader.flush()
assert check[:offset]==prefix and check[offset:]==payload and reader.unused_data==tail
assert result[4096+aligned(len(new_kernel)):]==android_section
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_bytes(result)
report=dict(header_version=3,template=str(a.template.resolve()),template_sha256=sha(old),
            boot_bytes=len(result),boot_sha256=sha(result),payload_bytes=size,payload_sha256=sha(payload),
            firmware_prefix_sha256=sha(prefix),firmware_preserved=True,dtb_sha256=sha(tail),
            dtb_preserved=True,android_ramdisk_preserved=True,hardware_tested=False)
(a.output.parent/'bootimage.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
