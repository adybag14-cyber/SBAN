#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'zig-out' / 'bin' / 'zig_sban'
OUT = ROOT / 'docs' / 'results' / 'v8_search'
OUT.mkdir(parents=True, exist_ok=True)

PROTOCOLS = {
    'prefix': (ROOT / 'data' / 'enwik8', 'prefix', 10000),
    'drift': (ROOT / 'data' / 'enwik8', 'drift', 10000),
    'probe': (ROOT / 'data' / 'elastic_probe.bin', 'prefix', 29000),
}

CANDIDATES = {
    'base': [],
    'carry48': ['max_carry_memories=48'],
    'no_long': ['enable_long_term=false'],
    'single': ['max_regions=1', 'initial_regions=1', 'region_split_load=65535'],
    'carry48_no_long': ['max_carry_memories=48', 'enable_long_term=false'],
    'pp600': ['promotion_precision_ppm=600'],
}


def run(protocol: str, bits: int, profile: str, overrides: list[str]) -> float:
    dataset, mode, seg_len = PROTOCOLS[protocol]
    out_json = OUT / f'{protocol}_{bits}_{profile}.json'
    cmd = [
        str(BIN),
        'eval-variant',
        str(dataset),
        str(out_json),
        mode,
        str(bits),
        'default',
        str(seg_len),
        '5000',
        '4096',
        f'label={protocol}_{bits}_{profile}',
        *overrides,
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    data = json.loads(out_json.read_text())['models'][0]
    return 100.0 * data['total_correct'] / data['total_predictions']


if __name__ == '__main__':
    for protocol in PROTOCOLS:
        rows = []
        for bits in (5, 6, 7, 8):
            for profile, overrides in CANDIDATES.items():
                acc = run(protocol, bits, profile, overrides)
                rows.append((acc, bits, profile))
        rows.sort(reverse=True)
        print(f'[{protocol}]')
        for acc, bits, profile in rows[:10]:
            print(f'  {acc:.4f}%  bits={bits}  profile={profile}')
