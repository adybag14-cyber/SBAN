#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUTS = [
    ROOT / "data" / "sban_runtime_prewarm_v36.txt",
    ROOT / "data" / "sban_synthetic_knowledge_v36.txt",
    ROOT / "data" / "sban_dialogue_open_seed_v36.txt",
]
DEFAULT_OUTPUT = ROOT / "docs" / "results" / "v36" / "vocab_size_probe_v36.json"
VOCAB_SIZES = (256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536)


def stable_bucket(token: str, vocab_size: int) -> int:
    digest = hashlib.blake2b(token.encode("utf-8"), digest_size=8).digest()
    return int.from_bytes(digest, "little") % vocab_size


def tokenize(text: str) -> list[str]:
    return re.findall(r"[a-z0-9_]+(?:'[a-z0-9_]+)?", text.lower())


def estimate_dense_bytes(vocab_size: int, orders: int = 2, regions: int = 8) -> int:
    return regions * orders * vocab_size * vocab_size * 4


def main() -> None:
    parser = argparse.ArgumentParser(description="Probe larger synthetic vocabulary sizes for SBAN v36.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--inputs", nargs="*", type=Path, default=DEFAULT_INPUTS)
    args = parser.parse_args()

    corpus = "\n".join(path.read_text(encoding="utf-8", errors="ignore") for path in args.inputs if path.exists())
    tokens = tokenize(corpus)
    unique_tokens = sorted(set(tokens))
    rows = []
    for vocab_size in VOCAB_SIZES:
        buckets: dict[int, int] = {}
        for token in unique_tokens:
            bucket = stable_bucket(token, vocab_size)
            buckets[bucket] = buckets.get(bucket, 0) + 1
        collisions = sum(count - 1 for count in buckets.values() if count > 1)
        rows.append(
            {
                "vocab_size": vocab_size,
                "unique_tokens": len(unique_tokens),
                "used_buckets": len(buckets),
                "collisions": collisions,
                "collision_rate": 0.0 if not unique_tokens else collisions / len(unique_tokens),
                "estimated_dense_order2_bytes": estimate_dense_bytes(vocab_size),
                "estimated_dense_order2_mib": estimate_dense_bytes(vocab_size) / (1024 * 1024),
            }
        )

    output = {
        "release": "v36",
        "core_byte_vocab_size": 256,
        "probe": "hashed wordpiece bucket collision and dense-table cost probe for larger vocabularies",
        "recommendation": "Use the v36 prewarm retrieval pack plus a sparse token index for 4096+ buckets; keep the core byte-level numeric runtime at 256 until dense order tables are replaced or sparsified.",
        "inputs": [str(path.relative_to(ROOT)) for path in args.inputs if path.exists()],
        "rows": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote={args.output}")
    for row in rows:
        print(f"vocab={row['vocab_size']} collisions={row['collisions']} collision_rate={row['collision_rate']:.4f}")


if __name__ == "__main__":
    main()
