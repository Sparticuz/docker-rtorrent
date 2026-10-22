#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request


def update_dockerfile(text, release):
    if release["draft"] or release["prerelease"]:
        raise ValueError("Expected a stable upstream release")
    version = release["tag_name"].removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Unexpected upstream version")
    current = re.findall(r"releases/download/v(\d+\.\d+\.\d+)/", text)
    if len(current) != 2 or current[0] != current[1]:
        raise ValueError("Expected matching rTorrent and libtorrent release pins")
    current = current[0]
    if tuple(map(int, version.split("."))) <= tuple(map(int, current.split("."))):
        return text

    text = text.replace(f"releases/download/v{current}/", f"releases/download/v{version}/")
    assets = {asset["name"]: asset for asset in release["assets"]}
    for project in ("libtorrent", "rtorrent"):
        digest = assets[f"{project}-{version}.tar.gz"]["digest"]
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest or ""):
            raise ValueError(f"Missing SHA-256 digest for {project}")
        old = f"{project}-{current}"
        if text.count(old) != 2:
            raise ValueError(f"Expected archive and build directory pins for {project}")
        text = text.replace(old, f"{project}-{version}")
        text, count = re.subn(
            r"[0-9a-f]{64}(?=  " + project + r"\.tar\.gz')",
            digest.removeprefix("sha256:"),
            text,
        )
        if count != 1:
            raise ValueError(f"Expected one checksum pin for {project}")
    return text


def main():
    release = json.loads(subprocess.check_output(
        ["gh", "api", "repos/rakshasa/rtorrent/releases/latest"], text=True,
    ))
    path = Path("Dockerfile")
    original = path.read_text()
    updated = update_dockerfile(original, release)
    version = release["tag_name"].removeprefix("v")
    if updated != original:
        assets = {asset["name"]: asset for asset in release["assets"]}
        for project in ("libtorrent", "rtorrent"):
            name = f"{project}-{version}.tar.gz"
            url = f"https://github.com/rakshasa/rtorrent/releases/download/v{version}/{name}"
            digest = hashlib.sha256()
            with urllib.request.urlopen(url, timeout=60) as response:
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
            if f"sha256:{digest.hexdigest()}" != assets[name]["digest"]:
                raise ValueError(f"Downloaded checksum mismatch for {name}")
        # Write only after both archives and every replacement have been validated.
        path.write_text(updated)
        print(f"Updated rTorrent and libtorrent to {version}")
    else:
        print(f"No newer stable release (upstream: {version})")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"updated={str(updated != original).lower()}\nversion={version}\n")


if __name__ == "__main__":
    main()
