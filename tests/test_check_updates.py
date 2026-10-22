import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "check_updates", Path(__file__).parents[1] / ".github/scripts/check-updates.py",
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.dockerfile = "\n".join(
            f"curl https://github.com/rakshasa/rtorrent/releases/download/v0.9.9/{project}-0.9.9.tar.gz\n"
            f"echo '{'a' * 64}  {project}.tar.gz' | sha256sum -c -\n"
            f"cd {project}-0.9.9"
            for project in ("libtorrent", "rtorrent")
        )
        self.release = {
            "tag_name": "v0.10.0", "draft": False, "prerelease": False,
            "assets": [
                {"name": "libtorrent-0.10.0.tar.gz", "digest": "sha256:" + "b" * 64},
                {"name": "rtorrent-0.10.0.tar.gz", "digest": "sha256:" + "c" * 64},
            ],
        }

    def test_updates_both_archives_directories_and_distinct_checksums(self):
        result = updater.update_dockerfile(self.dockerfile, self.release)
        for project, digest in (("libtorrent", "b" * 64), ("rtorrent", "c" * 64)):
            self.assertIn(f"/v0.10.0/{project}-0.10.0.tar.gz", result)
            self.assertIn(f"cd {project}-0.10.0", result)
            self.assertIn(f"'{digest}  {project}.tar.gz'", result)
        self.assertNotIn("0.9.9", result)
        self.assertEqual(updater.update_dockerfile(result, self.release), result)

    def test_does_not_downgrade(self):
        self.release["tag_name"] = "v0.9.8"
        self.assertEqual(updater.update_dockerfile(self.dockerfile, self.release), self.dockerfile)

    def test_rejects_incomplete_or_untrusted_release_metadata(self):
        for change in ("missing_asset", "missing_digest", "prerelease", "invalid_version"):
            with self.subTest(change=change):
                release = copy.deepcopy(self.release)
                if change == "missing_asset":
                    release["assets"].pop()
                elif change == "missing_digest":
                    release["assets"][0]["digest"] = None
                elif change == "prerelease":
                    release["prerelease"] = True
                else:
                    release["tag_name"] = "v0.10.0\ninjected=value"
                with self.assertRaises((ValueError, KeyError)):
                    updater.update_dockerfile(self.dockerfile, release)

    def test_rejects_mismatched_pins_or_missing_checksum(self):
        for text in (
            self.dockerfile.replace("/v0.9.9/rtorrent", "/v0.9.8/rtorrent"),
            self.dockerfile.replace("cd rtorrent-0.9.9", "cd elsewhere"),
            self.dockerfile.replace("a" * 64 + "  rtorrent.tar.gz", "missing  rtorrent.tar.gz"),
        ):
            with self.subTest(text=text), self.assertRaises(ValueError):
                updater.update_dockerfile(text, self.release)

    def test_checksum_mismatch_does_not_write_dockerfile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Dockerfile"
            path.write_text(self.dockerfile)
            with (
                mock.patch.object(updater, "Path", return_value=path),
                mock.patch.object(updater.subprocess, "check_output", return_value=json.dumps(self.release)),
                mock.patch.object(updater.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong archive")),
                self.assertRaisesRegex(ValueError, "checksum mismatch"),
            ):
                updater.main()
            self.assertEqual(path.read_text(), self.dockerfile)
