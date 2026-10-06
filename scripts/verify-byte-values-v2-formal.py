#!/usr/bin/env python3
"""Complete finite byte-value ABI checks and exact expected-failure mutations."""

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "formal/ByteValueDictionaryV2.tla"
LEDGER = ROOT / "formal/byte_values_v2_ledger.json"
CONFIG_DIR = ROOT / "formal/MC"
OUTPUT = ROOT / "target/byte-values-formal/gate"

# Each edit corrupts an actual transition or state value, not an invariant.
# Every mutation must be caught by its paired invariant in the declared case.
MUTATIONS = {
    "type_out_of_range": ("keyCalls |-> 0", "keyCalls |-> 2", "Main"),
    "offer_missing_point_capability": (
        '!.point[s] = Domain = "Bytes" /\\ HasPointV2 /\\ version <= 2,',
        "!.point[s] = TRUE,", "NoV2"
    ),
    "fall_back_bytes_to_v1": (
        '!.v1[s] = Domain # "Bytes" /\\ HasV1 /\\ version <= 1]',
        "!.v1[s] = HasV1 /\\ version <= 1]", "Main"
    ),
    "drop_snapshot_retain": ("!.retains[s] = 1,", "!.retains[s] = 0,", "Main"),
    "reuse_live_token": (
        '/\\ \\A other \\in Snapshots : st.live[other] => st.token[other] # word',
        '/\\ TRUE', "Tokens"
    ),
    "publish_failed_copy": (
        "!.published[s] = IF capacity < PayloadLength THEN 0 ELSE PayloadLength]",
        "!.published[s] = IF capacity < PayloadLength THEN 1 ELSE PayloadLength]",
        "Main"
    ),
    "understate_byte_capacity": ("!.capBytes[s] = capB]", "!.capBytes[s] = 0]", "Main"),
    "lose_live_lease": (
        "!.lease[s] = st.generation[s] + 1,", "!.lease[s] = 0,", "Main"
    ),
    "reopen_cancelled_cursor": (
        '!.cursor[s] = IF st.cursor[s] = "Open" THEN "Ended" ELSE st.cursor[s]]',
        "!.cursor[s] = st.cursor[s]]", "Main"
    ),
    "dispatch_per_key": (
        "!.capBytes[s] = capB]", "!.capBytes[s] = capB, !.keyCalls = 1]", "Main"
    ),
}


def run_tlc(command: list[str], config: Path, model: Path, name: str,
            should_fail: str | None) -> None:
    meta = OUTPUT / f"meta-{name}"
    meta.mkdir(parents=True, exist_ok=True)
    log = OUTPUT / f"{name}.log"
    with log.open("w") as output:
        try:
            result = subprocess.run(
                [*command, "-workers", "1", "-metadir", str(meta),
                 "-config", str(config), str(model)],
                cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                check=False, timeout=120,
            )
        except subprocess.TimeoutExpired as error:
            raise SystemExit(f"TLC timed out for {name}: {log}") from error
    text = log.read_text()
    if should_fail is None:
        if result.returncode != 0 or "Model checking completed. No error has been found." not in text:
            raise SystemExit(f"TLC positive case failed: {name}, {log}")
    elif result.returncode == 0 or f"Invariant {should_fail} is violated" not in text:
        raise SystemExit(f"mutation escaped {should_fail}: {name}, {log}")
    print(f"{name}: {'caught ' + should_fail if should_fail else 'passed'}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tlc-jar", type=Path)
    args = parser.parse_args()
    if args.tlc_jar:
        command = ["java", "-cp", str(args.tlc_jar.resolve()), "tlc2.TLC"]
    elif shutil.which("tlc"):
        command = ["tlc"]
    else:
        raise SystemExit("TLC is unavailable; pass --tlc-jar")

    ledger = json.loads(LEDGER.read_text())
    cases = sorted(CONFIG_DIR.glob("ByteValueDictionaryV2*.cfg"))
    if len(cases) != 7:
        raise SystemExit(f"expected seven finite configurations, found {len(cases)}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for config in cases:
        run_tlc(command, config, MODEL, config.stem, None)

    source = MODEL.read_text()
    mutant_dir = OUTPUT / "mutant"
    mutant_dir.mkdir(exist_ok=True)
    mutant_model = mutant_dir / MODEL.name
    mutant_config = mutant_dir / "check.cfg"
    if {row["mutation"] for row in ledger["invariants"]} != set(MUTATIONS):
        raise SystemExit("mutation ledger and runner differ")
    for row in ledger["invariants"]:
        mutation = row["mutation"]
        before, after, case = MUTATIONS[mutation]
        if source.count(before) != 1:
            raise SystemExit(f"mutation anchor is not unique: {mutation}")
        mutant_model.write_text(source.replace(before, after, 1))
        config = (CONFIG_DIR / f"ByteValueDictionaryV2{case}.cfg").read_text()
        config, count = re.subn(
            r"INVARIANTS\n(?:  [A-Za-z][A-Za-z0-9]*\n)+",
            f'INVARIANT {row["name"]}\n', config,
        )
        if count != 1:
            raise SystemExit(f"could not isolate invariant: {mutation}")
        mutant_config.write_text(config)
        run_tlc(command, mutant_config, mutant_model, mutation, row["name"])
    mutant_model.unlink()
    mutant_config.unlink()
    mutant_dir.rmdir()


if __name__ == "__main__":
    main()
