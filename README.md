# claude-lore

Persistent project memory for Claude Code. Context survives session boundaries. No database, no background service, no infrastructure.

---

## The problem

Every Claude Code session starts blank. You explain the project. You explain the decisions. You explain why you made the call you made three weeks ago. Then the session ends and you do it again.

Claude Code's native memory has gotten better lately. Auto Memory lets Claude take its own notes during a session — build commands, debugging patterns, architecture decisions. Auto Dream, a newer background process, consolidates those notes between sessions, pruning stale entries and resolving contradictions.

That handles what Claude _observed_. It doesn't handle what you need Claude to _understand_.

The decisions you made before Claude was in the room. The constraints that aren't obvious from the code. The approaches you already tried and rejected. The current state of something half-finished. That context doesn't emerge from observation — it has to be written intentionally.

`claude-lore` is where you put that. The two systems are complementary: native memory captures session history automatically, `claude-lore` carries the strategic context you'd otherwise re-explain every time.

---

## What "lore" means here

Lore is the accumulated knowledge of a world — the history, the decisions, the reasons things are the way they are. Every project has its own lore. The stack decisions, the rejected approaches, the constraints, the current state. `claude-lore` is where that lives.

---

## How it works

Three pieces work together:

**The vault** is a folder of markdown files — one for global context, one per project. You write them. You own them. They're just text files.

**The hook** is a small script that runs at the start of every Claude Code session. It reads your vault and injects the right context automatically. You don't think about it.

**MCPVault** is a tool that lets Claude update your vault files surgically during a session — appending a decision, updating a status, writing a note. The vault stays current without manual effort.

That's the whole system. No database, no running processes, no port 37777.

---

## Compared to alternatives

[claude-mem](https://github.com/thedotmack/claude-mem) captures everything Claude does automatically and compresses it with AI. Powerful, but it requires a persistent background service, SQLite, a vector database, and Bun. The memory it produces is machine-written — you don't read or edit it directly.

[Continuous-Claude](https://github.com/parcadei/Continuous-Claude-v3) is a full agent orchestration framework — 109 skills, 32 agents, 30 hooks, Docker, PostgreSQL, and a 12-step setup wizard. Different scope entirely.

`claude-lore` is for the developer who wants their context to survive session boundaries and nothing else. Install time is under 15 minutes. The only dependency beyond standard Unix tools is `jq`.

---

## Install

```bash
git clone https://github.com/jmsmrgn/claude-lore.git
cd claude-lore
chmod +x setup.sh
./setup.sh
```

The setup script will ask where to install the vault (default: `~/claude-lore`), install MCPVault if needed, copy the vault template, and inject the session hook into `~/.claude/settings.json`.

**Note:** Keep the cloned repo in place after running setup. The hook points to `hooks/inject-context.sh` inside it — moving or deleting the repo breaks the hook.

After setup, open `~/claude-lore/Global/CONTEXT.md`, fill in your identity and stack, and start a Claude Code session. Context loads automatically from there.

---

## Vault structure

```
~/claude-lore/
├── Global/
│   ├── CONTEXT.md       ← who you are, your stack, cross-project constraints
│   └── DECISIONS.md     ← graveyard for rejected approaches
└── Projects/
    └── your-project/
        ├── CONTEXT.md   ← what the project is, current state, key decisions
        ├── STATUS.md    ← where you left off, next steps
        └── DECISIONS.md ← locked decisions and rationale
```

Global context loads every session. Project context loads when you're working in that project's directory.

---

## Adding a new project

```bash
./scripts/new-project.sh my-project
```

Creates the project folder with stub files ready to fill in.

---

## Extending with rules/

Claude Code supports a `rules/` directory (`.claude/rules/`) that lets you define conditional instructions scoped to specific files or paths — enforcing code style rules only when editing a particular module, or injecting API conventions when touching certain directories.

This isn't included in the base `claude-lore` setup, and that's intentional. Rules are most useful once a project has settled conventions worth encoding. Writing them on day one means inventing constraints for a codebase that doesn't exist yet.

Once your project has real patterns — naming conventions, architectural decisions, workflows that repeat — add rules by starting a Claude Code session and saying:

> "This project has settled conventions. Let's build out .claude/rules/ to enforce them automatically."

Claude will walk the codebase, identify what's worth encoding, and create the rules files. Note: there are known open bugs in the rules implementation in recent Claude Code releases. Test before relying on them for anything critical.

---

## Claude Desktop bridge

If you use Claude Desktop for planning and Claude Code for execution, point the MCPVault server in your Desktop MCP config at the same vault directory. Notes you write in Desktop sessions become available to Claude Code sessions automatically.

This is optional. `claude-lore` works entirely within Claude Code without it.

---

## Portability

The hook system is Claude Code-specific — it uses `settings.json` lifecycle hooks that only Claude Code supports. The vault itself (the markdown files and MCPVault layer) is tool-agnostic. Adapting `claude-lore` for Cursor, Windsurf, or any other tool that supports session hooks is straightforward — the vault stays the same, only the hook layer changes.

---

## Requirements

- macOS or Linux
- `jq`
- `node` (for MCPVault)
- Claude Code

---

## License

MIT
