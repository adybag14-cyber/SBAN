#!/usr/bin/env python3
import json, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'zig-out' / 'bin' / 'zig_sban'
OUT = ROOT / 'docs' / 'results' / 'v12_search_release'
OUT.mkdir(parents=True, exist_ok=True)
PROTOCOLS = {
    'prefix': (ROOT / 'data' / 'enwik8', 'prefix', 10000),
    'drift': (ROOT / 'data' / 'enwik8', 'drift', 10000),
    'probe': (ROOT / 'data' / 'elastic_probe.bin', 'prefix', 29000),
    'longrun': (ROOT / 'data' / 'enwik8', 'prefix', 62500),
}
BASE = ['birth_pressure_threshold_bonus=0', 'birth_saturation_threshold_bonus=0', 'birth_saturation_parent_boost=0']
CANDIDATES = {
    'compact': ['enable_long_term=false', 'birth_margin=21', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', *BASE],
    'drift_bias': ['enable_long_term=false', 'birth_margin=20', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', *BASE],
    'longrun_hardened': ['enable_long_term=true', 'birth_margin=20', 'min_parents_for_birth=4', 'max_carry_memories=64', 'max_hidden_per_hop=48', 'propagation_depth=3', 'long_term_bonus_ppm=1120', 'long_term_bonus_precision_ppm=580', *BASE],
}
def run(protocol, bits, variant, profile, overrides):
    dataset, mode, seg_len = PROTOCOLS[protocol]
    out_json = OUT / f'{protocol}_{bits}_{variant}_{profile}.json'
    cmd = [str(BIN), 'eval-variant', str(dataset), str(out_json), mode, str(bits), variant, str(seg_len), '5000', '4096', f'label={protocol}_{bits}_{variant}_{profile}', *overrides]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    data = json.loads(out_json.read_text())['models'][0]
    return 100.0 * data['total_correct'] / data['total_predictions']
if __name__ == '__main__':
    for protocol in PROTOCOLS:
        rows = []
        if protocol == 'longrun':
            rows.append((run(protocol, 5, 'default', 'compact', CANDIDATES['compact']), 'default', 'compact'))
            rows.append((run(protocol, 5, 'fixed_capacity', 'hardened', CANDIDATES['longrun_hardened']), 'fixed_capacity', 'hardened'))
        else:
            rows.append((run(protocol, 5, 'default', 'compact', CANDIDATES['compact']), 'default', 'compact'))
            rows.append((run(protocol, 5, 'default', 'drift_bias', CANDIDATES['drift_bias']), 'default', 'drift_bias'))
        rows.sort(reverse=True)
        print(f'[{protocol}]')
        for acc, variant, profile in rows:
            print(f'  {acc:.4f}% variant={variant} profile={profile}')
