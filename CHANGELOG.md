# Changelog

## [0.5.5] - 2026-03-23

### Added
- **Configurable security policy** — 5 levels from `:sandbox` (0) to `:danger` (4), with fine-grained `allow_receiver`/`block_method` overrides
- **Environment variable config** — `MANA_MODEL`, `MANA_VERBOSE`, `MANA_TIMEOUT`, `MANA_BACKEND`, `MANA_SECURITY`
- **Verbose mode** — `c.verbose = true` logs LLM calls, tool usage, and results to stderr
- **API key validation** — clear `ConfigError` with setup instructions instead of cryptic HTTP 401
- **Long-term memory deduplication** — identical content is no longer stored twice
- **Current prompt overrides memory** — explicit priority rule in system prompt
- **Ruby 4.0 support** — CI tests Ruby 3.3, 3.4, and 4.0

### Fixed
- `write_var` works on Ruby 4.0 without pre-declaring variables (singleton method fallback)
- Blocked Ruby introspection methods (`methods`, `local_variables`, etc.) in `call_func`
- LLM retries once when model skips tool calling and returns text only
- Long-term memory stored in `~/.mana/` instead of platform-specific paths
- Default model changed to `claude-sonnet-4-6`
- Compiler uses isolated binding to prevent `generate()` recursion
- Cache files named by source path with prompt hash validation

### Removed
- Polyglot engine system (JavaScript, Python, language detection)
- `mini_racer` and `pycall` dependencies
- `ObjectRegistry`, `RemoteRef`, engine capability queries

## [0.5.3] - 2026-03-22

### Added
- **Timeout configuration** — `timeout` option in `Mana.configure` (default: 120 seconds)

## [0.5.2] - 2026-03-22

### Added
- **API URL endpoint configuration** — `effective_base_url` auto-resolves per backend
- `ANTHROPIC_API_URL` / `OPENAI_API_URL` environment variables
- API key fallback: `ANTHROPIC_API_KEY` → `OPENAI_API_KEY`

## [0.4.0] - 2026-02-22

- Multi-LLM backend — Anthropic + OpenAI-compatible APIs
- Test mode — `Mana.mock` + `mock_prompt` for stubbing LLM responses

## [0.3.1] - 2026-02-21

- Nested prompts — LLM calling LLM
- Lambda `call_func` support

## [0.3.0] - 2026-02-21

- Automatic memory — context sharing across LLM calls
- Incognito mode
- Persistent long-term memory

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
