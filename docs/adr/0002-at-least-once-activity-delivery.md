# Use at-least-once activity delivery

The runtime may redeliver activities after failures, so it provides persisted deduplication for workflow starts and external inputs and propagates stable activity idempotency keys. Applications and adapters remain responsible for idempotent side effects; the framework does not promise exactly-once effects across independent stores or services.
