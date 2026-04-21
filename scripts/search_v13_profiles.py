#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'zig-out' / 'bin' / 'zig_sban'
OUT = ROOT / 'docs' / 'results' / 'v13_search'
OUT.mkdir(parents=True, exist_ok=True)

BASE = ['birth_pressure_threshold_bonus=0', 'birth_saturation_threshold_bonus=0', 'birth_saturation_parent_boost=0']
CANDIDATES = {
    'compact': ['enable_long_term=false', 'birth_margin=21', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', *BASE],
    'drift_best': ['enable_long_term=false', 'birth_margin=20', 'min_parents_for_birth=4', 'max_carry_memories=48', 'max_hidden_per_hop=32', 'propagation_depth=2', *BASE],
    'hardened': ['enable_long_term=true', 'birth_margin=20', 'min_parents_for_birth=4', 'max_carry_memories=64', 'max_hidden_per_hop=48', 'propagation_depth=3', 'long_term_bonus_ppm=1120', 'long_term_bonus_precision_ppm=580', *BASE],
    'hardened_q0': ['enable_long_term=true', 'birth_margin=20', 'min_parents_for_birth=4', 'max_carry_memories=64', 'max_hidden_per_hop=48', 'propagation_depth=3', 'long_term_bonus_ppm=1120', 'long_term_bonus_precision_ppm=580', 'carry_quality_bonus=0', *BASE],
}
PROTOCOLS = {
    'prefix': ('data/enwik8', 'prefix', 10000, 'default', 'compact'),
    'drift': ('data/enwik8', 'drift', 10000, 'default', 'drift_best'),
    'probe': ('data/elastic_probe.bin', 'prefix', 29000, 'default', 'compact'),
    'longrun_250k': ('data/enwik8', 'prefix', 62500, 'fixed_capacity', 'hardened'),
    'longrun_1m': ('data/enwik8', 'prefix', 250000, 'fixed_capacity', 'hardened'),
}


def run_case(name: str, dataset: str, mode: str, seg_len: int, variant: str, profile_name: str) -> float:
    out_json = OUT / f'{name}.json'
    cmd = [str(BIN), 'eval-variant', str(ROOT / dataset), str(out_json), mode, '5', variant, str(seg_len), '5000', '4096', f'label={name}', *CANDIDATES[profile_name]]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    data = json.loads(out_json.read_text())['models'][0]
    return 100.0 * data['total_correct'] / data['total_predictions']


if __name__ == '__main__':
    for name, spec in PROTOCOLS.items():
        acc = run_case(name, *spec)
        print(f'{name}: {acc:.4f}%')
