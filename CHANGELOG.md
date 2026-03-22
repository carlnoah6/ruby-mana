# Changelog

## [0.5.4] - 2026-03-22

### Added
- **Ruby 4.0 support** — relaxed `binding_of_caller` and `mini_racer` version constraints, CI now tests Ruby 3.3, 3.4, and 4.0

### Fixed
- Fixed `RubyBridge` constant path in Python engine spec
- Fixed Python-dependent tests to skip gracefully when pycall is not available

## [0.5.3] - 2026-03-22

### Added
- **Timeout configuration** — `timeout` option in `Mana.configure` sets HTTP timeout (open + read) for LLM requests (default: 120 seconds). Closes #31

## [0.5.2] - 2026-03-22

### Added
- **API URL endpoint configuration** — `effective_base_url` auto-resolves the correct default URL per backend
- Support for `ANTHROPIC_API_URL` and `OPENAI_API_URL` environment variables
- API key fallback: `ANTHROPIC_API_KEY` → `OPENAI_API_KEY`
- GitHub Actions workflow for automated issue fixing via Claude Code
- GPT-5.4 independent code review workflow with auto-merge

## [0.5.1] - 2026-02-24

### Changed
- **Engine capability refactor** — replaced three redundant capability flags (`supports_remote_ref?`, `supports_bidirectional?`, `supports_state?`) with a single `execution_engine?` method
- Clearer semantics: execution engines (Ruby/JS/Python) vs reasoning engines (LLM)
- Fully backward compatible — old methods still work as derived properties

## [0.5.0] - 2026-02-22

### Added
- **Polyglot engine architecture** — run Ruby, JavaScript, and Python code side by side
- JavaScript engine via `mini_racer` with automatic variable bridging
- Python engine via `pycall` with automatic variable bridging
- Bidirectional Python ↔ Ruby calling through pycall bridge
- Engine interface abstraction (`Mana::Engines::Base`)
- Language auto-detection for polyglot dispatch

### Changed
- Refactored LLM logic into `Engines::LLM`, extracted from monolithic core

### Fixed
- Polyglot engine bug fixes (CodeRabbit review feedback)

## [0.4.0] - 2026-02-22

- Multi-LLM backend — Anthropic + OpenAI-compatible APIs
- Test mode — `Mana.mock` + `mock_prompt` for stubbing LLM responses

## [0.3.1] - 2026-02-21

- Nested prompts — LLM calling LLM
- Lambda `call_func` support
- Expanded test coverage

## [0.3.0] - 2026-02-21

- Automatic memory — context sharing across LLM calls
- Incognito mode
- Persistent long-term memory
- `Mana.session` — shared conversation context across prompts

## [0.2.0] - 2026-02-20

- Custom effect handlers — user-defined LLM tools
- `mana def` — LLM-compiled methods with file caching
- Auto-discover functions via Prism introspection

## [0.1.0] - 2026-02-19

- Initial release
- `~"..."` syntax for embedding LLM prompts in Ruby
- Effect system: read_var, write_var, read_attr, write_attr, call_func
- Anthropic Claude backend
- Variable binding via `<var>` convention
