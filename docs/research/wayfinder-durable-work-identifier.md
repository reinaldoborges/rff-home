# Durable work identifier constraints

**Status: research complete**, with a documented MySQL manual inconsistency
about BLOB sorting. This is evidence for [issue #65](https://github.com/reinaldoborges/rff-home/issues/65),
not approval to shorten identifiers or change their equality semantics.

## Revision and scope

The map pins `reinaldoborges/rff-go` to
`4ce0e74b4a6e78f955cd5fef858402f0d7a868c7`. On 2026-11-26, remote `master`
still resolved to that exact commit. The ordinary checkout was clean but on
`docs/effective-go-guidance` at `881c69249c751637bf7ae4b1755951707f758d75`;
it was not inspected or changed. Source references below point to the exact
pinned commit. On the final retry the remote master and checkout were
reverified unchanged, and the pinned commit was inspected in a clean detached
isolated worktree.

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

## MySQL 8.4 manual: value and index semantics

- [`LONGBLOB` holds at most 4,294,967,295 bytes](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/string-type-syntax.html);
  actual usable values depend on packet and memory limits. InnoDB additionally
  requires the [total row including BLOBs to be less than 4 GB](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/innodb-limits.html).
  Outside strict SQL mode, overlong values may be truncated with a warning;
  strict mode can reject truncation instead. These are storage/transport and
  configuration limits, **not an application contract to truncate IDs**:
  [BLOB and TEXT](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/blob.html).
- A BLOB is a binary byte string: comparison and sort use numeric byte values,
  all bytes including trailing spaces matter for comparison, and no bytes are
  stripped on retrieval. Binary columns do not apply character-set conversion
  in the documented column-assignment and retrieval cases. See
  [BLOB and TEXT](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/blob.html)
  and [binary versus `_bin` collations](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/charset-binary-collations.html).
- `INDEX(id(256))` on a BLOB indexes the **first 256 bytes**, not 256 Unicode
  characters; BLOB indexes must specify a prefix length. If the search term
  exceeds the index prefix, the manual says the index excludes nonmatches and
  remaining rows are examined for possible matches. Therefore a shared prefix
  produces candidates, not an equality of distinct full values: full-column
  `WHERE id = ?` retains its comparison, while the index may narrow candidates.
  An index need not be chosen at all. See [column indexes and prefixes](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/column-indexes.html#column-indexes-prefix)
  and [binary comparison rules](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/charset-binary-collations.html#charset-binary-collations-trailing-space-comparisons).
- The current prefix keys are **non-unique** and admit both identical IDs and
  distinct IDs with the same prefix at the schema level. A hypothetical
  `UNIQUE(id(256))` would require values to be unique **within the prefix**:
  it rejects two distinct longer IDs with that same prefix, not merely exact
  duplicates. It is not equivalent to unrestricted full-value uniqueness.
  See [CREATE INDEX: unique indexes](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/create-index.html#create-index-unique).
- InnoDB's documented index key prefix limits are 767 bytes for COMPACT or
  REDUNDANT rows, and 3072 for DYNAMIC or COMPRESSED at the default 16 KB page
  size; smaller 8 KB and 4 KB pages reduce the latter maximum to 1536 and 768
  bytes. Limits also apply to full-column index keys. A bounded full-value key
  thus needs an explicitly justified bound, row-format/page-size support,
  encoding and full equality semantics; a digest or prefix alone is not a
  collision-free identity. See [InnoDB limits](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/innodb-limits.html).

## MySQL 8.4 manual: ordering and a documentation conflict

- The [ORDER BY optimization manual](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/order-by-optimization.html)
  explicitly says an index on only a column prefix cannot fully resolve
  `ORDER BY` on that column: the index cannot distinguish the suffix and a
  filesort is needed. A prefix index may still help find rows. Other indexes
  or query shapes may enable ordering, but actual plan selection depends on
  cost, additional columns read, join order and predicates; adding an index
  does not guarantee its use or imply a particular latency.
- [LIMIT optimization](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/limit-optimization.html)
  says rows with identical ORDER BY values may be returned in any order and
  plan changes, including `LIMIT`, may change their relative order. In these
  adapters, [hook](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/activity_worker.go#L33-L70)
  and [notification](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/notification_outbox.go#L207-L255)
  claims take the first eligible item in the SQL scan; [timers](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/timer.go#L103-L124)
  use scan order only for equal earliest deadlines, and [input discovery](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/ingress.go#L103-L130)
  preserves scan order. A rewrite must deliberately preserve the observable
  selection rules rather than sort by a hash or prefix and assume equivalence.
- **Conflicting official text:** the 8.4 [BLOB/TEXT page](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/blob.html)
  states only the first `max_sort_length` bytes of a BLOB/TEXT column are used
  when sorting. The 8.4 [`max_sort_length` variable description](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/server-system-variables.html#sysvar_max_sort_length)
  instead restricts that truncation to strings using **PAD SPACE** collations,
  default 1024 bytes; it says this changed from previous versions. The
  first-party 8.4 source and BLOB regression test below support the latter
  distinction at the inspected snapshot. Do **not** resolve this inconsistency
  by asserting either a universal 1024-byte BLOB cutoff or universal unlimited
  full-ID ordering for all supported server versions and plans. Establish the
  actual target-version behavior with a regression case using long shared
  prefixes and, if exact deterministic tie ordering is required, define and
  verify it explicitly.

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

## MySQL source evidence from the retry

On the follow-up, the Oracle and MySQL documentation sites still returned HTTP
403; the Oracle-hosted manual became accessible on the final retry. As a
different first-party source, the public `mysql/mysql-server` 8.4
branch was read at commit
[`14f6f5119f993f74a8514352108d9337182d5be5`](https://github.com/mysql/mysql-server/commit/14f6f5119f993f74a8514352108d9337182d5be5).
This is an implementation snapshot, not an authoritative manual guarantee
for every 8.4 release or server supported by the adapter, which [accepts
MySQL 8.4 or later](https://github.com/reinaldoborges/rff-go/blob/4ce0e74b4a6e78f955cd5fef858402f0d7a868c7/adapters/mysql/mysql.go#L58-L82).

- In that snapshot, [`max_sort_length` is described](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/sql/sys_vars.cc#L2957-L2963)
  as the bytes used for long values **with PAD SPACE collations**, with default
  1024. The sort-key code applies the limit to fixed-length string sort keys
  and explains why it is needed for PAD SPACE TEXT; `NO_PAD` sort keys are
  variable-length in that code. See [`sortlength`](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/sql/filesort.cc#L2123-L2143)
  and its [limit branch](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/sql/filesort.cc#L2166-L2177).
  The binary character-set definition has [`NO_PAD`](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/strings/ctype-bin.cc#L509-L542).
- A MySQL regression test creates a BLOB column, sets session
  `max_sort_length = 20`, inserts distinct strings sharing more than 20 leading
  bytes, and expects them **still sorted** in `ORDER BY c, id`; the checked-in
  expected output shows that result. See the [test](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/mysql-test/suite/sys_vars/t/max_sort_length_func.test#L184-L209)
  and [expected output](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/mysql-test/suite/sys_vars/r/max_sort_length_func.result#L221-L256).
  This directly contradicts assuming that all BLOB sorts in MySQL 8.4 simply
  truncate at `max_sort_length`. It is one test at that revision, not proof of
  every possible sort path or release.
- The snapshot's index setup marks a key as usable for sorting only if the key
  part is full length and the handler supports ordered reads; its full-length
  condition excludes `BLOB_FLAG`. The optimizer's
  `test_if_order_by_key` rejects a key when the field is not marked
  `part_of_sortkey`. See [index setup](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/sql/table.cc#L755-L782)
  and [order-by check](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/sql/sql_optimizer.cc#L1804-L1831)
  with its [rejection](https://github.com/mysql/mysql-server/blob/14f6f5119f993f74a8514352108d9337182d5be5/sql/sql_optimizer.cc#L1914-L1915).
  This is concrete source evidence that this optimizer path cannot use the
  BLOB prefix key alone as the full-column sort key; it does not establish the
  chosen access path for the application's joined queries or a latency result.

## Outcome

The source establishes full application IDs as the durable identity and
shows no safe truncation rule. SQLite has full-key primary-key uniqueness and
documented text ordering; MySQL schema source establishes only a non-unique
256-byte prefix lookup index plus application-managed check-and-write behavior.
Full-column equality is not prefix equality; `UNIQUE` prefix keys introduce
false conflicts, and prefix indexes do not fully order the complete value.
The MySQL manual's contradictory sort-length statements and actual optimizer
selection remain explicit constraints to verify in the eventual design, not
reasons to change or truncate an application identity.
