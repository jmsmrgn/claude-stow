# claude-stow

> **Renamed:** This repo was previously `claude-lore`. If you cloned it before March 30 2026, update your remote:
>
> ```
> git remote set-url origin git@github.com:jmsmrgn/claude-stow.git
> ```

Persistent project memory that follows Claude across sessions. No database, no background service, no infrastructure.

Every project accumulates context: decisions made before Claude was in the room, approaches already tried, the reasons things are the way they are. `claude-stow` puts that context somewhere it can easily referenced and edited — and keeps it current automatically.

---

## The problem with static context

Claude's native memory continues to improve — in Claude Code, Auto Memory takes notes during sessions, and Auto Dream consolidates them between sessions, pruning contradictions, keeping things current.

That covers what Claude _observed_. It doesn't cover what you need Claude to _know from the start_ — context you authored deliberately, that you can read and correct, that exists before the first session begins.

Many users already solve this with a `CLAUDE.md` and a project context file. That's the right instinct. But a file you write before the project begins reflects what was true at the time of writing. It goes stale. Decisions accumulate, approaches get rejected, the current state shifts — and none of that finds its way back into the file unless you put it there manually.

`claude-stow` starts the same way: intentional foundation you write. But from there, Claude maintains it. Every decision appends. Every session patches the previous state. The context stays current without you having to remember to update it.

> **Claude Desktop users:** Auto Memory and Auto Dream are Claude Code-only features. Desktop sessions have no equivalent native memory — `claude-stow` fills that gap directly, not just as a complement to native memory but as a primary persistence layer.

---

## How it works

Three pieces work together:

**The vault** — a folder of markdown files, one for global context and one per project. You write them. You own them. They're just text files.

**The session hook** — a small script that runs at the start of every Claude Code session. It reads your vault and injects the right context automatically. You don't think about it.

**The checkpoint hook** — runs when a session ends (Stop event). It reads the session JSONL, extracts the conversation, and launches a background `claude -p` subprocess to update STATUS.md and DECISIONS.md automatically. No user action required. Output is logged to `~/.claude/stow-checkpoint.log`.

No database. No running processes. No port 37777.

---

## Compared to alternatives

**[claude-mem](https://github.com/thedotmack/claude-mem)** captures everything Claude does automatically and compresses it with AI. Powerful, but requires a persistent background service, SQLite, a vector database, and Bun. The memory it produces is machine-written — you don't read or edit it directly.

**[Continuous-Claude](https://github.com/parcadei/Continuous-Claude-v3)** is a full agent orchestration framework — 109 skills, 32 agents, 30 hooks, Docker, PostgreSQL, and a 12-step setup wizard. Different scope entirely.

`claude-stow` is for the user who wants their context to survive session boundaries and nothing else. Dependencies are `jq` and `python3` — both standard on macOS and Linux.

---

## Install

```bash
git clone https://github.com/jmsmrgn/claude-stow.git
cd claude-stow
chmod +x setup.sh
./setup.sh
```

The setup script will:

- Ask where to install the vault (default: `~/claude-stow`)
- Copy the vault template
- Inject the session and checkpoint hooks into `~/.claude/settings.json`
- Install the memory-writer subagent to `~/.claude/agents/`

> **Note:** Keep the cloned repo in place after running setup. The hooks point to scripts inside it — moving or deleting the repo breaks the hooks. The repo contains only installable source files. Your vault (where project context lives) is a separate directory created during setup.

After setup:

1. Open `~/claude-stow/Global/CONTEXT.md` and fill in your identity, stack, and cross-project constraints — package manager preferences, git conventions, infrastructure defaults, anything that applies across all your projects.
2. The setup script will print a block to paste into `~/.claude/CLAUDE.md`. That file is Claude's global instruction file — it controls how Claude behaves across all sessions. The block tells Claude Code to read your vault at session start. If the file doesn't exist yet, create it. If it does, paste the block at the end.
3. Start a Claude Code session from your project directory. Context loads automatically.

---

## Keeping context in the right place

`~/.claude/CLAUDE.md` and `Global/CONTEXT.md` serve different purposes and should not duplicate each other.

| File                  | Carries                                                                                                                                                         |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.claude/CLAUDE.md` | Instructions — how Claude should behave, communicate, and format output. Behavioral rules, vault routing protocol, skills index, operational limits.            |
| `Global/CONTEXT.md`   | Facts — who you are, your stack defaults, your cross-project constraints, your active projects. Things Claude should _know_, not instructions about how to act. |

A common mistake is putting stack conventions (package manager, git rules, infrastructure defaults) in both places. Put them in `Global/CONTEXT.md` only. `CLAUDE.md` already tells Claude to read that file at session start — there's no need to repeat yourself.

---

## Vault structure

```
~/claude-stow/
├── Global/
│   ├── CONTEXT.md       ← who you are, your stack, cross-project constraints
│   └── DECISIONS.md     ← graveyard for rejected approaches
└── Projects/
    └── your-project/
        ├── STATUS.md    ← where you left off, next steps (loads every session)
        ├── CONTEXT.md   ← what the project is, stack, key details (load on demand)
        └── DECISIONS.md ← locked decisions and rationale (search on demand)
```

`Global/CONTEXT.md` and `STATUS.md` load every session. `CONTEXT.md` and `DECISIONS.md` load only when the task requires them, keeping the active context window lean.

---

## Adding a new project

The easiest way — just tell Claude directly, in either Claude Code or Desktop:

```
New project: [name]. Update the vault with CONTEXT.md and STATUS.md and let's begin work.
```

Claude will create the files, ask what it needs to know, and start the session. No command line required.

If you prefer to set up the files yourself first, the script creates the folder structure:

```bash
./scripts/new-project.sh my-project
```

Either way, `STATUS.md` is the highest priority to fill in — it loads every session. `CONTEXT.md` and `DECISIONS.md` can wait until there's something worth locking down.

---

## How vault updates happen

**Automatically on session close** — the checkpoint hook fires when the session ends, extracts the conversation from the session JSONL, and launches a Haiku subprocess that reads the transcript and updates STATUS.md and DECISIONS.md. This runs in the background — you don't wait for it. Check `~/.claude/stow-checkpoint.log` to see what was written.

Sessions with fewer than 3 user turns are skipped (accidental opens, quick lookups).

**Manually during a session** — say "Lock this: [decision]" or "Update the vault" and Claude will use the memory-writer subagent to make surgical updates within the active session. Useful for capturing something mid-work without closing the session.

**Session prompts** — these are optional but available:

```
# Capture a mid-session decision immediately
Lock this: [decision]. Update DECISIONS.md now.

# Load deeper context when needed
Pull the full CONTEXT.md and DECISIONS.md for [project] — I need the full picture before we proceed.

# Explicit session close (still works, runs before the background subprocess)
Close the session — update STATUS.md and DECISIONS.md with everything from today.
```

---

## Extending with rules/

Claude Code supports a `.claude/rules/` directory that lets you define conditional instructions scoped to specific file paths — enforcing code style rules only when editing a particular module, or injecting API conventions when touching certain directories.

This isn't included in the base `claude-stow` setup intentionally. Rules are most useful once a project has settled conventions worth encoding. Writing them on day one means inventing constraints for a codebase that doesn't exist yet.

Once your project has real patterns, start a Claude Code session and say:

> "This project has settled conventions. Let's build out .claude/rules/ to enforce them automatically."

Claude will walk the codebase, identify what's worth encoding, and create the rule files.

> **Note:** There are known open bugs in the rules implementation in recent Claude Code releases. Test before relying on them for anything critical.

---

## Claude Desktop bridge

The checkpoint hook only runs in Claude Code — Desktop sessions don't fire Stop events. But the vault is just files. If you do planning or exploratory thinking in Desktop and want that context in your Code sessions, write it to the vault manually:

```
Update my vault for [project]: we decided to [decision]. Next steps are [X, Y, Z].
```

For Desktop to write to vault files, configure the vault directory as an allowed path in your Desktop MCP settings, or use any text editor — the files are plain markdown. Desktop sessions can reference vault files by path for read access without any additional setup.

---

## Portability

The hook system is Claude Code-specific — it uses `settings.json` lifecycle hooks that only Claude Code supports. The vault itself (plain markdown files) is tool-agnostic. Adapting `claude-stow` for Cursor, Windsurf, or any other tool that supports session hooks is straightforward — the vault stays the same, only the hook layer changes.

---

## Requirements

- macOS or Linux
- `jq`
- `python3`
- Claude Code (for the checkpoint subprocess)

---

## License

MIT
