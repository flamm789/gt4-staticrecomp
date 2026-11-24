"""Report local PAL disc identity and hashes without extracting game files."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import gt4disc
import pycdlib


REDUMP_DISCS = {
    (5660540928, "5b504676595dea8b32cb675993285fca"): "europe_australia_retail",
    (5573115904, "2fb950a8fe1bae24cc62e09e51526c37"): "europe_beta_2005_01_18",
}
MAX_BOOT_SIZE = 16 * 1024 * 1024


def fingerprint_iso(path):
    sha256 = hashlib.sha256()
    md5 = hashlib.md5(usedforsecurity=False)
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(gt4disc.CHUNK_SIZE):
            sha256.update(chunk)
            md5.update(chunk)
            size += len(chunk)
    return {"size_bytes": size, "sha256": sha256.hexdigest()}, md5.hexdigest()


def pcsx2_elf_crc(data):
    if (len(data) < 52 or data[:7] != b"\x7fELF\x01\x01\x01"
            or struct.unpack_from("<H", data, 18)[0] != 8):
        raise ValueError("BOOT2 is not a little-endian 32-bit MIPS ELF")
    # The PCSX2 disc CRC is the XOR of the ELF's complete little-endian words.
    crc = 0
    for (word,) in struct.iter_unpack("<I", memoryview(data)[:len(data) // 4 * 4]):
        crc ^= word
    return f"{crc:08X}"


def inspect_pal(path):
    disc, md5 = fingerprint_iso(path)
    report = gt4disc.inspect_disc(path, disc)
    system = report["system"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+", system["version"]) or system["video_mode"] not in {"PAL", "NTSC"}:
        raise ValueError("Unexpected VER or VMODE in SYSTEM.CNF")

    boot = report["files"][system["boot_path"]]
    if boot["size_bytes"] > MAX_BOOT_SIZE:
        raise ValueError("BOOT2 exceeds the supported 16 MiB limit")
    iso = pycdlib.PyCdlib()
    iso.open(str(path))
    try:
        with iso.open_file_from_iso(iso_path=system["boot_path"]) as stream:
            data = stream.read(MAX_BOOT_SIZE + 1)
    finally:
        iso.close()
    if len(data) != boot["size_bytes"] or hashlib.sha256(data).hexdigest() != boot["sha256"]:
        raise ValueError("BOOT2 changed during inspection")
    crc = pcsx2_elf_crc(data)
    usa = json.loads(gt4disc.DEFAULT_MANIFEST.read_text(encoding="utf-8"))
    core_path = "/CORE.GT4;1"
    report.update({
        "iso_md5": md5,
        "redump_match": REDUMP_DISCS.get((disc["size_bytes"], md5)),
        "pcsx2_disc_crc": crc,
        "matches_reported_pcsx2_id": system["serial"] == "SCES-51719" and crc == "44A61C8F",
        "core_matches_usa_v200": report["files"][core_path] == usa["files"][core_path],
    })
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=Path)
    args = parser.parse_args(argv)
    try:
        report = inspect_pal(args.iso)
    except (OSError, ValueError, pycdlib.pycdlibexception.PyCdlibException) as error:
        print(f"ISO inspection failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
