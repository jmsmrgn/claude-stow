# claude-lore

Persistent project memory that follows Claude across sessions. No database, no background service, no infrastructure.

Every project has lore: the decisions made before Claude was in the room, the approaches already tried, the reasons things are the way they are. This is where you keep it.

Most workflows already start with a plan. This is for everything that happens after.

---

## The problem with static context

Claude's native memory continues to improve — in Claude Code, Auto Memory takes notes during sessions, and Auto Dream consolidates them between sessions, pruning contradictions, keeping things current.

That covers what Claude _observed_. It doesn't cover what you need Claude to _know from the start_ — context you authored deliberately, that you can read and correct, that exists before the first session begins.

Many users already solve this with a `CLAUDE.md` and a project context file. That's the right instinct. But a file you write before the project begins reflects what was true at the time of writing. It goes stale. Decisions accumulate, approaches get rejected, the current state shifts — and none of that finds its way back into the file unless you put it there manually.

`claude-lore` starts the same way: intentional foundation you write. But from there, Claude maintains it. Every decision appends. Every session patches the previous state. The context is always current because the project informs it, not because you remembered to update it.

> **Claude Desktop users:** Auto Memory and Auto Dream are Claude Code-only features. Desktop sessions have no equivalent native memory — `claude-lore` fills that gap directly, not just as a complement to native memory but as a primary persistence layer. Point both at the same vault and context from Desktop thinking is available the moment you open Code.

The constraints that aren't obvious from the code. The approaches you already tried and rejected. The current state of something half-finished. That context doesn't emerge from observation — it has to be written intentionally. And then it has to stay current.

`claude-lore` is where you put that.

---

## How it works

Four pieces work together:

**The vault** — a folder of markdown files, one for global context and one per project. You write them. You own them. They're just text files.

**The session hook** — a small script that runs at the start of every Claude Code session. It reads your vault and injects the right context automatically. You don't think about it.

**The checkpoint hook** — runs after every Claude response (Stop event), rate-limited to fire an instruction every 5 turns by default (configurable). It tells Claude to update your vault files periodically without waiting for you to ask. The automated equivalent of "save your work."

**[MCPVault](https://github.com/bitbonsai/mcpvault)** — lets Claude update your vault files surgically during a session: appending a decision, updating a status, writing a note. The vault stays current without manual effort.

No database. No running processes. No port 37777.

---

## Compared to alternatives

**[claude-mem](https://github.com/thedotmack/claude-mem)** captures everything Claude does automatically and compresses it with AI. Powerful, but requires a persistent background service, SQLite, a vector database, and Bun. The memory it produces is machine-written — you don't read or edit it directly.

**[Continuous-Claude](https://github.com/parcadei/Continuous-Claude-v3)** is a full agent orchestration framework — 109 skills, 32 agents, 30 hooks, Docker, PostgreSQL, and a 12-step setup wizard. Different scope entirely.

`claude-lore` is for the user who wants their context to survive session boundaries and nothing else. Dependencies are node, jq, and MCPVault (handled automatically by the setup script).

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

> **Note:** Keep the cloned repo in place after running setup. The hook points to `hooks/inject-context.sh` inside it — moving or deleting the repo breaks the hook. The repo contains only installable source files. Your vault (where project context lives) is a separate directory created during setup.

After setup:

1. Open `~/claude-lore/Global/CONTEXT.md` and fill in your identity, stack, and cross-project constraints — package manager preferences, git conventions, infrastructure defaults, anything that applies across all your projects.
2. The setup script will print a block to paste into `~/.claude/CLAUDE.md`. That file is Claude's global instruction file — it controls how Claude behaves across all sessions. The block tells Claude Code to read your vault at session start and write back to it at session end. If the file doesn't exist yet, create it. If it does, paste the block at the end.
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

The easiest way — just tell Claude directly, in either Claude Code or Desktop:

```
New project: [name]. Update the vault with CONTEXT.md and STATUS.md and let's begin work.
```

Claude will create the files, ask what it needs to know, and start the session. No command line required.

If you prefer to set up the files yourself first, the script creates the folder structure:

```bash
./scripts/new-project.sh my-project
```

Pass an optional repo path to also generate a project-scoped `CLAUDE.md`:

```bash
./scripts/new-project.sh my-project ~/git/my-project
```

Either way, `STATUS.md` is the highest priority to fill in — it loads every session. `CONTEXT.md` and `DECISIONS.md` can wait until there's something worth locking down. See [Vault structure](#vault-structure) for what belongs in each file.

---

## How vault updates happen

**During a session** — Claude uses MCPVault's `patch_note` tool to make surgical updates: appending a decision, changing a status line, updating next steps. This runs via the memory-writer subagent — a lightweight Haiku agent installed to `~/.claude/agents/` by the setup script — in an isolated context window so vault I/O never pollutes the main session.

**Periodically** — the checkpoint hook fires after every Claude response and emits a vault update instruction every 5 turns (adjustable via `WRITE_EVERY` in `hooks/session-checkpoint.sh`). Claude updates `STATUS.md` and `DECISIONS.md` automatically in the background.

You can also trigger a manual update at any time by saying `close the session` — Claude will write a full session summary to your vault files.

---

## Session prompts

The session hook and checkpoint hook handle context automatically in Claude Code. But when you're resuming work, switching environments, or need to pull in deeper context mid-session, these are the prompts to reach for.

**Resuming a project:**
```
Check the vault for [project] context and resume from where we left off.
```

**Loading deeper context when needed:**
```
Pull the full CONTEXT.md and DECISIONS.md for [project] — I need you to understand the full picture before we proceed.
```

**Closing a session:**
```
Close the session — update STATUS.md and DECISIONS.md with everything from today.
```

**Capturing a decision mid-session:**
```
Lock this: [decision]. Update DECISIONS.md now.
```

Any natural phrasing works. The key is referencing the vault explicitly so Claude knows to read the files rather than rely on what's already in context.

**Claude Desktop users:** the hook doesn't fire in Desktop sessions, so the resume prompt is load-bearing, not optional. Start every Desktop session with it. The MCPVault MCP server must also be configured in your Desktop MCP config pointing at the same vault directory — see [Claude Desktop bridge](#claude-desktop-bridge).

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

Some of the most important project context emerges in conversations that never touch a codebase — exploring tradeoffs, stress-testing an approach, working through something ambiguous before committing to a direction. That kind of unstructured thinking is where Desktop earns its place. Claude Code is where you build. The vault is what connects them.

Point both at the same vault and nothing gets lost. Context written in a Desktop session carries over to your next Claude Code session automatically.

Open `~/Library/Application Support/Claude/claude_desktop_config.json` (create it if it doesn't exist) and add MCPVault under `mcpServers`, pointing at your vault directory:

```json
{
  "mcpServers": {
    "mcpvault": {
      "command": "npx",
      "args": ["-y", "mcpvault", "--vault", "~/claude-lore"]
    }
  }
}
```

Replace `~/claude-lore` with your actual vault path if you chose a different location during setup. Restart Claude Desktop after saving.

This is optional. `claude-lore` works entirely within Claude Code without it.

---

## Portability

The hook system is Claude Code-specific — it uses `settings.json` lifecycle hooks that only Claude Code supports. The vault itself (markdown files + MCPVault) is tool-agnostic. Adapting `claude-lore` for Cursor, Windsurf, or any other tool that supports session hooks is straightforward — the vault stays the same, only the hook layer changes.

---

## Requirements

- macOS or Linux
- `jq`
- `node` (for [MCPVault](https://github.com/bitbonsai/mcpvault))
- Claude Code

---

## License

MIT
