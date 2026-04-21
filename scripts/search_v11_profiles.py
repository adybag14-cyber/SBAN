#!/usr/bin/env python3
import json, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'zig-out' / 'bin' / 'zig_sban'
OUT = ROOT / 'docs' / 'results' / 'v11_search'
OUT.mkdir(parents=True, exist_ok=True)
PROTOCOLS = {
    'prefix': (ROOT / 'data' / 'enwik8', 'prefix', 10000),
    'drift': (ROOT / 'data' / 'enwik8', 'drift', 10000),
    'probe': (ROOT / 'data' / 'elastic_probe.bin', 'prefix', 29000),
}
CANDIDATES = {
    'unified': ['enable_long_term=false', 'birth_margin=21', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', 'birth_pressure_threshold_bonus=0'],
    'drift_bias': ['enable_long_term=false', 'birth_margin=20', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', 'birth_pressure_threshold_bonus=0'],
    'probe_bias': ['enable_long_term=false', 'birth_margin=21', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', 'birth_pressure_threshold_bonus=0'],
    'long_term_ref': ['enable_long_term=true', 'birth_margin=24', 'min_parents_for_birth=4', 'max_carry_memories=32', 'max_hidden_per_hop=40', 'propagation_depth=3', 'birth_pressure_threshold_bonus=0'],
}

def run(protocol: str, bits: int, profile: str, overrides: list[str]) -> float:
    dataset, mode, seg_len = PROTOCOLS[protocol]
    out_json = OUT / f'{protocol}_{bits}_{profile}.json'
    cmd = [str(BIN), 'eval-variant', str(dataset), str(out_json), mode, str(bits), 'default', str(seg_len), '5000', '4096', f'label={protocol}_{bits}_{profile}', *overrides]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    data = json.loads(out_json.read_text())['models'][0]
    return 100.0 * data['total_correct'] / data['total_predictions']

if __name__ == '__main__':
    for protocol in PROTOCOLS:
        rows = []
        for bits in (5, 6):
            for profile, overrides in CANDIDATES.items():
                rows.append((run(protocol, bits, profile, overrides), bits, profile))
        rows.sort(reverse=True)
        print(f'[{protocol}]')
        for acc, bits, profile in rows:
            print(f'  {acc:.4f}%  bits={bits}  profile={profile}')
