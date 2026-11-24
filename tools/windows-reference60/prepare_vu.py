"""Prepare the existing v2.00 VU tables from a verified local ELF."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def require_digest(data, expected, label):
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"SHA-256 mismatch: {label}")


def verify_tables(output, reference):
    for unit in (0, 1):
        pins = reference[f"vu{unit}_aot"]
        generated = output / f"vu{unit}-gen"
        image = output / f"vu{unit}-image" / f"vu{unit}_image.bin"
        require_digest(image.read_bytes(), pins["image_sha256"], str(image))
        manifest_path = generated / "manifest.json"
        manifest_bytes = manifest_path.read_bytes()
        manifest_pin = pins["manifest_sha256"] if unit == 0 else pins["generated_manifest_sha256"]
        require_digest(manifest_bytes, manifest_pin, str(manifest_path))
        manifest = json.loads(manifest_bytes)
        table = generated / f"vu{unit}_generated.cpp"
        table_pin = pins["table_sha256"] if unit == 0 else pins["generated_source_sha256"]
        require_digest(table.read_bytes(), table_pin, str(table))
        expected_files = {table.name, manifest_path.name}
        for part in manifest.get("generated_parts", []):
            source = generated / part["file"]
            require_digest(source.read_bytes(), part["sha256"], str(source))
            expected_files.add(source.name)
        if {path.name for path in generated.iterdir()} != expected_files:
            raise ValueError(f"Unexpected generated files in {generated}")


def prepare(output, repo, elf_path, recompiler):
    inputs = repo / "docs/inputs"
    reference = read_json(inputs / "slice408-pcsx2.json")
    elf = elf_path.read_bytes()
    require_digest(elf, read_json(inputs / "usa-v2.00-native.json")["native_elf_sha256"], str(elf_path))
    if output.exists():
        verify_tables(output, reference)
        print(f"Verified existing VU tables in {output}")
        return
    if not recompiler.is_file():
        raise ValueError(f"Missing VU generator: {recompiler}")

    # Reuse the upstream image and entry producers. The VU1 tail is the exact
    # one in the pinned image manifest. No private snapshot is claimed here.
    sys.path.insert(0, str(repo / "scripts"))
    from vu1_image import BLOB_BYTES, ELF_OFFSET, decrypt_blob

    vu1_pins = read_json(inputs / "slice155-vu1-image.json")
    vu1_blob = decrypt_blob(elf[ELF_OFFSET:ELF_OFFSET + BLOB_BYTES])
    require_digest(vu1_blob, vu1_pins["blob_sha256"], "VU1 blob")
    vu1_image = vu1_blob + bytes.fromhex(vu1_pins["tail_hex"])
    require_digest(vu1_image, vu1_pins["image"]["sha256"], "VU1 image")

    with tempfile.TemporaryDirectory(prefix=".vu-", dir=output.parent) as temporary:
        stage = Path(temporary) / "tables"

        def image_tool(unit, *arguments):
            subprocess.run([sys.executable, repo / "scripts" / f"vu{unit}_image.py", *arguments], check=True)

        image0 = stage / "vu0-image" / "vu0_image.bin"
        image1 = stage / "vu1-image" / "vu1_image.bin"
        image0.parent.mkdir(parents=True)
        image1.parent.mkdir()
        image1.write_bytes(vu1_image)
        image_tool(0, "build", "--elf", elf_path, "--out", image0.parent)
        image_tool(0, "check", "--image", image0)
        entries0 = stage / "vu0-entries.txt"
        entries1 = stage / "vu1-entries.txt"
        image_tool(0, "entries", "--image", image0, "--out", entries0)
        image_tool(1, "entries", "--image", image1, "--policy", "all", "--out", entries1)
        require_digest(entries0.read_bytes(), reference["vu0_aot"]["entry_list_sha256"], str(entries0))
        require_digest(entries1.read_bytes(), reference["vu1_aot"]["entry_list_sha256"], str(entries1))

        subprocess.run(
            [recompiler, "--unit", "0", "--namespace", "gt4::vugen::vu0", "--entry-policy",
             "vcallms", "--image", image0, "--entries", entries0, stage / "vu0-gen"],
            check=True,
        )
        subprocess.run(
            [recompiler, "--programs-per-file", "16", "--entry-policy", "all", "--image", image1,
             "--entries", entries1, stage / "vu1-gen"],
            check=True,
        )
        verify_tables(stage, reference)
        stage.rename(output)
    print(f"Prepared and verified the VU tables in {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path)
    parser.add_argument("elf", type=Path)
    parser.add_argument("recompiler", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.output, args.repository, args.elf, args.recompiler)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"VU preparation failed: {error}\n")


if __name__ == "__main__":
    main()
