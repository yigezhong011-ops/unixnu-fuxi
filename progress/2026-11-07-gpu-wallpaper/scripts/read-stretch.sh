#!/bin/bash
# Poster activity in the newest boot stretches of one capture. Read-only. Usage: read-stretch.sh <capture name>
N=/mnt/e/DSH-Fuxi/logs/carve-$1/lscan.txt
echo "=== $1 $(wc -l < $N) lines"
python3 -I - "$N" <<'EOF'
import re, sys
keys = {'spawn K': b'Successfully spawned KaleidoscopePoster', 'spawn P': b'Successfully spawned PridePosterExtension', 'spawn H': b'Successfully spawned HelloPosterExtension',
        'deny GPU K': b'KaleidoscopePoster', 'snap K': b'cleanup is running for', 'dev refused': b'native-metal: device refused'}
marks = []; seg = []; cur = None; last = 0; keep = []
with open(sys.argv[1], 'rb') as f:
    for n, line in enumerate(f, 1):
        if b'Doing boot task' in line or b'mount-phase-1' in line:
            if cur is None or n - cur['start'] > 20000:
                cur = {'start': n, 'lines': []}; seg.append(cur)
            continue
        if cur is None:
            continue
        if re.search(rb'(?i)(Kaleidoscope|PridePoster|HelloPoster)', line) and re.search(rb'(?i)Sandbox:|spawned|cleanup is running|exited|crash|jetsam|terminat|invalidat', line) or line.startswith(b'native-metal'):
            cur['lines'].append(re.sub(rb'0x[0-9a-f]+|\d+', b'N', line.rstrip())[:130].decode('utf-8', 'replace'))
        cur['end'] = n
import collections
print('stretches', len(seg))
for s in seg[-2:]:
    c = collections.Counter(s['lines'])
    print('--- stretch', s['start'], '-', s.get('end'), 'kinds', len(c))
    for k, v in c.most_common(30):
        print('%5d %s' % (v, k))
EOF
