# claude-lore

Persistent project memory for Claude Code. Context survives session boundaries. No database, no background service, no infrastructure.

---

## The problem

Claude Code's native memory continues to improve. Auto Memory takes notes during sessions. Auto Dream consolidates them between sessions, pruning contradictions, keeping things current.

That covers what Claude _observed_. It doesn't cover what you need Claude to _know from the start_ — context you authored deliberately, that you can read and correct, that exists before the first session begins.

> **Claude Desktop users:** Auto Memory and Auto Dream are Claude Code-only features. Desktop sessions have no equivalent native memory — `claude-lore` fills that gap directly, not just as a complement to native memory but as a primary persistence layer.

The decisions you made before Claude was in the room. The constraints that aren't obvious from the code. The approaches you already tried and rejected. The current state of something half-finished. That context doesn't emerge from observation — it has to be written intentionally.

`claude-lore` is where you put that.

---

## What "lore" means here

Lore is the accumulated knowledge of a world — the history, the decisions, the reasons things are the way they are. Every project has its own lore: the stack decisions, the rejected approaches, the constraints, the current state. `claude-lore` is where that lives.

---

## How it works

Four pieces work together:

**The vault** — a folder of markdown files, one for global context and one per project. You write them. You own them. They're just text files.

**The session hook** — a small script that runs at the start of every Claude Code session. It reads your vault and injects the right context automatically. You don't think about it.

**The checkpoint hook** — runs before Claude Code compacts the context window. It tells Claude to update your vault files before anything is lost. The automated equivalent of "save your work."

**MCPVault** — lets Claude update your vault files surgically during a session: appending a decision, updating a status, writing a note. The vault stays current without manual effort.

No database. No running processes. No port 37777.

---

## Compared to alternatives

**[claude-mem](https://github.com/thedotmack/claude-mem)** captures everything Claude does automatically and compresses it with AI. Powerful, but requires a persistent background service, SQLite, a vector database, and Bun. The memory it produces is machine-written — you don't read or edit it directly.

**[Continuous-Claude](https://github.com/parcadei/Continuous-Claude-v3)** is a full agent orchestration framework — 109 skills, 32 agents, 30 hooks, Docker, PostgreSQL, and a 12-step setup wizard. Different scope entirely.

`claude-lore` is for the developer who wants their context to survive session boundaries and nothing else. Install time is under 15 minutes. The only dependency beyond standard Unix tools is `jq`.

---

## Install

```bash
git clone https://github.com/jmsmrgn/claude-lore.git
cd claude-lore
chmod +x setup.sh
./setup.sh
```

The setup script will:

- Ask where to install the vault (default: `~/claude-lore`)
- Install MCPVault if needed
- Copy the vault template
- Inject the session hook into `~/.claude/settings.json`

> **Note:** Keep the cloned repo in place after running setup. The hook points to `hooks/inject-context.sh` inside it — moving or deleting the repo breaks the hook.

After setup:

1. Open `~/claude-lore/Global/CONTEXT.md` and fill in your identity, stack, and cross-project constraints — package manager preferences, git conventions, infrastructure defaults, anything that applies across all your projects.
2. Add the vault protocol to `~/.claude/CLAUDE.md` — the setup script will print the exact block to paste. This tells Claude Code to read your project's STATUS.md at session start and update vault files at session end.
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
~/claude-lore/
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

```bash
./scripts/new-project.sh my-project
```

Creates the project folder with stub files ready to fill in. Pass an optional repo path to also generate a project-scoped `CLAUDE.md`:

```bash
./scripts/new-project.sh my-project ~/git/my-project
```

---

## How vault updates happen

**During a session** — Claude uses MCPVault's `patch_note` tool to make surgical updates: appending a decision, changing a status line, updating next steps. This runs in an isolated subagent context so it doesn't pollute the main session's context window.

**At compaction** — when Claude Code's context window fills and compacts (configurable, default ~50%), the checkpoint hook fires automatically. Claude updates `STATUS.md` and `DECISIONS.md` before compaction runs. Nothing is lost.

You can also trigger a manual update at any time by saying `close the session` — Claude will write a full session summary to your vault files.

---

## Why MCPVault and not a CLI tool

Some Claude Code workflows prefer CLI tools over MCP servers for simplicity. MCPVault is the right choice here for two reasons:

- `patch_note` provides structured confirmation that a write succeeded, which Claude uses to verify vault updates mid-session rather than assuming success.
- MCPVault works in Claude Desktop, where bash isn't available — relevant if you use Desktop for planning and Code for execution (see [Claude Desktop bridge](#claude-desktop-bridge) below).

---

## Extending with rules/

Claude Code supports a `.claude/rules/` directory that lets you define conditional instructions scoped to specific file paths — enforcing code style rules only when editing a particular module, or injecting API conventions when touching certain directories.

This isn't included in the base `claude-lore` setup intentionally. Rules are most useful once a project has settled conventions worth encoding. Writing them on day one means inventing constraints for a codebase that doesn't exist yet.

Once your project has real patterns, start a Claude Code session and say:

> "This project has settled conventions. Let's build out .claude/rules/ to enforce them automatically."

Claude will walk the codebase, identify what's worth encoding, and create the rule files.

> **Note:** There are known open bugs in the rules implementation in recent Claude Code releases. Test before relying on them for anything critical.

---

## Claude Desktop bridge

If you use Claude Desktop for planning and Claude Code for execution, point the MCPVault server in your Desktop MCP config at the same vault directory. Context you write in Desktop sessions becomes available to Claude Code sessions automatically.

This is optional. `claude-lore` works entirely within Claude Code without it.

---

## Portability

The hook system is Claude Code-specific — it uses `settings.json` lifecycle hooks that only Claude Code supports. The vault itself (markdown files + MCPVault) is tool-agnostic. Adapting `claude-lore` for Cursor, Windsurf, or any other tool that supports session hooks is straightforward — the vault stays the same, only the hook layer changes.

---

## Requirements

- macOS or Linux
- `jq`
- `node` (for MCPVault)
- Claude Code

---

## License

MIT
