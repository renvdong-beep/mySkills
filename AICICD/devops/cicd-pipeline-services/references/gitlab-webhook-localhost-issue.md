# GitLab Webhook URL Must Use IP Address (2026-05-18)

## Problem

**Symptom**:
- GitLab webhook created successfully with `url: http://localhost:8091/gitlab/push`
- `push_events: true` is enabled
- `allow_local_requests_from_hooks_and_services: true` is set
- Webhook events list is empty `[]` after push
- webhook-server never receives push events
- CI variables don't update, OBS projects don't get created

**Root cause**: GitLab's internal webhook trigger mechanism does NOT work with `localhost` URLs, even when all local request permissions are enabled. The webhook is created but never fired.

## Solution

Use the host's actual IP address instead of `localhost`:

```bash
# Get host IP
IP=$(hostname -I | awk '{print $1}')

# Create webhook with IP address
curl -X POST "http://localhost:8080/api/v4/projects/$ID/hooks" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --form "url=http://${IP}:8091/gitlab/push" \
  --form "push_events=true" \
  --form "enable_ssl_verification=false"
```

## Verification

```bash
# Check webhook was created
curl -s "http://localhost:8080/api/v4/projects/$ID/hooks" --header "PRIVATE-TOKEN: $TOKEN"

# Push code and check webhook events
curl -s "http://localhost:8080/api/v4/projects/$ID/hooks/$HOOK_ID/events" --header "PRIVATE-TOKEN: $TOKEN"
```

## Why This Happens

GitLab's webhook trigger logic has a known issue where `localhost` URLs are not processed correctly, even with explicit permission settings. The exact reason varies by GitLab version, but using the actual IP address bypasses this issue entirely.

## Related

- `cicd-pipeline-services` skill pitfall #50
- `obs-build-service` skill pitfall #47
