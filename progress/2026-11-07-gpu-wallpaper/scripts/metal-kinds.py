#!/usr/bin/env python3
"""Count native-metal log kinds in an lscan capture, or the growth between two count files.

lscan mixes boots, so one boot shows up as the growth between captures. Log rotation can remove old
lines, so a growth figure is a lower bound.

Usage: metal-kinds.py count <lscan.txt> <out.json>
       metal-kinds.py diff <before.json> <after.json>
"""
import collections
import json
import re
import sys


POSTER = re.compile(rb'KaleidoscopePoster|PridePoster|HelloPoster')
TROUBLE = re.compile(rb'(?i)den(y|ied)|sandbox|refus|fail|error|crash|abort|invalid|exit|terminat|jetsam')


def kind(line):
    line = re.sub(r'0x[0-9a-f]+', 'N', line)
    line = re.sub(r'\d+', 'N', line)
    return line[:96]


def main():
    if sys.argv[1] == 'count':
        counts = collections.Counter()
        with open(sys.argv[2], 'rb') as f:
            for raw in f:
                if raw.startswith(b'native-metal') or raw.startswith(b'NATIVE_METAL'):
                    counts[kind(raw.decode('utf-8', 'replace').rstrip())] += 1
                elif POSTER.search(raw) and TROUBLE.search(raw):
                    counts['poster: ' + kind(raw.decode('utf-8', 'replace').rstrip())] += 1
        with open(sys.argv[3], 'w', encoding='utf-8') as f:
            json.dump(counts, f, ensure_ascii=False, indent=0)
        print('kinds', len(counts), 'lines', sum(counts.values()))
        return
    a = json.load(open(sys.argv[2], encoding='utf-8'))
    b = json.load(open(sys.argv[3], encoding='utf-8'))
    rows = sorted(((b.get(k, 0) - a.get(k, 0), k) for k in set(a) | set(b)), reverse=True)
    grown = [r for r in rows if r[0] > 0]
    print('grown kinds', len(grown), 'lines', sum(r[0] for r in grown), 'shrunk kinds', sum(r[0] < 0 for r in rows))
    for n, k in grown[:30]:
        print('%6d %s' % (n, k))


main()
