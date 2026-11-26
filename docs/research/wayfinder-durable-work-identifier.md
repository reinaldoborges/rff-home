# Durable work identifier constraints

**Status: incomplete — MySQL manual could not be retrieved.** This note records
verified implementation and SQLite evidence, but it does not resolve the MySQL
prefix-index or BLOB-ordering questions. Keep issue [#65
open](https://github.com/reinaldoborges/rff-home/issues/65); do not use this as
approval to shorten identifiers or change their equality semantics.

## Revision and scope

The map pins `reinaldoborges/rff-go` to
`4ce0e74b4a6e78f955cd5fef858402f0d7a868c7`. On 2026-11-26, remote `master`
still resolved to that exact commit. The ordinary checkout was clean but on
`docs/effective-go-guidance` at `881c69249c751637bf7ae4b1755951707f758d75`;
it was not inspected or changed. Source references below point to the exact
pinned commit.

## What the application persists and means by an ID

- Timer and input APIs use Go `string` IDs (`TimerRequest.ID`,
  `InputRecord.ID`). Scheduling/acceptance rejects the empty string, but these
  paths do not declare a maximum length, character set, normalization, or
  truncation rule. The MySQL adapter checks that the JSON record ID equals the
  lookup ID before using it. See [runtime timer types](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/runtime/timer.go#L13-L35),
  [runtime input types](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/runtime/ingress.go#L39-L60),
  [timer decode and acceptance](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/timer.go#L15-L24)
  and [input decode and acceptance](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/ingress.go#L13-L20).
- Hook and notification work use the execution ID as their key. Execution IDs
  are also represented as Go strings, but the persisted execution record uses a
  byte-exact identity envelope: raw `[]byte` identity fields are stored beside
  the JSON display strings, checked on decode, then restored. That is explicit
  evidence against silently changing identity bytes or treating a display
  prefix as the identity. See [identity envelope matching](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/internal/executionidentity/identity.go#L1-L18)
  and [MySQL record encoding](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/record.go#L47-L90).
- Timer and input records use ordinary Go `encoding/json`, not that identity
  envelope. Go's v1 JSON marshaler replaces invalid UTF-8 bytes in strings with
  U+FFFD; the adapters' exact `record.ID != id` check means such IDs do not
  round-trip through these code paths. This is not a declared UTF-8 validation
  contract or an ID length cap. See [Go JSON Marshal documentation](https://pkg.go.dev/encoding/json#Marshal)
  and the decode links above.
- Notification intent IDs are a separate value: `notificationID` computes
  `rff-notification:` plus the hex SHA-256 of that prefix and the execution ID
  (81 ASCII characters). But `rff_notification_work` is keyed and selected by
  the original `execution_id`, not the derived intent ID. Do not treat that
  hash as evidence that work identity is truncated or hash-keyed. See
  [`notificationID`](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/commit.go#L88-L91)
  and [work insertion](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/atomic_commit.go#L108-L116).

## Schema and uniqueness

SQLite declares timer/input IDs as `TEXT PRIMARY KEY NOT NULL` and hook and
notification `execution_id` as `TEXT PRIMARY KEY NOT NULL`. The primary key
therefore enforces uniqueness of the complete stored key; `NOT NULL` avoids
SQLite's documented legacy exception allowing NULL in some non-integer primary
keys. The table declarations are in
[SQLite schema.go](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/sqlite/schema.go#L18-L24).

The MySQL schema instead declares these four key columns `LONGBLOB NOT NULL`
with ordinary `KEY` indexes using `(256)`. Its schema validator explicitly
requires each of those indexes to be `nonUnique: true` with prefix length 256.
There is no primary/unique constraint on these work tables in this DDL. See
[MySQL DDL](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/schema.go#L38-L56)
and [index validation](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/schema.go#L285-L302).
Thus the application schema does not forbid two full identifiers sharing the
indexed 256-unit prefix, and the index itself does not impose full-key
uniqueness. The source defines the SQL predicates as full-column equality
(`WHERE id = ?` / `WHERE execution_id = ?`), not as an application-level
prefix comparison.

For normal adapter writes, uniqueness/replay behavior is implemented above
that MySQL DDL: timer scheduling and input acceptance select by the requested
ID and insert only when absent; hook work checks existence then updates or
inserts; notification work is created while advancing a validated execution.
Adapter transactions acquire the shared `rff_transaction_lock` row first. This
serializes the adapter's own check-and-write paths; it is not a uniqueness
constraint against out-of-band writers or malformed existing rows. See
[transaction serialization](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/mysql.go#L88-L99),
[timer check/insert](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/timer.go#L35-L82),
[input check/insert](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/ingress.go#L36-L83),
[hook upsert logic](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/activity.go#L290-L309),
and [notification creation](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/notification_outbox.go#L120-L153).

## Verified SQLite constraints and ordering

- SQLite's documented default maximum length for a string or BLOB is 1,000,000,000
  bytes; its implementation ceiling is 2^31−3 bytes. The compile-time setting
  can vary and the runtime limit can be lowered. This is an engine ceiling,
  **not** an application ID limit. See [SQLite limits: maximum length](https://www.sqlite.org/limits.html#max_length).
- The `id` columns have no explicit `COLLATE`, so SQLite's default is `BINARY`.
  SQLite documents BINARY as bytewise comparison (`memcmp`) and uses the
  column's collation for `ORDER BY id`. Its sort rules distinguish TEXT and
  BLOB storage classes; the adapter schema declares these IDs as TEXT. See
  [SQLite collating sequences](https://www.sqlite.org/datatype3.html#collation),
  [sorting/grouping](https://www.sqlite.org/datatype3.html#sorting_grouping_and_compound_selects),
  and [CREATE TABLE primary-key constraints](https://www.sqlite.org/lang_createtable.html#the_primary_key).
- Both adapters' selectors order timers and inputs by ID; hook and notification
  worker scans order by `execution_id`. `ClaimDueTimer` scans IDs in that order
  and replaces its current candidate only when a deadline is strictly earlier,
  so equal-deadline timers are resolved by ID scan order. SQLite's primary key
  makes IDs distinct; `ORDER BY` does not define an order among rows tied on
  every ordering expression. See [MySQL timer claim](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/timer.go#L90-L145),
  [SQLite timer claim](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/sqlite/timer.go#L90-L145),
  [MySQL input listing](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/ingress.go#L103-L130),
  [SQLite input listing](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/sqlite/ingress.go#L103-L130),
  [MySQL hook selection](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/activity_worker.go#L33-L35),
  [SQLite hook selection](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/sqlite/activity_worker.go#L33-L35),
  [MySQL notification selection](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/notification_outbox.go#L207-L210),
  [SQLite notification selection](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/sqlite/notification_outbox.go#L207-L210),
  and [SQLite SELECT ordering](https://www.sqlite.org/lang_select.html#orderby).

## MySQL documentation gap — blocks a decision

On 2026-11-26, requests to the official MySQL 8.4 manual returned HTTP 403 in
this environment (both `dev.mysql.com` and the Oracle-hosted manual). I did not
work around that restriction. The relevant primary-source pages that still
need review are:

- [Column prefix indexes](https://dev.mysql.com/doc/refman/8.4/en/column-indexes.html)
- [BLOB and TEXT types](https://dev.mysql.com/doc/refman/8.4/en/blob.html)
- [ORDER BY optimization](https://dev.mysql.com/doc/refman/8.4/en/order-by-optimization.html)
- [Sorting rows](https://dev.mysql.com/doc/refman/8.4/en/sorting-rows.html)
- [InnoDB limits](https://dev.mysql.com/doc/refman/8.4/en/innodb-limits.html)
- [Server system variables, including sort-related limits](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html)

Accordingly, this research does **not** state MySQL's maximum `LONGBLOB` ID
size, the exact prefix-index comparison/recheck behavior for a full-column
equality predicate, any InnoDB prefix-index limits, the bytes considered when
sorting BLOBs, or which rows may tie under `ORDER BY id`. Those must be verified
against the manual before treating MySQL equality or order as equivalent to
SQLite or choosing a bounded-key/index design. A 256-prefix non-unique key is
not evidence that IDs may be truncated to 256 bytes.

## Outcome

The source establishes full application IDs as the durable identity and
shows no safe truncation rule. SQLite has full-key primary-key uniqueness and
documented text ordering; MySQL schema source establishes only a non-unique
256-prefix lookup index plus application-managed check-and-write behavior.
Because the required MySQL database guarantees could not be verified, this is
partial research only: leave issue #65 open and do not add a decision to map
#61 until the official MySQL pages are accessible and checked.
