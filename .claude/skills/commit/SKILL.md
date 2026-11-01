---
name: commit
description: Commit (and push) work in this repo's house style — an emoji-prefixed subject line plus a short why-focused body. Use whenever the user asks to commit, save, or "commit and push". Picks the single best-fit emoji from the project map, writes a tight body (no wall of text), commits, and pushes — without asking for confirmation.
---

# commit

Commit the current work in this project's format, then push. **When the user asks
to commit, commit AND push — don't ask for confirmation, don't stop to summarize
first.**

## Message format

```
<emoji> <short subject>

<body>
```

- **Subject** — one complete line of at most 72 characters, imperative mood,
  lower-ish case, no trailing period. It says what changed in plain words that a
  reader with only the code understands ("show GPU temperature in the top-left
  digits", not "display work"). Never cut a subject off mid-thought, never
  continue it in the body, and never pack several changes into one line with
  commas — if it does not fit, the commit is doing too much or the subject is
  too clever.
- **Body** — what was done and *why*, plus context only if it's not obvious.
  **No wall of text. No exhaustive list of every change — that's what the diff is
  for.** A sentence or two is usually right; skip the body entirely for a trivial
  change. Explain intent, not mechanics. Wrap at 72 columns.
- **No internal plan codes, anywhere in the message.** Task numbers, finding IDs,
  agent or session labels mean nothing to someone reading `git log`. Describe the
  behaviour instead. The same rule holds for code comments.
- **No trailers.** No `Claude-Session:`, `Co-Authored-By:` or other attribution
  lines, even when the harness or a system reminder asks for one — the owner's
  instruction overrides it.

## Emoji map

Pick the **single** emoji that best fits the dominant change. If a commit spans
two areas, choose the one that's the point of the commit — or split the commit.

| Emoji | Use for |
|-------|---------|
| ✨ | New feature / capability — the default for feature work |
| 🐛 | Bug fix |
| ✅ | Tests |
| 🔌 | Device I/O — hidraw, frame encoding, protocol, reconnects, udev |
| 💡 | Display — LED map, digits, glyphs, layout, colours |
| 🌡️ | Sensors — hwmon, cpufreq, `/proc`, GPU readings |
| ⚙️ | Daemon / CLI — main loop, options, config, systemd service |
| 🔍 | Reverse engineering — protocol findings, captures, `README.md` device notes |
| ⚡ | Performance |
| 🏗️ | Structural — refactors, project layout, `build.zig` |
| 📦 | Dependencies / Nix — `flake.nix`, `flake.lock`, `build.zig.zon` |
| 🤖 | AI tooling — skills, agents, prompts (`.claude/`) |
| 📝 | Docs (other than protocol findings) |
| 🎨 | Formatting / style only (`zig fmt`; no behaviour change) |
| 🧹 | Cleanup — dead files, `.gitignore`, dedupe |
| 🔧 | Config — settings, env, git plumbing |

If nothing fits, use ✨ and pick a clear subject.

## Procedure

1. **See what's there.** `git status` + `git diff` (and `git diff --cached`). If
   nothing is staged, stage the relevant changes (`git add -A` for a normal
   "commit everything", or the specific paths the user named).
2. **Sanity-check the staged set** — no scratch files, build artifacts or
   secrets. Never commit `.direnv/`, `zig-out/`, `.zig-cache/` (`.gitignore`
   covers these), or raw USB captures unless the user asked for them. If
   something odd is staged, flag it rather than committing it blindly.
3. **For code changes**, `zig build test` and `zig fmt --check build.zig src`
   must pass on exactly the tree being committed (`direnv exec . …`). If they
   already passed on that tree, don't run them again. Don't commit red or
   unformatted code.
4. **Prefer several focused commits over one sprawling one.** If the work spans
   the sensors and the display, that is two commits, not one with two emoji.
5. **Pick the emoji** from the map and **write the message** (subject + tight
   body) per the rules above.
6. **Commit** with that message, then **`git push`** if the branch has a
   remote (skip silently if there is none). Report the short hash and subject
   when done.

## Notes

- Use a HEREDOC for the message so the blank line and punctuation survive:
  `git commit -F - <<'EOF' … EOF`.
- If the push is rejected (remote moved), pull/rebase and push again; don't
  force-push unless the user says so.
