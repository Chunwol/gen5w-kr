#!/usr/bin/env python3
"""Read the source revision from normal clones and Windows worktrees in WSL."""
import os
from pathlib import Path
import re
import subprocess


WINDOWS_ABSOLUTE = re.compile(r'^([A-Za-z]):[\\/](.*)$')


def wsl_gitdir(value):
    """Translate a Windows absolute gitdir path to its standard WSL mount."""
    match = WINDOWS_ABSOLUTE.match(str(value).strip())
    if not match:
        return Path(value)
    tail = match.group(2).replace('\\', '/').lstrip('/')
    return Path('/mnt') / match.group(1).lower() / tail


def _git_revision(repo, gitdir=None):
    command = ['git']
    if gitdir is not None:
        command.append('--git-dir=' + str(gitdir))
    command.extend(['rev-parse', 'HEAD'])
    return subprocess.check_output(
        command, cwd=repo, text=True, stderr=subprocess.DEVNULL
    ).strip()


def source_revision(repo):
    repo = Path(repo).resolve()
    try:
        return _git_revision(repo)
    except (OSError, subprocess.CalledProcessError):
        marker = repo / '.git'
        if os.name == 'nt' or not marker.is_file():
            raise
        line = marker.read_text(encoding='utf-8').strip()
        if not line.startswith('gitdir: '):
            raise
        value = line[len('gitdir: '):].strip()
        gitdir = wsl_gitdir(value)
        if not WINDOWS_ABSOLUTE.match(value):
            gitdir = (repo / gitdir).resolve()
        return _git_revision(repo, gitdir)
