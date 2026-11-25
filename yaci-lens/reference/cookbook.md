# Query cookbook

Patterns for common Cardano questions. Every query was run against the lake with `scripts/query.sh`. Replace the
dates, epochs, hashes and addresses with the ones you need. Times are cold-cache wall clock from a laptop.

## What the data covers

```sql
SELECT * FROM read_parquet(getvariable('summary') || 'about.parquet');
```
`tip_date` is the last complete UTC day; `tip_epoch` is the current (partial) epoch.

## Activity over time (summary pack, about 1 s)

```sql
-- Transactions, fees and script usage per day, last 30 days
SELECT date, txs, round(fees_ada) AS fees_ada, script_txs, metadata_txs, mint_events
FROM read_parquet(getvariable('summary') || 'daily.parquet')
ORDER BY date DESC LIMIT 30;
```

```sql
-- Ada pots (at the start of each epoch) and active stake per complete epoch. Amounts here are already ADA.
SELECT epoch, round(treasury_ada / 1e6, 1) AS treasury_million_ada, round(reserves_ada / 1e9, 2) AS reserves_billion_ada,
       round(active_stake_ada / 1e9, 2) AS active_stake_billion_ada, pools, delegators, txs, round(fees_ada) AS fees_ada
FROM read_parquet(getvariable('summary') || 'epochs.parquet')
ORDER BY epoch DESC LIMIT 10;
```

```sql
-- Monthly transactions since genesis
SELECT date_trunc('month', date) AS month, sum(txs) AS txs
FROM read_parquet(getvariable('summary') || 'daily.parquet')
GROUP BY 1 ORDER BY 1;
```

## Blocks and transactions

```sql
-- Find a transaction by hash (about 6 s). The tx index maps the first 8 bytes of the hash to the UTC day;
-- summary/tx_index.parquet names the current index files.
SET VARIABLE tx_index = (SELECT list('https://data.bloxbean.org/mainnet/v1/index/' || file)
                         FROM read_parquet(getvariable('summary') || 'tx_index.parquet'));
SET VARIABLE tx_day = (SELECT max(date) FROM read_parquet(getvariable('tx_index'))
                       WHERE k = ('0x' || left('8662b5e621d183682ba855c6291f72350ef0b8dacc7e7b3e4b0d9a936569bd1c', 16))::UBIGINT);
SELECT tx_hash, block, date, fee FROM transaction
WHERE date = getvariable('tx_day') AND tx_hash = '8662b5e621d183682ba855c6291f72350ef0b8dacc7e7b3e4b0d9a936569bd1c';
```
The same lookup resolves an input `tx_hash#index`: find its tx's day, then read `address_utxo` on that day with
`tx_hash = … AND output_index = …`. (A key can in theory map to two days; checking the full hash settles it.)

```sql
-- A block by number (pruned by column stats, about 0.5 s)
SELECT number, hash, slot, epoch, block_time, no_of_txs, total_fees, body_size, slot_leader AS pool_hash, date
FROM block WHERE number = 14240057;
```

```sql
-- Transactions of that block: use the block's date to read one partition
SELECT tx_hash, tx_index, fee, invalid, json_array_length(inputs) AS inputs, json_array_length(outputs) AS outputs
FROM transaction
WHERE date = DATE '2026-11-24' AND block = 14240057
ORDER BY tx_index;
```

```sql
-- A transaction's outputs (one row per asset per output)
SELECT output_index, owner_addr, asset_unit, quantity, inline_datum IS NOT NULL AS has_inline_datum
FROM address_utxo
WHERE date = DATE '2026-11-24' AND tx_hash = '8662b5e621d183682ba855c6291f72350ef0b8dacc7e7b3e4b0d9a936569bd1c'
ORDER BY output_index;
```

```sql
-- Its script executions (redeemers) and metadata
SELECT purpose, redeemer_index, script_hash, script_type, unit_mem, unit_steps
FROM transaction_scripts
WHERE date = DATE '2026-11-24' AND tx_hash = '8662b5e621d183682ba855c6291f72350ef0b8dacc7e7b3e4b0d9a936569bd1c';

SELECT label, body FROM transaction_metadata
WHERE date = DATE '2026-11-24' AND tx_hash = '8662b5e621d183682ba855c6291f72350ef0b8dacc7e7b3e4b0d9a936569bd1c';
```

```sql
-- Who spent an output (tx_input is partitioned by the day it was spent: search a range)
SELECT tx_hash, output_index, spent_tx_hash, spent_block_time
FROM tx_input
WHERE date BETWEEN DATE '2026-11-20' AND DATE '2026-11-24'
  AND tx_hash = 'c1852b6fe415cb8b2f343ab2ea85eb1901c9e9e981bcb128be0a50a72f840de0';
```

```sql
-- Biggest fees of a day
SELECT tx_hash, block, fee / 1e6 AS fee_ada FROM transaction
WHERE date = DATE '2026-11-24' ORDER BY fee DESC LIMIT 10;
```

## Addresses (per day: there is no all-history address index)

```sql
-- Outputs received by an address on a day, with ADA and tokens
SELECT tx_hash, output_index, asset_unit, quantity
FROM address_utxo
WHERE date = DATE '2026-11-24' AND owner_addr = 'addr1q9am3l7qprxvq22nyfcd0sxyxcy3dge8ufj4cyd85k88fuetded03eh2u8uedk4vygmf0vgpg9d4ucq72kgflux3ujrqzzdx3w';
```

```sql
-- Same for every address of a stake key (owner_stake_addr), over a week
SELECT date, count(DISTINCT tx_hash) AS txs, sum(quantity) FILTER (WHERE asset_unit = 'lovelace') / 1e6 AS ada_received
FROM address_utxo
WHERE date BETWEEN DATE '2026-11-18' AND DATE '2026-11-24' AND owner_stake_addr = 'stake1…'
GROUP BY 1 ORDER BY 1;
```

## Staking and rewards

```sql
-- Active stake per pool in epoch 669: the snapshot taken at epoch 669 - 2 = 667
SELECT pool_id AS pool_hash, count(*) AS delegators, round(sum(amount) / 1e6) AS stake_ada
FROM epoch_stake WHERE epoch = 667
GROUP BY 1 ORDER BY stake_ada DESC LIMIT 20;
```

```sql
-- Or, for the current epoch, with registration parameters (summary pack)
SELECT pool_hash, round(active_stake_ada) AS stake_ada, round(stake_share * 100, 3) AS pct, delegators,
       pledge_ada, cost_ada, margin, blocks_last_epoch, metadata_url
FROM read_parquet(getvariable('summary') || 'pools.parquet')
ORDER BY active_stake_ada DESC LIMIT 20;
```

```sql
-- One delegator: stake and pool in a snapshot, and rewards earned for an epoch
SELECT * FROM epoch_stake WHERE epoch = 667 AND address = 'stake1…';
SELECT epoch, type, pool_id, amount / 1e6 AS ada, spendable_epoch FROM reward
WHERE epoch = 667 AND address = 'stake1…';
```

```sql
-- Blocks per pool in a complete epoch (pruned to that epoch's days)
SELECT slot_leader AS pool_hash, count(*) AS blocks FROM block
WHERE epoch = 668 GROUP BY 1 ORDER BY blocks DESC LIMIT 20;
```

## Names (off-chain metadata, hash-checked)

```sql
-- Largest pools with ticker and name
SELECT m.ticker, m.name, round(p.active_stake_ada / 1e6, 1) AS stake_m_ada, p.delegators
FROM read_parquet(getvariable('summary') || 'pools.parquet') p
LEFT JOIN read_parquet(getvariable('summary') || 'pool_meta.parquet') m
  ON m.pool_hash = p.pool_hash AND m.fetched AND m.hash_ok
ORDER BY p.active_stake_ada DESC LIMIT 20;
```

## Governance

```sql
-- Every governance action with status and per-role vote counts (summary pack)
SELECT type, status, proposed_epoch, drep_yes, drep_no, drep_abstain, spo_yes, spo_no, cc_yes, cc_no, anchor_url, tx_hash, idx
FROM read_parquet(getvariable('summary') || 'governance.parquet')
ORDER BY proposed_epoch DESC;
```

```sql
-- Votes cast in an epoch (voting_procedure is partitioned by date: use the epoch's days)
SELECT voter_type, vote, count(*) AS votes FROM voting_procedure
WHERE date BETWEEN DATE '2026-11-21' AND DATE '2026-11-24'
GROUP BY ALL ORDER BY votes DESC;
```

```sql
-- Top DReps by voting power (summary pack)
SELECT coalesce(drep_id, drep_type) AS drep, round(voting_power_ada / 1e6, 2) AS power_m_ada, status
FROM read_parquet(getvariable('summary') || 'dreps.parquet')
ORDER BY voting_power_ada DESC LIMIT 20;
```

```sql
-- Decentralisation and rewards per epoch
SELECT epoch, nakamoto, round(top10_share * 100, 1) AS top10_pct, pools_with_stake,
       round(member_rewards_ada + leader_rewards_ada) AS rewards_ada
FROM read_parquet(getvariable('summary') || 'staking_epochs.parquet') ORDER BY epoch DESC LIMIT 10;
```

## Scripts, tokens and metadata

```sql
-- Script executions by Plutus version on a day
SELECT script_type, purpose, count(*) AS redeemers, count(DISTINCT script_hash) AS scripts
FROM transaction_scripts WHERE date = DATE '2026-11-24'
GROUP BY ALL ORDER BY redeemers DESC;
```

```sql
-- A script's code by hash: script_index gives its day, then read one partition
WITH i AS (SELECT date FROM read_parquet(getvariable('summary') || 'script_index.parquet')
           WHERE script_hash = '5986bfcc0cbfc60dec8df87715cc95d03817aac386b0e9d33da03b39')
SELECT script_hash, script_type, length("content") AS json_length FROM script
WHERE date = (SELECT date FROM i) AND script_hash = '5986bfcc0cbfc60dec8df87715cc95d03817aac386b0e9d33da03b39';
```

```sql
-- Most active minting policies over a week
SELECT policy, count(*) AS events, count(DISTINCT asset_name) AS assets, sum(quantity) AS net
FROM assets WHERE date BETWEEN DATE '2026-11-18' AND DATE '2026-11-24'
GROUP BY 1 ORDER BY events DESC LIMIT 20;
```

```sql
-- Metadata labels used on a day
SELECT label, count(*) AS entries FROM transaction_metadata
WHERE date = DATE '2026-11-24' GROUP BY 1 ORDER BY entries DESC LIMIT 20;
```

## Lake metadata

```sql
-- Tables, rows, files, size (catalog metadata only: instant)
SELECT t.table_name, s.record_count, round(s.file_size_bytes / 1e9, 2) AS gb
FROM lake_meta.ducklake_table t JOIN lake_meta.ducklake_table_stats s USING (table_id)
WHERE t.end_snapshot IS NULL ORDER BY s.file_size_bytes DESC;
```

```sql
-- Check that a query prunes (look for the number of files scanned)
EXPLAIN ANALYZE SELECT count(*) FROM block WHERE epoch = 668;
```
