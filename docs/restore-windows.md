# Continue after reinstalling Windows

Checked 2026-10-07. The latest technical checkpoint is published on
[`claude/inspiring-euler-3v24zv`](https://github.com/HarDvolT/SpawnAlpha/tree/claude/inspiring-euler-3v24zv).
The remote was verified at `92eb94a` (cursor source/track groundwork).
Read `AGENTS.md` first, then the Handover in `docs/status.md` to resume.
Do not start from `main`, which only has the initial project.

## Before formatting

The owner has confirmed **E: will not be deleted**. For a Windows reinstall
that formats only C: and leaves E: intact, the code, current app data, SDK and
local notes remain in `E:\Ai\ChatGPT`. The older Documents app data from C:
has also been copied to
`local-data\windows-reinstall-backups\20261007-211803-f44c2c96\Documents-SpawnAlpha`
inside the project. All 13 files (323,010,901 bytes) matched SHA-256 checks;
the originals on C: were preserved. The adjacent `backup-check.json` is the
local verification receipt. This is a copy on the retained drive, not an
external backup. No personal file contents or hashes were published.

If E: or all project storage will also be erased, follow the full-backup rules
below before formatting.

- Preserve the entire `E:\Ai\ChatGPT\SpawnAlpha` folder, including hidden
  `.git`, ignored `local-data` and other local files. The repository currently
  also has local planning/recovery notes that are intentionally not on GitHub.
- Preserve `C:\Users\Hakim\Documents\SpawnAlpha` too; earlier app data exists
  there. Include any exports or other project assets saved outside those folders.
- For an all-drives wipe, put the backup on storage outside the PC being formatted
  and check it before formatting. Another partition being erased is not sufficient.
  The current project folder and GitHub are not a verified external backup.
- Windows secure storage holds provider API keys separately. Copying the project
  does not guarantee those keys will work after reinstalling Windows. Reconnect
  providers securely when needed; never put keys or personal recordings on GitHub.
- Flutter, package caches, model downloads and generated builds can be downloaded
  or rebuilt. They do not replace the backup of scripts, takes and local work.

No external backup was created by this recovery check.

## After reinstalling

The agent handles the technical work; the owner does not type commands or edit
files. Restore the full project backup to the same path when available. If only
GitHub remains, clone the branch above into `E:\Ai\ChatGPT\SpawnAlpha`; the
published code and progress notes can be recovered, but unbacked local files
cannot be recreated from that clone.

Follow the Windows setup in `AGENTS.md`: verify E: is NTFS, reinstall Git and
Visual Studio Community with C++/ATL, enable Developer Mode, restore Flutter
3.47.5 at `E:\Ai\ChatGPT\flutter`, disable its analytics and configure the
user PATH. Set `PUB_CACHE=E:\Ai\ChatGPT\pub-cache` and
`SPAWNALPHA_DATA_DIR=E:\Ai\ChatGPT\SpawnAlpha\local-data` again so the restored
app opens the correct data. GitHub sign-in and Windows admin approval may be
needed. Check Windows desktop readiness, analyze/test, rebuild and open the app.

The technical checkpoint has 1151 passing Flutter tests and a successful
normal Windows release build. Smooth cursor rendering/history/UI, broader
editor/coaching/voice follow and mobile/launch work are still unfinished.
