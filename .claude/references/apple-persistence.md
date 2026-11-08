# Native Apple persistence and inspection

Read when a feature uses structured local storage, upgrades, retrieval indexes or a database
inspector. Reuse the project's supported storage API; this guidance does not require SwiftData
or add a database to a file-only app.

## Ownership and durable state

- Identify canonical records and every writer, initializer, importer and migration entry point.
  Keep contexts/models within their owning isolation boundary; use the context's queue/`perform`
  APIs for Core Data. Expose immutable projections across isolation. Auxiliary windows use the
  existing service rather than opening independent containers.
- Separate durable user records from rebuildable caches/indexes and release artifacts. Preserve
  database sidecars and backups during replacement. A failed open/migration must not silently
  delete/reset history or replace it with an empty store. Surface failure and preserve recovery.
- Version schemas and test representative older stores, partial failure and readback. Save/flush
  failures remain visible; acknowledge durability only after the owning writer succeeds.

## Read-only operator views

- Trace reads through their callees: convenient loaders may create stores, migrate, import,
  chmod backups, repair records or index content. Keep inspection on fetch/count paths through
  the initialized service. If unavailable, show an error/refresh route without creating a store.
- List bounded metadata pages; fetch large blobs only for an opened row. Use stable ordering,
  a matching cursor predicate and a deterministic tie-breaker. Counts should use scalar queries.
- Read current row details on selection/open. Distinguish a deleted row from a storage failure;
  invalidate old page/row completions on refresh, selection changes and view closure. Where the
  app caches an open store, reject missing/replaced-store identity rather than displaying stale data.
- Preserve malformed bytes visibly with a lossless representation; inspection is not a repair
  or semantic cache-validation operation. Human inspection grants no model tool access.
- Verify reads against a real temporary disk store with ordinary writers paused. Check canonical
  data, store/WAL bytes and relevant permissions/import receipts before and after. Account for
  framework lock/shared-memory bookkeeping separately. Use a normal writer/import as a positive
  control where needed; an inspector with disabled buttons can still write through its loader.

## Retrieval and derived indexes

- Keep stable source conversation/message identifiers and enforce retrieval scope before
  returning content. Hydrate results from canonical records; an index is not the source of truth.
- Record embedding provider/model revision, language, dimension and content revision/digest.
  Invalidate/rebuild derived data when its contract changes. Validate dimensions and finite,
  usable values before similarity search; inspection should still expose damaged cache rows.
- Label semantic/vector results separately from text-index results. Preserve source references
  and distinguish no matches, incomplete coverage and an unavailable provider/index. A disabled
  index may leave history readable; rebuilding it must not delete canonical records.

References: [SwiftData ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor),
[ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext),
[Core Data concurrency](https://developer.apple.com/documentation/coredata/using-core-data-in-the-background).
