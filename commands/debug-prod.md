---
description: Read-only first look at a misbehaving service on prod (or dev) — logs, ECS state, last deploy, targets, alarms
argument-hint: <service> [--dev] [--since 1h] [symptom…]
---
Investigate `$ARGUMENTS` (first word = service, e.g. `pricing-service` or `orders-bff`; `--dev` = dev instead of
prod; `--since` defaults to 1h; anything else = the symptom I described). READ-ONLY: never deploy, scale, restart,
change SSM or write to any database — propose those as commands for me instead.

**Normalize once**: base = the name without a trailing `-service` (`pricing-service` → `pricing`). Then:
| env | profile | cluster | ECS service | logs |
|---|---|---|---|---|
| prod | `--profile prod` | `<prod-cluster>` | `<prefix>-<base>-service` | via `svc-logs <base> --prod` |
| dev | `--profile default` | `<dev-cluster>` | `<prefix>-<base>-service` | via `svc-logs <base>` |
Fill the cluster and service-name pattern from your own infrastructure notes once; if you run extra clusters (e.g. a
separate workload pool), add a row for each.
Every AWS command carries `--profile <p> --region <region>` explicitly — never rely on the default profile for
prod; ECS commands also `--cluster <c>` (elbv2 / cloudwatch / logs commands don't take `--cluster`). If `describe-services` returns MISSING, list the cluster's services
(`aws ecs list-services --profile <p> --region <region> --cluster <c>`) and match — don't conclude "not deployed".
Prod needs the VPN for DBs and the search cluster.

Steps (run the independent ones in parallel):
1. **Errors**: `svc-logs <base> --prod --since <since> --grep ERROR` (dev: drop `--prod`) (also try `Error`, `Exception`, `ORA-`,
   `ECONN`, `timeout` when the plain filter is empty). Group by message; count; first/last time.
2. **ECS state**: `aws ecs describe-services --profile prod --region <region> --cluster <prod-cluster> --services <ecs-service>` → desired / running /
   pending, deployments (rolloutState, taskDefinition, createdAt) and the last ~10 `events` (crash loops,
   failed health checks, placement errors). `aws ecs list-tasks --desired-status STOPPED` + `describe-tasks` →
   `stoppedReason` / container exit codes if tasks are dying.
3. **Last deploy**: task definition revision + image (tag/digest) + when it rolled out; does the error start then?
4. **Traffic**: `aws elbv2 describe-target-health` for the service's target group (find it from the service's
   loadBalancers) — unhealthy reasons.
5. **Alarms**: `aws cloudwatch describe-alarms --state-value ALARM` filtered to the service.
6. Only if the logs point at data: one small read-only query (`ro-sql prod` / `ro-pg <svc> --prod` /
   `ro-es prod`) to confirm — keep results tiny, filter by the customer id, no personal-data dumps.
7. Check your own notes for known causes first (e.g. database connection/NAT hangs, missing prod credentials for a
   service, a `:latest` image tag not re-pulled without a force deploy) before inventing new theories.

Report: what's wrong (one line) · evidence (log lines with timestamps, ECS events) · since when / which deploy ·
most likely cause · the fix, as commands or a code pointer for me to approve · what you couldn't check (VPN, access).
