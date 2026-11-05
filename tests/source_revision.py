#!/usr/bin/env python3
import pathlib
import re
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

from source_revision import source_revision, wsl_gitdir


class SourceRevisionTest(unittest.TestCase):
    def test_translates_windows_gitdir_for_wsl(self):
        self.assertEqual(
            pathlib.Path('/mnt/d/project/.git/worktrees/feature'),
            wsl_gitdir(r'D:\project\.git\worktrees\feature'),
        )

    def test_reads_current_worktree_revision(self):
        revision = source_revision(ROOT)
        self.assertRegex(revision, re.compile(r'^[0-9a-f]{40}$'))


if __name__ == '__main__':
    unittest.main()
