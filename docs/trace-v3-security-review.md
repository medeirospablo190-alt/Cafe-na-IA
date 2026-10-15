# Trace V3 gateway security review

Status: static review; not a production penetration test.

## Verified in the reviewed branch

- `gateway-main.js` sets Express `trust proxy` to `1`.
- The legacy trace limiter and Trace V3 limiter derive their client key from Express request IP data and hash the value before using it as a map key.
- Trace V3 rate-limit state is held in a process-local `Map`; it is not shared between instances and resets when the process restarts.
- Trace V3 has bounded request-body, record, remote, batch, and rate-limit-map sizes. Unit/integration tests cover relevant input limits and rate-limit expiry/capacity.
- The batch endpoint requires server-side GitHub configuration to mirror data. A reusable GitHub token must never be shipped in the Lua client.
- Raw traces can contain account identifiers, usernames, game paths, state observations, and other sensitive gameplay metadata. Keep raw traces private and limit access to generated reports.

## Not yet verified

- The actual trusted-proxy hop count and forwarding-header behavior in the deployed Render service.
- Whether the deployment runs one or multiple instances, and whether local disk persists across restarts.
- Operational limits and alerts for GitHub API usage, repository growth, and storage consumption.
- A suitable admission/authentication policy for a public client that does not embed a reusable server secret.

## Required before treating the endpoint as production-hardened

1. Confirm the hosting proxy topology and configure Express to trust only the actual trusted proxy boundary. Do not assume `trust proxy = 1` is correct without this evidence.
2. Define admission control that does not put a GitHub token or other reusable server secret in Lua. If clients cannot authenticate securely, treat incoming observations as untrusted and apply server-side quotas, validation, and abuse monitoring.
3. Decide how quotas behave across multiple instances and restarts; use a shared limiter if a global quota is required.
4. Set alerts and operational ceilings for request volume, GitHub API calls, repository growth, and storage.
5. Verify persistence and recovery behavior for local files and GitHub-mirrored records.
6. Add tests for trusted-proxy behavior using the confirmed deployment topology, forwarded-header spoofing, and rate-limit behavior across the chosen storage mechanism.
7. Test on staging or a controlled environment before production rollout.

## Safety boundaries

- Do not test abuse or load against production without explicit authorization and bounded limits.
- Do not embed GitHub credentials in the client.
- Do not delete historical trace data as a cleanup shortcut.
- Keep this review descriptive: it records what code review confirmed and what still needs deployment evidence.
