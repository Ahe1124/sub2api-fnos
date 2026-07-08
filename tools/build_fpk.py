#!/usr/bin/env python3
import argparse
import hashlib
import io
import os
import shutil
import tarfile
from pathlib import Path


EXECUTABLE_PATHS = {
    "cmd/main",
    "cmd/install_init",
    "cmd/install_callback",
    "cmd/config_init",
    "cmd/config_callback",
    "cmd/upgrade_init",
    "cmd/upgrade_callback",
    "cmd/uninstall_init",
    "cmd/uninstall_callback",
    "docker/sub2api-fnos-entrypoint.sh",
}


def mode_for(name: str, is_dir: bool) -> int:
    if is_dir:
        return 0o755
    if name.replace("\\", "/") in EXECUTABLE_PATHS:
        return 0o755
    return 0o644


def add_path(tar: tarfile.TarFile, source: Path, arcname: str) -> None:
    arcname = arcname.replace("\\", "/")
    info = tar.gettarinfo(str(source), arcname)
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mode = mode_for(arcname, source.is_dir())

    if source.is_file():
        with source.open("rb") as handle:
            tar.addfile(info, handle)
    else:
        tar.addfile(info)


def add_tree(tar: tarfile.TarFile, source_root: Path, archive_root: str = "") -> None:
    for path in sorted(source_root.rglob("*")):
        rel = path.relative_to(source_root).as_posix()
        arcname = f"{archive_root}/{rel}" if archive_root else rel
        add_path(tar, path, arcname)


def write_app_tgz(package_dir: Path, output_path: Path) -> str:
    with tarfile.open(output_path, "w:gz", format=tarfile.PAX_FORMAT) as tar:
        for name in ("docker", "ui", "www"):
            add_path(tar, package_dir / "app" / name, name)
            add_tree(tar, package_dir / "app" / name, name)
        add_path(tar, package_dir / "config", "config")
        add_tree(tar, package_dir / "config", "config")

    return hashlib.md5(output_path.read_bytes()).hexdigest()


def write_fpk(package_dir: Path, app_tgz: Path, output_path: Path) -> None:
    with tarfile.open(output_path, "w:gz", format=tarfile.PAX_FORMAT) as tar:
        for name in ("ICON.PNG", "ICON_256.PNG", "manifest"):
            add_path(tar, package_dir / name, name)

        app_info = tar.gettarinfo(str(app_tgz), "app.tgz")
        app_info.uid = 0
        app_info.gid = 0
        app_info.uname = "root"
        app_info.gname = "root"
        app_info.mode = 0o644
        with app_tgz.open("rb") as handle:
            tar.addfile(app_info, handle)

        for name in ("cmd", "config", "wizard"):
            add_path(tar, package_dir / name, name)
            add_tree(tar, package_dir / name, name)


def configure_prebuilt_image(root: Path, image: str) -> None:
    image = image.strip()
    if not image:
        return
    source = 'PREBUILT_IMAGE="__SUB2API_FNOS_IMAGE__"'
    target = f'PREBUILT_IMAGE="{image}"'
    for relative in ("cmd/install_callback", "cmd/uninstall_callback"):
        path = root / relative
        content = path.read_text(encoding="utf-8")
        path.write_text(content.replace(source, target), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--version", default="0.1.0")
    parser.add_argument("--image", default="")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    package_dir = root / "package"
    dist_dir = root / "dist"
    build_dir = root / ".build"
    dist_dir.mkdir(parents=True, exist_ok=True)

    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True)

    app_tgz = build_dir / "app.tgz"
    checksum = write_app_tgz(package_dir, app_tgz)

    manifest_path = package_dir / "manifest"
    manifest = manifest_path.read_text(encoding="utf-8")
    manifest = "\n".join(
        line for line in manifest.splitlines()
        if not line.startswith("checksum=")
    ).rstrip() + f"\nchecksum={checksum}\n"

    temp_package = build_dir / "package"
    shutil.copytree(package_dir, temp_package)
    configure_prebuilt_image(temp_package, args.image)
    (temp_package / "manifest").write_text(manifest, encoding="utf-8", newline="\n")

    output_path = dist_dir / f"sub2api-docker_{args.version}.fpk"
    if output_path.exists():
        output_path.unlink()
    write_fpk(temp_package, app_tgz, output_path)

    digest = hashlib.md5(output_path.read_bytes()).hexdigest()
    print(f"FPK: {output_path}")
    print(f"Size: {output_path.stat().st_size} bytes")
    print(f"MD5: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
