---
name: yaci-lens
description: Query Cardano mainnet data (blocks, transactions, UTxOs, stake, rewards, pools, governance, DReps, scripts, metadata, ada pots) with SQL over the public Yaci Lens data lake, using the DuckDB CLI with no API key or server. Use when asked about Cardano on-chain history or analytics, e.g. transactions or fees per day or epoch, a block or transaction's details, stake distribution, rewards, pool performance, treasury and reserves, governance actions and votes, DRep voting power, script usage, token minting, or metadata.
---

# Yaci Lens: Cardano data with SQL

The Yaci Lens data lake is Cardano mainnet indexed by Yaci Store and published daily as Apache Parquet files with a
DuckLake catalog, at `https://data.bloxbean.org/mainnet/v1/`. Anyone can query it with DuckDB 1.5+ over HTTPS.
DuckDB reads only the parts of the files a query needs. It's a **daily snapshot, not live**: check the tip first.

## Run a query

```bash
scripts/query.sh "SELECT * FROM read_parquet(getvariable('summary') || 'about.parquet')"   # what the data covers
scripts/query.sh "SELECT count(*) FROM block WHERE date = DATE '2026-11-24'"
scripts/query.sh -csv -f my_query.sql      # -csv / -json / -line output
```

`scripts/query.sh` (in this skill's folder) needs the `duckdb` CLI 1.5 or newer (`brew install duckdb`, or a release
from duckdb.org). Without the CLI, use `python3 scripts/query.py "SQL"` (`pip install "duckdb>=1.5"`; `--csv` for CSV). It attaches the catalog as `lake` and makes it the default database, so `block` means `lake.block`.
It also attaches the DuckLake metadata tables as `lake_meta`, sets the session time zone to UTC, and sets
`getvariable('summary')` to the summary-pack folder URL. If the `duckdb-skills` query skill is available, use the same
prelude:

```sql
INSTALL ducklake; LOAD ducklake; SET TimeZone = 'UTC';
ATTACH 'https://data.bloxbean.org/mainnet/v1/catalog.ducklake' AS lake (TYPE ducklake, READ_ONLY);
USE lake;
```

## Rules that keep queries fast and correct

1. **Always filter big tables on their partition column.** Every table is partitioned by `date` (UTC day) or `epoch`
   (see `reference/schema.md`). With the filter, DuckDB opens a few files; without it, it opens thousands at about
   0.1–0.3 s each, which can take many minutes. A `WHERE number = …` or `WHERE epoch = …` on `block` also prunes, because
   the catalog has per-file min/max statistics.
2. **History-wide questions: use the summary pack first.** These are one small file each, rebuilt daily:
   `epochs` (per-epoch activity, ada pots, active stake), `daily` (per-day txs, fees, script txs, mints),
   `staking_daily` (certificates, delegations, withdrawals per day), `staking_epochs` (rewards by type, Nakamoto
   coefficient, top-10/100 share), `drep_epochs` (DRep vs Abstain vs No-confidence power), `latest_blocks`,
   `pools`, `governance`, `dreps`, `pool_meta` / `drep_meta` / `action_meta` (hash-checked off-chain metadata:
   pool ticker and name, DRep name and profile, proposal title and texts), `script_index`, `tx_index`, `about`.
   Governance: `votes` (every vote; the latest per voter and action counts), `drep_power` (each DRep's power per
   epoch). Smart contracts: `script_daily` (per day and Plutus script: txs, redeemers, fees of those txs, execution
   units, purposes), `script_totals`, `script_names` (dApp labels from the Strica and CRFA registries; join on
   `script_hash`). Native assets: `asset_tokens` (fungible tokens with decoded `name`, supply, 30-day policy
   activity), `asset_policies`, `asset_mint_daily`, `asset_daily` and `token_daily` (last 365 days of token
   transactions), `asset_index` (names the index files under `index/` for lookups of any asset by unit or
   fingerprint). Read them with `FROM read_parquet(getvariable('summary') || 'epochs.parquet')`. Their amounts are
   ADA as `DOUBLE`; `script_daily` counts a transaction's fee once for each script it ran.
3. **Amounts in lake tables are lovelace** (exact `DECIMAL(38,0)` or `BIGINT`). Divide by 1e6 for ADA.
4. **Lookups by hash need a day.** `transaction`, `address_utxo`, `tx_input`, `datum` and `script` are partitioned by
   day, and hashes are random, so a hash alone means scanning every day. Find the day first:
   - For a transaction hash: the **tx index** (see `reference/cookbook.md`, "Find a transaction by hash"). This is
     also how to resolve an input (`tx_hash#index`): its output is in `address_utxo` on the day its tx was made.
   - From a block number: `SELECT date FROM block WHERE number = N` (fast).
   - For a script hash: `script_index` in the summary pack gives the day of its `script` partition.
5. **Stake snapshots:** `epoch_stake.epoch` is the epoch the snapshot was taken. That stake is active in
   `active_epoch` = epoch + 2. "Active stake in epoch E" is `WHERE epoch = E - 2`.
6. **Identifiers:** pool ids are hex key hashes (`block.slot_leader`, `epoch_stake.pool_id`), not `pool1…` bech32.
   Stake addresses are bech32 (`stake1…`). DRep ids in `drep_dist`/`dreps` are bech32 (`drep1…`).
7. **Dates and times are UTC.** `date` is the UTC day of the block. The current epoch is partial; the newest
   complete epoch is `tip_epoch - 1`. The `epochs` summary (and the `epoch` table) has complete epochs only, while
   `adapot` already has a row for the current epoch.
8. **Ada pots are taken at the epoch boundary.** `adapot` (and `treasury_ada` / `reserves_ada` in `epochs`) for
   epoch E is the value at the start of E (`adapot.slot` is the boundary slot).
9. **Pool names** come from `pool_meta` (ticker, name; use rows with `fetched AND hash_ok`). DRep names from
   `drep_meta.given_name`, proposal titles from `action_meta.title`. These are self-declared. To show `pool1…` ids, bech32-encode the hex hash with hrp `pool`, e.g.
   `python3 -c "import sys;from bech32 import bech32_encode,convertbits;print(bech32_encode('pool',convertbits(bytes.fromhex(sys.argv[1]),8,5)))" <hex>`
   (`pip install bech32`), or show the hex.
10. Address-wide history (all activity of one address since genesis) has no index: say so, and offer a date range.

## Reading the answer back

- Say what the data covers ("data through 2026-11-24, tip block #…") when the question is about "now" or "latest".
- Show the SQL you ran, so the user can rerun it here or in the Yaci Lens SQL lab.
- Round ADA sensibly and keep lovelace when exactness matters.

## References

- `reference/schema.md`: every table with its partition column, row count, size and columns, plus the summary pack.
  Regenerate it with `scripts/gen-schema.sh`.
- `reference/cookbook.md`: tested query patterns for common questions.
