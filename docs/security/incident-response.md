# Security incident response

Applies to Morea / Seallo (the Rails platform on Render) and Seallo Connect (the Shopify app service), including buyer personal data imported from merchants' Shopify stores. Review it at least once a year and after every incident.

## What counts as an incident

Any suspected or confirmed event that exposes, alters or destroys personal data or credentials, or lets someone act outside their authorization. Examples: a leaked secret or token, an unexpected `personal_data.read` pattern in the access log, one workspace seeing another's data, a compromised staff account, a vulnerable dependency exploited in production, loss of the database.

## Roles

- **Incident lead:** the platform owner, or whoever they delegate in writing for the duration of the incident. Makes containment and notification decisions.
- **Responder:** an engineer with production access to Render, GitHub and the Shopify Dev Dashboard.
- Keep names and phone numbers in the team's private contact sheet, not in this repository.

## Detect and report

Sources: the `audit_events` access log (below), Render logs and alerts, GitHub/Dependabot and CI audit failures, Shopify notifications, merchant or buyer reports to the support address, staff reports.

Anyone who suspects an incident tells the incident lead immediately and does not try to fix or investigate alone. Open a private incident note with the time, who reported it, and what was seen. Do not paste credentials or customer data into tickets, chat or pull requests.

## Respond

1. **Triage (first hour).** Classify: *critical* (confirmed exposure of buyer data or credentials, or cross-workspace access), *high* (probable exposure, active compromise attempt), *moderate* (vulnerability without evidence of exploitation).
2. **Contain.** Stop the harm first, preserve evidence second.
   - Suspend the affected staff account (`status: suspended` blocks sign-in and live sessions) and end its sessions.
   - Rotate exposed secrets. `SEALLO_BRIDGE_SECRET` must change on both the `morea` and `seallo-connect` services together. The Shopify client secret is rotated in the Dev Dashboard and updated on both services. Rotating `SECRET_KEY_BASE` invalidates Morea's encrypted credentials, so plan reconnection before doing it.
   - If Shopify access tokens may be exposed, remove the app's session rows so merchants must reauthorize, and ask Shopify to revoke where needed.
   - Disable a vulnerable endpoint or feature flag, or roll back the deploy.
3. **Investigate.** Use the access log and service logs to establish what was read, by whom, through which surface (`ui`, `api`, `mcp`), and over what period. Determine whether buyer data left the platform and which merchants and buyers are affected.
4. **Notify.**
   - **Merchants** whose buyers' data is affected: without undue delay after we become aware, with what happened, which data, what we did, and what they should do.
   - **Shopify:** report through Shopify Partner support when app credentials or merchant data are affected.
   - **Regulators and buyers:** the incident lead decides with legal advice where applicable law requires notification.
5. **Recover.** Fix the root cause, deploy, confirm with tests and logs, restore from Render point-in-time recovery only if data was lost or altered, and reactivate suspended access deliberately.
6. **Review (within 5 working days of closure).** Write a blameless post-incident note: timeline, root cause, impact, what worked, what to change. Track the follow-ups as issues and add a regression test where code was at fault.

## Using the personal-data access log

`audit_events` records each read of buyer contact details with `source` (`ui`, `api`, `mcp`), `store_id`, actor, IP, the subject record and the screen or operation. It stores identifiers only, never the data, and rows cannot be updated or deleted through the application.

```sql
-- Who read buyer data in a workspace during a window
select created_at, source, actor_label, ip, subject_type, subject_id, metadata->>'surface' as surface
from audit_events
where action = 'personal_data.read' and store_id = :store_id
  and created_at between :from and :to
order by created_at;

-- Unusual volume per actor
select actor_label, source, count(*) from audit_events
where action = 'personal_data.read' and created_at > now() - interval '1 day'
group by 1, 2 order by 3 desc limit 20;

-- Platform administrators reading a workspace they do not belong to
select * from audit_events where acting_as_platform and created_at > now() - interval '30 days';
```

Logging is best-effort: a failed write is reported to the error tracker but does not block order handling, so a gap in the log is itself a signal to check.

## Maintenance

- Test the secret-rotation steps in a non-production environment at least once a year.
- Keep staff and platform-admin accounts to those who need them, and review the list quarterly.
- Update this document when infrastructure, vendors or roles change.
