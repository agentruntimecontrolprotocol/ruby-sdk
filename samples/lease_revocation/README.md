# lease_revocation

Warehouse DB admin agent. Reads against pre-granted tables run free.
INSERT / UPDATE / DELETE / DDL trigger a synchronous
`permission.request` scoped to the specific table and operation.

## Before ARCP

Two failure modes: (1) the agent has a write-capable DB role and
operators audit Slack, hoping; (2) writes go through a separate
"approval" service that the agent doesn't actually understand —
when approval is denied, the agent gets a 403 with no structure
and either gives up or retries blindly.

## With ARCP

```ruby
def authorize(client, sql, leases:)
  klass = SqlClassifier.classify(sql) # read / write / ddl
  klass.tables.each do |table|
    leases[[table, klass.op]] ||= request_lease(
      client, permission: "db.#{klass.op}", table: table,
      operation: klass.op,
      seconds: klass.op == 'read' ? READ_LEASE_SECONDS : WRITE_LEASE_SECONDS
    )
  end
  klass.op
end
```

Granted leases are cached. Mid-statement `lease.revoked` drops the
cache entry so the next call re-prompts.

## ARCP primitives

- Permission challenge — RFC §15.4.
- Full lease lifecycle (request, grant, use, refresh, revoke) — §15.5.
- `PERMISSION_DENIED` / `LEASE_EXPIRED` / `LEASE_REVOKED` — §18.2.

## File tour

- `main.rb` — opens session, bootstraps reads, runs two queries.
- `sql.rb` — sqlglot/pg_query-based read/write/ddl classifier (stub).

## Variations

- Replace operator approval with a policy engine (Cedar, OPA) — the
  responder is interchangeable as long as it emits `lease.granted`.
- Promote read leases to row-level by encoding row-filter SQL into
  `resource` (`table:public.orders/region=us`).
- Stream every DDL into [subscriptions](../subscriptions) for change
  history.
