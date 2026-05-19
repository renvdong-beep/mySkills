# OBS aarch64 Worker Setup Session Log (2026-05-14)

## Goal
Configure OBS to build aarch64 RPM packages on x86_64 host using qemu-user-static emulation.

## Environment
- Host: openEuler 2403 SP3 (x86_64)
- OBS: openEuler OBS 2.10.15 in Docker container
- Target: aarch64 RPM builds for S5000C ISO image

## Steps Performed

### 1. Install qemu-user-static
```bash
sudo dnf install -y qemu-user-static
# Result: qemu-user-static-8.2.0-73.oe2403sp3.x86_64 installed
```

Verify binfmt_misc configuration:
```bash
cat /proc/sys/fs/binfmt_misc/qemu-aarch64
# Output:
# enabled
# interpreter /usr/bin/qemu-aarch64-static
# flags: F
# offset 0
# magic 7f454c460201010000000000000000000200b700
# mask ffffffffffffff00fffffffffffffffffeffffff
```

### 2. Recreate OBS Container with qemu Mount
```bash
docker stop obs-server-test
docker rm obs-server-test

docker run -d \
  --name obs-server-test \
  --restart unless-stopped \
  --privileged \
  -p 4455:4455 \
  -p 5252:5252 \
  -p 5352:5352 \
  -v /home/nando/AICICD/data/obs:/var/obs \
  -v /usr/bin/qemu-aarch64-static:/usr/bin/qemu-aarch64-static:ro \
  -v /usr/bin/qemu-aarch64-static:/usr/bin/qemu-aarch64:ro \
  obs-server:local
```

### 3. Initialize OBS API Database
```bash
# Run migrations
docker exec obs-server-test bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails db:create db:migrate"

# Create Admin user
docker exec obs-server-test bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner '
  u = User.find_or_initialize_by(login: \"Admin\")
  u.email = \"admin@obs.local\"
  u.password = \"admin123\"
  u.password_confirmation = \"admin123\"
  u.state = \"confirmed\"
  u.save!
'"
```

### 4. Configure Architecture in Database
```bash
docker exec obs-server-test mysql --socket=/var/run/mysqld/mysqld.sock obs_api -e "
INSERT IGNORE INTO architectures (name) VALUES ('x86_64');
INSERT IGNORE INTO architectures (name) VALUES ('aarch64');
UPDATE architectures SET available = 1 WHERE name IN ('x86_64', 'aarch64');
SELECT id, name, available FROM architectures;
"
# Output:
# id  name      available
# 1   x86_64    1
# 2   aarch64   1
```

### 5. Start OBS Backend Services
```bash
# Source server
docker exec -d obs-server-test perl /usr/lib/obs/server/bs_srcserver --port 5352 --daemonize

# Repo server
docker exec -d obs-server-test perl /usr/lib/obs/server/bs_repserver --port 5252 --daemonize

# Dispatcher
docker exec -d obs-server-test perl /usr/lib/obs/server/bs_dispatch --daemonize
```

### 6. Start Workers (x86_64 and aarch64)
```bash
# Create worker directories
docker exec obs-server-test mkdir -p /var/cache/obs-worker/1 /var/cache/obs-worker/2
docker exec obs-server-test mkdir -p /var/run/obs/worker1 /var/run/obs/worker2

# Start x86_64 worker
docker exec -d obs-server-test perl /usr/lib/obs/server/bs_worker \
  --root /var/cache/obs-worker/1 \
  --statedir /var/run/obs/worker1 \
  --arch x86_64 \
  --id worker-1-x86_64 \
  --reposerver http://localhost:5252 --nocodeupdate

# Start aarch64 worker
docker exec -d obs-server-test perl /usr/lib/obs/server/bs_worker \
  --root /var/cache/obs-worker/2 \
  --statedir /var/run/obs/worker2 \
  --arch aarch64 \
  --id worker-2-aarch64 \
  --reposerver http://localhost:5252 --nocodeupdate
```

Verify workers running:
```bash
docker exec obs-server-test ps aux | grep bs_worker
# Output:
# root  413  perl bs_worker --arch x86_64 --id worker-1-x86_64 ...
# root  418  perl bs_worker --arch aarch64 --id worker-2-aarch64 ...
```

### 7. Start OBS API
```bash
docker exec -d obs-server-test bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0"

# Verify API
curl -s -u Admin:admin123 http://localhost:4455/about
# Output:
# <about>
#   <title>Open Build Service API</title>
#   <revision>2.10.15</revision>
# </about>
```

## Blocking Issue: Architecture Not Recognized

### Symptom
```bash
curl -s -X PUT -u Admin:admin123 "http://localhost:4455/source/home:Admin/_meta" -d '
<project name="home:Admin">
  <repository name="standard">
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>'
# Response:
# <status code="not_found">
#   <summary>unknown architecture: 'x86_64'</summary>
# </status>
```

### Investigation
- Architecture exists in database: `SELECT name FROM architectures` shows x86_64, aarch64
- Architecture marked as available: `available = 1`
- OBS API restarted to clear cache
- Issue persists despite all configuration

### Possible Root Causes
1. OBS backend (bs_srcserver) has separate architecture validation from API
2. Project creation requires external repository path dependency (e.g., openEuler:24.03)
3. OBS needs platform configuration files beyond database entries
4. Cache not properly cleared between API and backend

### Next Steps to Resolve
1. Import openEuler base project as dependency: `<path project="openEuler:24.03" repository="standard"/>`
2. Check OBS backend architecture configuration in BSConfig.pm
3. Verify bs_srcserver can access architecture definitions
4. Consider using osc CLI tool instead of direct API calls

## Service Status Summary

| Service | Status | Port | Notes |
|---------|--------|------|-------|
| OBS API | Running | 4455 | Rails server, Admin:admin123 |
| Source Server | Running | 5352 | bs_srcserver daemonized |
| Repo Server | Running | 5252 | bs_repserver daemonized |
| Dispatcher | Running | - | bs_dispatch daemonized |
| x86_64 Worker | Running | - | worker-1-x86_64 |
| aarch64 Worker | Running | - | worker-2-aarch64, qemu enabled |
| MySQL | Running | socket | MariaDB, obs_api database |
| Redis | Running | 6379 | Required for scheduler |

## Key Commands Reference

```bash
# Check worker status
curl -s -u Admin:admin123 http://localhost:4455/worker/status

# Check repo server
docker exec obs-server-test curl -s http://localhost:5252/

# Check source server
docker exec obs-server-test curl -s http://localhost:5352/source

# List architectures in database
docker exec obs-server-test mysql --socket=/var/run/mysqld/mysqld.sock obs_api -e "SELECT * FROM architectures"

# Restart OBS API
docker exec obs-server-test pkill -f "rails server"
docker exec -d obs-server-test bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0"

# Check OBS logs
docker exec obs-server-test tail -50 /srv/www/obs/api/log/production.log
```

## Lessons Learned

1. **qemu-user-static must be mounted into container** - OBS worker needs access to emulator binary
2. **binfmt_misc requires privileged container** - Container must have access to host's binfmt configuration
3. **Architecture database entries required** - OBS API stores architectures in MySQL, not just config files
4. **API and backend may have separate validation** - Architecture recognized by API database but not by backend
5. **Fresh OBS needs full initialization** - Database migration, user creation, architecture setup all required