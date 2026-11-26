# Yaci Lens skill

An agent skill for querying **Cardano mainnet data with SQL**, over the public Yaci Lens data lake
(`https://data.bloxbean.org/mainnet/v1/`): Yaci Store's export as Apache Parquet with a DuckLake catalog, published
daily to Cloudflare R2. There's no server, API key or account: the agent runs DuckDB locally, and DuckDB reads only the
parts of the remote files a query needs.

The same data powers [Yaci Lens](https://github.com/bloxbean/yaci-lens), the serverless Cardano analytics explorer.

```
yaci-lens/
  SKILL.md               what the data is, how to query it, rules that keep queries fast and correct
  scripts/query.sh       DuckDB CLI wrapper: attaches the catalog, UTC, summary-pack variable
  scripts/query.py       the same with the duckdb Python package
  scripts/gen-schema.sh  regenerates reference/schema.md from the live catalog
  reference/schema.md    every table: partition column, rows, size, columns; plus the summary pack
  reference/cookbook.md  tested queries for common questions
```

## Install

**Requirements:** a shell, network access to `data.bloxbean.org` and `extensions.duckdb.org` (DuckDB downloads the
`ducklake` extension once), and DuckDB 1.5+ as a CLI (`brew install duckdb`) or Python package (`pip install "duckdb>=1.5"`).

- **Claude Code:** copy or link the skill folder into your skills directory:
  ```bash
  ln -s "$PWD/yaci-lens" ~/.claude/skills/yaci-lens          # personal
  # or, for one project: ln -s "$PWD/yaci-lens" <project>/.claude/skills/yaci-lens
  ```
  Then ask, e.g. "How did Cardano transaction volume change over the last 30 days?" or "Which pools made the most
  blocks in epoch 668?". Claude loads the skill and runs `scripts/query.sh`.
- **Claude Desktop / claude.ai:** zip the `yaci-lens` folder (`zip -r yaci-lens.zip yaci-lens`) and upload it under
  Settings → Capabilities → Skills. Code execution must be on, and its sandbox must be allowed to reach
  `data.bloxbean.org` and `extensions.duckdb.org`. If the sandbox blocks that egress, use Claude Code, or the MCP
  server on the roadmap.
- **Other agents** (Codex, Cursor, …): `SKILL.md` is plain Markdown. Point the agent at it (e.g. from `AGENTS.md`)
  and make sure DuckDB is installed.

## Maintenance

- After yaci-store schema changes, run `yaci-lens/scripts/gen-schema.sh` and commit `reference/schema.md`.
- To check the cookbook still runs, run each query with `scripts/query.sh`. Every query was verified on 2026-11-25
  against data through 2026-11-24.
- Point at another deployment with `LENS_CATALOG_URL` / `LENS_SUMMARY_URL`.

## Roadmap: serverless MCP

An MCP server that exposes the lake as tools (`describe_tables`, `query`, `summary`) for clients that can't run a shell.
Options to evaluate:
- A local stdio server (`npx yaci-lens-mcp`) on DuckDB's Node bindings. No hosting at all.
- A remote MCP on Cloudflare Workers with DuckDB-WASM. Worker memory and CPU limits cap query size, but summary-pack
  and single-partition queries fit.
- A remote MCP on Cloudflare Containers running the DuckDB CLI, for unrestricted queries.

## License

MIT
