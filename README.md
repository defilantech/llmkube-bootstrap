# llmkube-bootstrap

Setup script + Ansible playbook that gets a fresh Apple Silicon
MacBook Pro from out-of-the-box to running local LLM inference on
[LLMKube](https://github.com/defilantech/LLMKube). One command, then
the secrets you wire in yourself.

Target: Apple Silicon MacBook Pro on macOS Sequoia (15) or later.
The default memory budget is tuned for a 128 GB machine; on smaller
hardware, lower `metal_agent_memory_fraction` in `group_vars/all.yml`
before running bootstrap. Earlier macOS versions and Intel Macs are
intentionally out of scope for v0.1.

## What it sets up

After a clean bootstrap you have:

- Homebrew + the LLMKube-supporting package set (`kubectl`, `helm`,
  `kind`, `jq`, `yq`, `gh`, `k9s`, `tmux`, `ripgrep`, `fzf`).
- `colima` started with a user-space Lima VM (4 CPU, 6 GiB, 60 GiB
  disk by default; override via `--extra-vars`). Provides the Docker
  socket `kind` uses. `docker` / `docker-compose` / `docker-buildx`
  CLIs installed via Homebrew, no Docker Desktop required. To use
  Docker Desktop instead, see the "Docker Desktop on Apple Silicon"
  callout near the end of this README.
- A `kind` cluster named `llmkube-local` running the LLMKube
  operator from the published Helm chart.
- A clone of `defilantech/LLMKube` at `~/src/LLMKube`, and the
  `metal-agent` daemon installed + running under `launchd`.
- A starter model (`phi-4-mini-instruct`, Q4_K_M) deployed via
  `Model` + `InferenceService` CRs and verified via a real chat
  completion against `localhost:<port>`.
- `opencode` installed with a sanitized config pointing at your local
  llama-server. MCP servers (`brave-search`, `github`, `context7`,
  `playwright`) are configured but inert until you supply API keys.

Optional add-ons via flags:

- `--with-carnice` — pulls
  `Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Balanced.gguf` (~36 GB) and
  deploys it as a second InferenceService. A larger MoE coder model
  serving up to 256 K context via YaRN; expect 10–40 min to download
  depending on connection.
- `--with-foreman` — installs the Foreman agentic-workload add-on
  (operator + node agent) onto the local kind cluster. See the
  [LLMKube Foreman M3 runbook](https://github.com/defilantech/LLMKube/blob/main/docs/foreman/runbook-m3.md).

## Quickstart

```bash
git clone https://github.com/defilantech/llmkube-bootstrap
cd llmkube-bootstrap
./bootstrap.sh                         # base install (phi-4-mini)
./bootstrap.sh --with-carnice          # base + Carnice 35B
./bootstrap.sh --with-foreman          # base + Foreman opt-in
./bootstrap.sh --with-foreman --with-carnice   # the works
```

On a fresh Mac, the very first `git clone` will trigger macOS to
prompt "git requires Command Line Tools, install?" — click Install,
wait ~3 min, re-run the clone. That is the only pre-prerequisite this
repo cannot pave around.

Bootstrap is idempotent. Run it again after an OS update or a chart
release to bring the install current.

## After bootstrap: secrets you wire in yourself

The playbook intentionally never touches secrets. After it finishes:

| What | Where | Used by |
|---|---|---|
| GitHub PAT | `~/.config/foreman/github-token` (or `$GITHUB_TOKEN` env) | Foreman (push branches to your fork), `gh` CLI |
| Brave Search API key | `$BRAVE_API_KEY` env (e.g. in `~/.zshrc`) | opencode's `brave-search` MCP server |
| Anthropic API key | `$ANTHROPIC_API_KEY` env | opencode's Anthropic provider, Foreman M6 planner |
| Hugging Face token | `$HF_TOKEN` env | opencode's `huggingface` MCP server, gated model downloads |
| Jira creds | `$JIRA_URL` / `$JIRA_USERNAME` / `$JIRA_API_TOKEN` env | opencode's `atlassian` MCP server |

Restart your shell (or `source ~/.zshrc`) after setting envs.

## Teardown

If you need to start from a clean slate to test a change to the
playbook:

```bash
./teardown.sh                          # removes kind cluster, launchd unit, model store
```

`teardown.sh` deliberately does NOT uninstall Homebrew, Docker
Desktop, or your shell config. It removes only what the bootstrap
created in the LLMKube layer.

## Repo layout

```
bootstrap.sh             # ensures brew + ansible, then runs the playbook
teardown.sh              # nuke the LLMKube layer for re-testing
playbook.yml             # Ansible entrypoint
inventory/localhost.yml  # always local
group_vars/all.yml       # tunables (memory_fraction, src_dir, model_repo, etc.)
roles/
  system/                # macOS sanity asserts, Xcode CLT
  homebrew/              # brew + per-package installs
  kubernetes/            # colima, kind, kubectl, helm, k9s
  llmkube_core/          # clone LLMKube, helm install, install metal-agent
  model_starter/         # download phi-4-mini, apply Model + InferenceService
  opencode/              # opencode binary + sanitized config template
  developer_tools/       # gh, jq, yq, tmux, etc.
  carnice/               # opt-in via --tags carnice
  foreman/               # opt-in via --tags foreman
files/
  opencode.json.template # the opencode config we drop into ~/.config/opencode/
.github/workflows/
  ci.yml                 # ansible-lint + yamllint + shellcheck
```

## CI

Every PR runs three linters:

- `ansible-lint` — Ansible best practices, role correctness
- `yamllint` — YAML formatting
- `shellcheck` — `bootstrap.sh` and `teardown.sh`

These run on an Ubuntu runner in seconds. They do not exercise the
playbook end-to-end — macOS-bound bugs in homebrew / launchd / colima
will only surface when a human runs the bootstrap on a real Mac. A
future change may add a nightly macOS runner that does the
full install; that's not in v0.1.

## Docker Desktop on Apple Silicon (opt-in only)

The default Docker runtime is **colima**. If you specifically want
Docker Desktop instead (for the GUI, for parity with an existing
team setup, or to test something Docker Desktop-only), opt in via
your `group_vars`:

```yaml
# group_vars/all.yml or a per-host override
homebrew_casks:
  - docker          # the cask is named `docker`; brew resolves to docker-desktop
```

Two caveats specific to Apple Silicon:

1. Docker Desktop's cask postinstall hook writes CLI plugin symlinks
   into `/usr/local/cli-plugins`. The pre-task in
   `roles/homebrew/tasks/main.yml` handles that automatically when
   `homebrew_casks` contains `docker` / `docker-desktop`.
2. Docker Desktop also writes the `docker`, `docker-compose`, and
   `docker-buildx` binaries into `/usr/local/bin`. On a fresh
   Apple Silicon Mac that directory may not exist (Homebrew lives
   at `/opt/homebrew/bin`), and `/usr/local/` is root-owned. If
   bootstrap fails here, run once:

   ```sh
   sudo mkdir -p /usr/local/bin
   sudo chown -R "$(whoami)":staff /usr/local/bin
   ./bootstrap.sh
   ```

   Subsequent runs no-op; Docker Desktop will not try to recreate
   the directory once it has user-write perms.

If neither caveat sounds appealing, the default colima path is
strictly easier.

## Contributing

This repo is small but opinionated. Two rules:

1. Roles must be idempotent. Re-running `./bootstrap.sh` on a fully
   set-up machine must converge cleanly to "ok=N changed=0" — no
   destructive operations, no half-applied state.
2. Roles must not require secrets at apply time. The secret
   inventory in this README is the contract; if a role needs a new
   secret, add it to the table.

DCO sign-off on every commit (`git commit -s`).

## License

Apache 2.0 — matches LLMKube's license.
