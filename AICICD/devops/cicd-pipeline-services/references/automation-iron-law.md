# Automation Iron Law and New Pitfalls (2026-05-18)

## Automation Iron Law (铁律)

**User correction**: "有需要手动的问题，就应该设置为自动化脚本，保证全链路自动化流程。不允许手动介入！"

**Rule**: When you encounter ANY manual step during debugging or operation, immediately create an automation script. The project铁律 is: **full automation from push to ISO, no manual intervention allowed**.

**Actions required when finding manual steps**:
1. Create automation script in `/home/nando/AICICD/scripts/`
2. Document the problem and solution in `docs/debug/`
3. Update existing automation scripts if the fix affects them

**Example scripts created** (2026-05-18):
- `scripts/add-test-package.sh` — One-click add test package + trigger full-chain build
- `scripts/full-chain-test.sh` — Full-chain automated test (env check + code creation + Pipeline monitoring + ISO verification)
- `scripts/check-and-fix-obs.sh` — OBS service health check and auto-repair
- `scripts/setup-gitlab-webhook.sh` — GitLab webhook auto-configuration

## GitLab Webhook Configuration via PostgreSQL

**Symptom**: `curl -X PUT .../application/settings` returns success but `allow_local_requests_from_web_hooks_and_services` remains `false`. GitLab rejects localhost webhook URLs with "Invalid url given".

**Root cause**: GitLab Rails API settings update may fail silently due to encryption issues or cached values.

**Fix**: Modify GitLab PostgreSQL database directly (most reliable method):
```bash
# Enable local requests for webhooks
docker exec gitlab gitlab-psql -c "UPDATE application_settings SET allow_local_requests_from_web_hooks_and_services = true;"

# Add localhost/IP to outbound whitelist (CRITICAL!)
docker exec gitlab gitlab-psql -c "UPDATE application_settings SET outbound_local_requests_whitelist = ARRAY['localhost', '127.0.0.1', '192.168.137.103'];"
```

**Then create webhook**:
```bash
curl -s -X POST "http://localhost:8080/api/v4/projects/$ID/hooks" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url": "http://localhost:8091/gitlab/push", "push_events": true, "enable_ssl_verification": false}'
```

**Note**: The `outbound_local_requests_whitelist` column is essential — without it, GitLab still rejects localhost URLs.

## Docker API Version Compatibility

**Symptom**: ISO build container fails to start with error: `client version 1.52 is too new. Maximum supported API version is 1.39`

**Root cause**: Container's Docker client uses newer API version than host's Docker daemon.

**Fix**: Set `DOCKER_API_VERSION` environment variable:
```dockerfile
# In Dockerfile
ENV DOCKER_API_VERSION=1.39
```

Or in docker run:
```bash
docker run -e DOCKER_API_VERSION=1.39 ...
```

## Webhook Server Branch Name Handling Bug

**Symptom**: Pipeline trigger fails with `Reference not found` and logs show `ref=mainmain`

**Root cause**: Incorrect string replacement:
```python
# WRONG — replaces "refs/heads/" with "main", resulting in "mainmain"
ref = event.ref.replace("refs/heads/", "main")

# CORRECT — removes prefix, resulting in "main"
ref = event.ref.replace("refs/heads/", "")
```

**Fix**: Always remove the prefix, not replace with a value.

## Webhook Server Image Rebuild Required

**Symptom**: Code changes to `app.py` don't take effect after `docker restart webhook-server`

**Root cause**: Container doesn't mount source code — code is baked into image.

**Fix**: Rebuild image and recreate container:
```bash
cd /home/nando/AICICD/01-source-trigger/webhook-server
docker build -t intewell-webhook-server:v2.2 .
docker stop webhook-server && docker rm webhook-server
docker run -d --name webhook-server --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DOCKER_API_VERSION=1.39 \
  intewell-webhook-server:v2.2
```

## OBS Service Health Check Pattern

**Symptom**: OBS API returns 500, Pipeline obs-wait times out with `all_done=null`

**Root cause**: OBS backend services may not fully start after container restart.

**Fix**: Use automated health check script:
```bash
/home/nando/AICICD/scripts/check-and-fix-obs.sh
```

**Manual check commands**:
```bash
# Check process count (should be >= 8)
docker exec obs-server-test ps aux | grep -E "bs_srcserver|bs_repserver|bs_sched|bs_worker" | wc -l

# Check API
curl -s "http://localhost:4455/source/home:Admin/_meta" --user "Admin:admin123"
```

## Document Debug Process in Real-Time

**User correction**: "实时记录调试记录到文档MD"

**Rule**: During debugging, write findings to `docs/debug/` immediately. Don't wait until the end of the session.

**Debug doc structure**:
- Problem description (现象)
- Root cause (原因)
- Solution (解决方案)
- Commands/scripts used

**Example**: `docs/debug/add-test-folder-process.md`

## GitLab Duplicate Webhooks Cause Multiple Pipelines

**Symptom**: One push triggers 3-4 Pipelines with the same commit SHA

**Root cause**: `setup-gitlab-webhook.sh` creates a new webhook every time without checking if one already exists

**Fix**: Check for existing webhooks before creating:
```bash
EXISTING=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/hooks" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | python3 -c "
import sys,json
hooks = json.load(sys.stdin)
for h in hooks:
    if '$WEBHOOK_URL' in h.get('url', ''):
        print(h['id'])
        break
")

if [ -n "$EXISTING" ]; then
    echo "webhook已存在 (id=$EXISTING)"
    continue
fi
```

**Cleanup**: Delete duplicate webhooks:
```bash
for id in 3 4 5; do
    curl -s -X DELETE "http://localhost:8080/api/v4/projects/1/hooks/$id" --header "PRIVATE-TOKEN: $TOKEN"
done
```

## OBS API 500 Error - Missing Database Columns

**Symptom**: OBS API returns 500, logs show `NoMethodError: undefined method 'in_beta?' for #<User:0x...>`

**Root cause**: Database migration incomplete, users table missing `in_beta` and `beta_features` columns

**Fix**:
```bash
# Add missing columns
docker exec obs-server-test mysql -u obs -pobs123 obs_api -e "
    ALTER TABLE users ADD COLUMN IF NOT EXISTS in_beta BOOLEAN DEFAULT FALSE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS beta_features TEXT;
"

# Restart OBS API
docker exec obs-server-test pkill -f "rails server"
docker exec -d obs-server-test bash -c '
    cd /srv/www/obs/api
    export SECRET_KEY_BASE=$(openssl rand -hex 64)
    RAILS_ENV=production bin/rails server -b 0.0.0.0 -p 4455 --daemon
'
```

**Automation**: Integrated into `scripts/check-and-fix-obs.sh`

## OBS Rails API 500 — Missing /app Symlink

**Symptom**: OBS Rails API (port 4455) returns 500 for all requests with `ActionView::MissingTemplate` error, while backend API (port 5352) works fine. Rails is searching for templates in `/app/views` but they exist at `/srv/www/obs/api/app/views/`.

**Root cause**: OBS 2.10.28+ container builds may have missing `/app` symlink. Rails code references `/app/views` path.

**Fix**:
```bash
# Create symlink
docker exec obs-server-test ln -s /srv/www/obs/api/app /app

# Restart Rails API
docker exec obs-server-test pkill -f "rails server"
docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && export SECRET_KEY_BASE=$(openssl rand -hex 64) && RAILS_ENV=production bin/rails server -b 0.0.0.0 -p 4455 --daemon'
```

**Verification**: `curl -s "http://localhost:4455/source/home:Admin/_meta" --user "Admin:admin123"` should return XML.

**Persistence**: Add to `/start-obs.sh`: `[ ! -e /app ] && ln -s /srv/www/obs/api/app /app`

## OBS Rails Database Out of Sync with Backend

**Symptom**: Backend API shows 9 projects exist, but Rails API returns `unknown_project`. Database query `SELECT name FROM projects;` shows only `deleted`.

**Root cause**: OBS backend stores projects as XML files in `/srv/obs/projects/*.xml`, while Rails uses MySQL `obs_api.projects` table. After container restart or data migration, database may be empty while backend files persist.

**Fix**: Sync backend projects to Rails database:
```bash
docker exec obs-server-test bash -c 'cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner "
  projects = [\"home:Admin\", \"home:Admin:demo-app\", \"home:Admin:openEuler24.03-SP1\"]
  projects.each do |p|
    begin
      Project.find_or_create_by(name: p)
      puts \"Synced: #{p}\"
    rescue => e
      puts \"Error: #{e.message}\"
    end
  end
"'
```

**Note**: New projects created via Rails API will auto-sync. This is mainly needed after data recovery/migration.
