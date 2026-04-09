# Agent Coordination

## Spawn Order

```
Phase 1  core-builder          sequential
Phase 2  scenario-implementor  sequential (requires Phase 1)
Phase 3  kibana-expert         parallel with Phase 4
Phase 4  demo-expert           parallel with Phase 3
Phase 5  qa-agent              sequential (requires 2+3+4)
```

## Agents

| Agent | File | Owns |
|-------|------|------|
| Core Builder | `core-builder.md` | cmd/, internal/, web/, elk/, scripts/, docker-compose.yml, Dockerfile, Makefile |
| Scenario Implementor | `scenario-implementor.md` | `scenarios/*/main.go`, `cmd/server/scenarios_init.go` |
| Kibana Expert | `kibana-expert.md` | `scenarios/*/setup.sh`, `scenarios/*/reset.sh`, `scenarios/*/dashboard.ndjson`, `scenarios/*/discover_url.md` |
| Demo Expert | `demo-expert.md` | `scenarios/*/README.md`, `scenarios/*/verbal_script.md`, `scenarios/*/notebooklm_prompt.md`, `scenarios/README.md` |
| QA Agent | `qa-agent.md` | `qa/report.md` (read-only elsewhere) |

## File Ownership Map

```
cmd/                    → core-builder (main.go) + scenario-implementor (scenarios_init.go)
internal/logger/        → core-builder
internal/scenarios/     → core-builder (registry.go)
web/                    → core-builder
elk/                    → core-builder
scripts/                → core-builder
docker-compose.yml      → core-builder
Dockerfile              → core-builder
Makefile                → core-builder
scenarios/*/main.go     → scenario-implementor
scenarios/*/setup.sh    → kibana-expert
scenarios/*/reset.sh    → kibana-expert
scenarios/*/dashboard.* → kibana-expert
scenarios/*/discover_*  → kibana-expert
scenarios/*/README.md   → demo-expert
scenarios/*/verbal_*    → demo-expert
scenarios/*/notebooklm* → demo-expert
agents/                 → READ ONLY (never modify)
```

## Autonomy Rules (all agents)

1. Proceed without asking.
2. When blocked: give exactly 2 options with tradeoffs. No open questions.
3. Ambiguous → pick simpler, note in comment.
4. Missing dependency → infer from PLAN.md. Don't halt.

## Worktree Rules

Switch AI agent/model mid-project → new git worktree:

```bash
# Start
git worktree add ../go-simulator-<agent> -b feat/<agent>

# Finish
git -C ../go-simulator-<agent> add -A
git -C ../go-simulator-<agent> commit -m "feat(<agent>): <summary>"
git checkout main && git merge feat/<agent>
git worktree remove ../go-simulator-<agent>
```

Branch naming: `feat/core-builder`, `feat/scenario-implementor`, `feat/kibana-expert`, `feat/demo-expert`

Merge to `main` only after QA passes for that phase.

## Invoke: Claude Code

```bash
claude --agent agents/core-builder.md

claude --agent agents/scenario-implementor.md

claude --agent agents/kibana-expert.md &
claude --agent agents/demo-expert.md &
wait

claude --agent agents/qa-agent.md
```

## Invoke: Kiro / Codex / Antigravity

Each agent file is a self-contained Markdown spec with:
- Role + context
- Exact file ownership
- Detailed per-file specs
- Constraints
- Done criteria

Load as system prompt or context document in any agent runtime.
