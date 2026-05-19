# OBS Rails API 500 Error Debugging Session (2026-05-18)

## Summary

OBS Rails API (port 4455) returned 500 Internal Server Error while OBS backend API (port 5352) worked correctly. Multiple root causes were discovered and fixed.

## Issues Found and Fixed

### Issue 1: memcached Not Running

**Error**: `Dalli::RingError: No server available`

**Diagnosis**:
```bash
docker exec obs-server-test tail -20 /srv/www/obs/api/log/production.log | grep -E "Error|FATAL"
# Output: FATAL -- : Dalli::RingError: No server available
```

**Root cause**: OBS Rails uses memcached (Dalli gem) for caching. memcached was not running or hostname `cache` was unresolvable.

**Fix**:
```bash
# Modify memcached_host to localhost
docker exec obs-server-test sed -i 's/memcached_host: cache/memcached_host: localhost/' /srv/www/obs/api/config/options.yml

# Start memcached
docker exec obs-server-test memcached -d -u root
```

### Issue 2: Missing Database Columns

**Error**: `NameError: undefined local variable or method 'password_digest' for #<User:...>`

**Root cause**: OBS Rails code expects database columns that don't exist after migration.

**Fix**:
```bash
docker exec obs-server-test mysql -u obs -pobs123 obs_api -e "
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_digest VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS deprecated_password VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS deprecated_password_salt VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS deprecated_password_hash_type VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS in_beta BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS beta_features TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS staging_workflow_id INT DEFAULT NULL;
"
```

### Issue 3: bcrypt Password Migration

**Error**: Password authentication failed even after adding columns.

**Root cause**: bcrypt passwords stored in `password` field, but Rails `has_secure_password` expects `password_digest`.

**Fix**:
```bash
docker exec obs-server-test mysql -u obs -pobs123 obs_api -e "
UPDATE users 
SET password_digest = password 
WHERE password_hash_type = 'bcrypt' OR password LIKE '\$2b\$%';
"
```

### Issue 4: Database Out of Sync with Backend

**Symptom**: Backend API (port 5352) shows 9 projects, Rails API (port 4455) shows only `deleted`.

**Diagnosis**:
```bash
# Backend shows projects
curl -s "http://localhost:5352/source/" --user "Admin:admin123" | grep -c "entry name"
# Output: 9

# Rails database shows only deleted
docker exec obs-server-test mysql -u obs -pobs123 obs_api -e "SELECT name FROM projects;"
# Output: deleted
```

**Root cause**: OBS backend stores projects as XML files in `/srv/obs/projects/*.xml`. Rails API uses MySQL `obs_api.projects` table. After container restart or data migration, backend projects exist but Rails database is empty.

**Fix**: Sync backend projects to Rails database:
```bash
docker exec obs-server-test bash -c 'cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner "
  projects = [\"home:Admin\", \"home:Admin:demo-app\", \"home:Admin:hello-world\", \"home:Admin:openEuler24.03-SP1\"]
  projects.each do |p|
    begin
      Project.find_or_create_by(name: p)
      puts \"Synced: #{p}\"
    rescue => e
      puts \"Error syncing #{p}: #{e.message}\"
    end
  end
"'
```

### Issue 5: Missing /app Symlink (Final Fix)

**Error**: `ActionView::MissingTemplate (Missing partial models/_project with {...})`. Rails searching in `/app/views`.

**Diagnosis**:
```bash
docker exec obs-server-test ls -la /app 2>&1
# Output: ls: cannot access '/app': No such file or directory

docker exec obs-server-test ls -la /srv/www/obs/api/app/views/models/
# Output: _project.xml.builder exists
```

**Root cause**: OBS Rails code references `/app/views` but actual templates are at `/srv/www/obs/api/app/views/`. The `/app` symlink was missing.

**Fix**:
```bash
# Create symlink
docker exec obs-server-test ln -s /srv/www/obs/api/app /app

# Restart Rails API
docker exec obs-server-test pkill -f "rails server"
docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && export SECRET_KEY_BASE=$(openssl rand -hex 64) && RAILS_ENV=production bin/rails server -b 0.0.0.0 -p 4455 --daemon'
```

**Verification**:
```bash
curl -s "http://localhost:4455/source/home:Admin/_meta" --user "Admin:admin123"
# Output: <project name="home:Admin">...</project>  (success!)
```

## Automation Scripts Created

After this debugging session, the following automation scripts were created to prevent future manual intervention:

1. **`scripts/check-and-fix-obs.sh`** - OBS service health check and auto-fix
2. **`scripts/init-obs-projects.sh`** - Initialize OBS project structure (DoD + integration project)

## Key Lessons

1. OBS uses **memcached** (not Redis) for Rails cache. Redis is only for backend inter-process communication.
2. OBS Rails API and backend have separate storage: Rails uses MySQL, backend uses XML files.
3. The `/app` symlink is critical for Rails view rendering in some OBS container builds.
4. Always check both APIs (4455 Rails, 5352 backend) when debugging OBS issues.
5. Database schema may be incomplete after container migration - check for missing columns.