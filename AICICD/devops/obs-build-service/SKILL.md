---
name: obs-build-service
description: Deploy and troubleshoot OBS (Open Build Service) in container environments. Covers Worker startup, build environment config, DoD setup, and container-specific pitfalls.
tags: [obs, build-service, rpm, packaging, containers, devops, debugging]
---

# OBS (Open Build Service) Container Debugging

Deploy and troubleshoot OBS (Open Build Service) in container environments. Covers Worker startup issues, build environment configuration, DoD (Download on Demand) setup, and common container-specific pitfalls.

## Triggers
- OBS Server/Worker deployment in Docker containers
- OBS build failures with "excluded", "badhost", "blocked" statuses
- Worker cannot find Build.pm or other build scripts
- DoD package download issues
- Dispatcher/Worker communication failures

## Key Components

### OBS Architecture (Container Mode)
- **bs_srcserver** (port 5352): Source file management
- **bs_repserver** (port 5252): Repository/binary management  
- **bs_sched**: Scheduler per architecture (e.g., `bs_sched x86_64`)
- **bs_dispatch**: Job dispatcher to workers
- **bs_worker**: Build execution agents
- **Redis**: Required for scheduler/dispatcher communication

### Startup Sequence
1. Redis: `redis-server --daemonize yes`
2. Source server: `perl bs_srcserver --port 5352 --daemonize`
3. Repo server: `perl bs_repserver --daemonize`
4. Scheduler: `perl bs_sched x86_64` (per arch, no --daemonize)
5. Dispatcher: `perl bs_dispatch` (no --daemonize option)
6. Workers: `perl bs_worker --root /var/cache/obs-worker/${i} --statedir /var/run/obs/worker${i} --arch x86_64 --id worker-${i}-x86_64 --reposerver http://localhost:5252`

## Common Pitfalls & Fixes

### 1. Worker Build.pm Not Found
**Symptom**: `Can't locate Build.pm in @INC` in badhost log
**Root cause**: Worker creates symlink `build -> ../../build` which resolves incorrectly in container (`/run/build` vs `/var/run/obs/build`)
**Fix**:
```bash
mkdir -p /var/run/obs/build
cp -r /usr/lib/obs/server/build/* /var/run/obs/build/
# Worker symlink will now resolve correctly
```

### 2. Package Status "excluded"
**Symptom**: Package shows `excluded` status, never builds
**Root cause**: Project config uses wrong type identifier
**Fix**: In project meta, use `Type: spec` (not `Type: rpm`). OBS expects build type names, not binary type names.

### 3. Worker Marked as "badhost"
**Symptom**: Dispatcher logs `badhost event`, workers never process jobs
**Debug locations**:
- `/srv/obs/jobs/<arch>/.logfile.badhost/<jobid>` - contains error message
- Dispatcher caches badhost in memory - restart to clear
**Fix sequence**:
1. Read badhost log to identify error
2. Fix the underlying issue
3. Remove badhost directory: `rm -rf /srv/obs/jobs/x86_64/.logfile.badhost`
4. Restart dispatcher: `pkill -f bs_dispatch; perl bs_dispatch`

### 4. hostname Command Not Found
**Symptom**: Build log shows `hostname: command not found`
**Fix**: `dnf install -y hostname` (or `apt install hostname`)

### 5. chroot rpm Not Found
**Symptom**: `chroot: failed to run command 'rpm': No such file or directory`
**Root cause**: OBS Worker chroot environment missing rpm binary
**Debug chain**:
1. Check if rpm package is in preinstall list
2. Check if rpm binary exists in chroot: `ls /var/cache/obs-worker/1/usr/bin/rpm`
3. Check dynamic linker: `ls /var/cache/obs-worker/1/lib64/ld-linux-x86-64.so.2`
4. Check library dependencies: `chroot /var/cache/obs-worker/1 /usr/bin/rpmdb --version`
**Fix**: Add required packages to Preinstall in project config:
```
Preinstall: filesystem glibc libgcc rpm-libs bash coreutils rpm
```

### 6. chroot Dynamic Linker Missing
**Symptom**: `chroot: failed to run command '/usr/bin/rpmdb': No such file or directory` (but file exists)
**Root cause**: glibc creates `/lib64` directory, but filesystem package also contains `/lib64` - order conflict
**Fix**: Use `Order:` directive to ensure filesystem installs before glibc:
```
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
```

### 7. Preinstall Library Dependencies
**Symptom**: `/usr/bin/rpmdb: error while loading shared libraries: librpm.so.9: cannot open shared object file`
**Root cause**: rpm package depends on rpm-libs, libcap, libacl, etc. but these aren't in preinstall
**Fix**: Add all required libraries to Preinstall:
```
Preinstall: filesystem setup glibc libgcc libcap libacl libarchive bzip2 xz-libs zstd openssl-libs libselinux libsepol popt readline ncurses lua rpm-libs bash coreutils rpm
```

### 8. bsdtar Directory Conflict
**Symptom**: `./lib64: Can't replace existing directory with non-directory: Directory not empty` during preinstall
**Root cause**: bsdtar (libarchive) is stricter than GNU tar about directory conflicts. When glibc creates `/lib64` before filesystem package tries to create it, bsdtar fails.
**Fix**: Disable bsdtar in init_buildsystem to use GNU tar instead:
```bash
sed -i "s|if test -x /usr/bin/bsdtar ; then|if false ; then # disabled bsdtar|" /var/run/obs/worker1/build/init_buildsystem
```
**Note**: This must be done after Worker creates the build directory but before the build starts. Consider adding to Worker startup script.

### 9. chroot Missing `su` Command
**Symptom**: `chroot: failed to run command 'su': No such file or directory` or `Error: TOPDIR empty`
**Root cause**: OBS build scripts use `chroot $BUILD_ROOT su -c "..."` to switch users, but `su` is in util-linux package
**Fix**: Add `util-linux` to Preinstall:
```
Preinstall: rpm util-linux
```

### 10. gcc Cannot Find `ld` Linker
**Symptom**: `collect2: fatal error: cannot find 'ld'` during compilation
**Root cause**: binutils postinstall script needs `/usr/sbin/alternatives` to create `/usr/bin/ld` symlink. `alternatives` is in chkconfig package.
**Fix**: Add `chkconfig` to Preinstall:
```
Preinstall: rpm util-linux chkconfig
```

### 11. DoD (Download on Demand) Setup for Cross-Architecture Builds
**Purpose**: DoD allows OBS to download package metadata from external repositories on demand, enabling dependency resolution without mirroring entire distro repos.

**Setup workflow**:
1. Create a DoD base project (e.g., `home:Admin:openEuler24.03`) pointing to the external repo:
   ```bash
   curl -s -u Admin:admin123 -X PUT -H "Content-Type: text/xml" \
     -d '<project name="home:Admin:openEuler24.03">
       <title>openEuler 24.03 Base for aarch64</title>
       <repository name="standard" rebuild="local" block="local">
         <download arch="aarch64" url="https://repo.openeuler.org/openEuler-24.03-LTS-SP3/everything/aarch64/" repotype="rpmmd"/>
         <arch>aarch64</arch>
       </repository>
     </project>' \
     "http://localhost:4455/source/home:Admin:openEuler24.03/_meta"
   ```

2. Add DoD project as path in main project:
   ```xml
   <repository name="standard">
     <path project="home:Admin:openEuler24.03" repository="standard"/>
     <arch>x86_64</arch>
     <arch>aarch64</arch>
   </repository>
   ```

3. Set DoD project `_config` with same prjconf as main project:
   ```bash
   curl -s -u Admin:admin123 -X PUT -d 'Type: rpm
   Required: rpm-build
   Preinstall: rpm util-linux chkconfig
   ' "http://localhost:4455/source/home:Admin:openEuler24.03/_config"
   ```

4. Run `bs_dodup` manually to trigger DoD data download:
   ```bash
   docker exec obs-server-test perl /usr/lib/obs/server/bs_dodup \
     --dodfile /srv/obs/dods/home:Admin:openEuler24.03::standard::aarch64
   ```

5. Verify DoD data downloaded:
   - Check `/srv/obs/build/<DoD-project>/standard/<arch>/:full/doddata` exists (binary metadata)
   - Check `/srv/obs/build/<DoD-project>/standard/<arch>/:full.solv` exists (libsolv index, ~5MB for full repo)

**Critical**: openEuler uses **zstd compression** for RPMs. The `bs_dodup` script only supports `.gz` and `.xz` by default. You MUST patch it to add `.zst` support:
```bash
# Patch bs_dodup for zstd support
docker exec obs-server-test bash -c '
cp /usr/lib/obs/server/bs_dodup /usr/lib/obs/server/bs_dodup.bak
# Line ~151: change regex to include zst
sed -i "151s/(gz|xz)/(gz|xz|zst)/" /usr/lib/obs/server/bs_dodup
# Line ~153: change decompress command to handle zst
sed -i "153s/my \$decmp = \$1 eq '\''gz'\'' ? '\''gunzip'\'' : '\''xzdec'\'';/my \$comp = \$1; my \$decmp = \$comp eq '\''gz'\'' ? '\''gunzip'\'' : \$comp eq '\''xz'\'' ? '\''xzdec'\'' : '\''zstd'\'';/" /usr/lib/obs/server/bs_dodup
# Verify: zstd must be installed
which zstd || dnf install -y zstd
'
```

**DoD data flow**: doddata (binary package metadata) → bs_repserver generates :full.solv (libsolv index) → Scheduler loads solv into dependency pool → packages can resolve BuildRequire against the full distro repo

**Pitfall**: If Scheduler still marks packages as `excluded` after DoD setup, the main project's `:full.solv` may be empty (120 bytes = no packages). This means Scheduler failed to merge the DoD project's solv into the main project's dependency pool. Check:
- `ls -la /srv/obs/build/<main-project>/standard/<arch>/:full.solv` — should be >120 bytes
- `ls -la /srv/obs/build/<DoD-project>/standard/<arch>/:full.solv` — should be ~5MB
- Restart Scheduler after DoD data download: `pkill -f bs_sched <arch>; perl bs_sched <arch>`

### 11b. DoD :full Directory Permission Mismatch
**Symptom**: bs_dodup silently fails to write doddata/doddata.cookie; Scheduler reports "downloading N dod packages" indefinitely even though :full directory has RPMs
**Root cause**: Manually downloaded RPMs (via curl from host) are owned by `nando:nando` or other user, but bs_dodup/Scheduler run as `obsrun:obsrun`
**Fix**:
```bash
docker exec obs-server-test chown -R obsrun:obsrun /srv/obs/build/<DoD-project>/standard/<arch>/:full/
```
**Critical**: ALWAYS chown :full directory to obsrun after manually placing RPMs. Without write permission, bs_dodup cannot create doddata/doddata.cookie, and the Scheduler cannot update :full.solv.

### 11c. DoD URL vs RPM Version Mismatch
**Symptom**: doddata generated but Scheduler still reports "downloading N dod packages" indefinitely; number decreases slowly then gets stuck
**Root cause**: DoD project `<download>` URL points to a different repo version than the manually downloaded RPMs. E.g., URL points to `openEuler-24.03-LTS-SP3` (oe2403sp3 packages) but :full contains RPMs from `openEuler-24.03-LTS` (oe2403 packages). doddata is generated from the remote URL metadata, so it references packages that don't match what's in :full.
**Fix**: Ensure DoD project XML URL matches the actual RPM source:
```bash
# Update the <download> URL in the project XML
docker exec obs-server-test bash -c '
cat > /srv/obs/projects/home:Admin:openEuler24.03.xml << "XMLEOF"
<project name="home:Admin:openEuler24.03">
  <repository name="standard">
    <download arch="aarch64" repotype="rpmmd" url="https://repo.openeuler.org/openEuler-24.03-LTS/everything/aarch64/"/>
    <arch>aarch64</arch>
  </repository>
</project>
XMLEOF
'
```

### 11d. DoD "downloading N dod packages" — Intermediate Status
**Meaning**: Scheduler has resolved dependencies but N packages are not yet in :full directory. It sends download requests to repserver which forwards to bs_dodup.
**Progress**: The number decreases as bs_dodup downloads packages automatically (e.g., 58 → 51 → 2 over ~10 minutes).
**If stuck at small number**: The remaining packages may not exist in the remote repo, or download is failing silently. Debug:
- `ls -lt /srv/obs/build/<DoD-project>/standard/<arch>/:full/` — check if new files appearing
- `cat /srv/obs/build/<main-project>/standard/<arch>/:packstatus` — check packerror message
- Run bs_dodup with `--dodfile` to force recheck
- Consider manual download workaround (see references/dod-deep-debug.md)

### 11e. DoD doddata Regeneration Workflow
When doddata gets out of sync with :full directory contents (e.g., after URL change or manual RPM placement):
1. Delete doddata and cookie: `rm -f :full/doddata :full/doddata.cookie`
2. Delete all Scheduler caches: `rm -f :packstatus :schedulerstate :full.solv`
3. Run bs_dodup manually: `./bs_dodup --dodfile /srv/obs/dods/<dodfile>`
4. Restart Scheduler: `pkill -f bs_sched; ./bs_sched aarch64`

**Key**: bs_dodup generates doddata by fetching repomd.xml from the remote URL, NOT by scanning :full directory. doddata reflects what's available remotely, not what's already downloaded locally.

### 11f. Manual RPM Download to :full Directory (Workaround)
When bs_dodup can't download all packages automatically, download manually:
```bash
# Download in parallel using xargs + curl (wget may fail on some repos)
cat /tmp/wget_list.txt | xargs -P 8 -I {} curl -sL -o /tmp/rpms/{}  {}

# Copy to :full with OBS naming convention (name.rpm, NOT full-versioned name)
for f in /tmp/rpms/*.rpm; do
  name=$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)
  [ -n "$name" ] && cp "$f" ":full_dir/$name.rpm"
done

# CRITICAL: Fix permissions!
chown -R obsrun:obsrun :full_dir/

# Clear caches and restart
rm -f :packstatus :schedulerstate :full.solv
pkill -f bs_sched; ./bs_sched aarch64
```

### 11g. DoD Meta File Missing (Legacy)
**Symptom**: Worker fails to get DoD package binaries
**Fix**: Create empty meta files for DoD packages as workaround:
```bash
touch /srv/obs/repos/<project>/<repo>/<arch>/<package>.meta
```

### 11h. DoD d0d0d0d0 Placeholder — Packages Exist in :full but Scheduler Still Says "downloading N dod packages"
**Symptom**: `:full` directory contains all needed RPMs, but Scheduler still reports "downloading N dod packages" indefinitely. Build stays `blocked`.
**Root cause**: `BSSched/DoD.pm` `readparsed()` function (line 55-56) forces ALL DoD package `hdrmd5` to `d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0` placeholder. Even when actual RPMs exist in `:full`, the solv built from doddata retains placeholder pkgids. Scheduler's `dodcheck()` (line 163) sees placeholder pkgid → marks package as needing download → dodfetch() → repserver → but repserver also checks for placeholder → circular failure.
**Additionally**: `addrepo_scan()` (BuildRepo.pm line 957-961) short-circuits if existing `:full.solv` is "external" (from doddata) — it returns the doddata-based solv WITHOUT scanning `:full` directory for actual RPMs. So `updatefrombins()` never runs, and manually placed RPMs are never indexed.
**Fix**: Remove doddata entirely so Scheduler builds solv from actual :full RPMs:
```bash
# 1. Kill bs_dodup (it will regenerate doddata otherwise)
pkill -9 -f bs_dodup

# 2. Kill scheduler
pkill -f "bs_sched <arch>"

# 3. Delete doddata and ALL caches (both DoD and main project)
rm -f /srv/obs/build/<DoD-project>/standard/<arch>/:full/doddata
rm -f /srv/obs/build/<DoD-project>/standard/<arch>/:full/doddata.cookie
rm -f /srv/obs/build/<DoD-project>/standard/<arch>/:full.solv
rm -f /srv/obs/build/<DoD-project>/standard/<arch>/:packstatus
rm -f /srv/obs/build/<DoD-project>/standard/<arch>/:schedulerstate
rm -f /srv/obs/build/<main-project>/standard/<arch>/:full.solv
rm -f /srv/obs/build/<main-project>/standard/<arch>/:packstatus
rm -f /srv/obs/build/<main-project>/standard/<arch>/:schedulerstate
rm -f /srv/obs/build/<main-project>/standard/<arch>/:depends

# 4. Restart scheduler (WITHOUT bs_dodup)
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && ./bs_sched <arch>'
```
**Result**: Without doddata, solv is built from :full RPMs with real pkgids (~50KB vs ~5MB). Error changes from vague "downloading N dod packages" to specific "unresolvable: nothing provides X needed by Y" — which is actually more useful for debugging.
**Trade-off**: Without doddata, Scheduler can only resolve deps against packages physically in :full. Missing transitive deps produce clear "unresolvable" errors. You must manually download ALL needed packages to :full.
**Better approach**: Use `dnf install --downloadonly --downloaddir=/tmp/rpm-deps rpm-build` to download the full dependency tree, then copy to :full with OBS naming (`name.rpm` format).
**See**: `references/dod-placeholder-mechanism.md` for full source code trace and detailed explanation

### 12. API Authentication
**Default credentials**: Admin/admin (may be changed to Admin/admin123 in some deployments)
**Test**: `curl -u Admin:admin http://localhost:4455/build`

### 13. aarch64 Worker Setup (Cross-Architecture Builds)
**Symptom**: Worker fails with "native compile is not possible, an emulator via binfmt misc handler must be configured"
**Root cause**: Building aarch64 on x86_64 host requires qemu-user-static for emulation
**Fix sequence**:
1. Install qemu-user-static on host: `sudo dnf install -y qemu-user-static`
2. Verify binfmt_misc is configured: `cat /proc/sys/fs/binfmt_misc/qemu-aarch64` (should show "enabled")
3. Mount qemu into OBS container:
   ```bash
   docker run -d --name obs-server \
     --privileged \
     -v /usr/bin/qemu-aarch64-static:/usr/bin/qemu-aarch64-static:ro \
     -v /usr/bin/qemu-aarch64-static:/usr/bin/qemu-aarch64:ro \
     ...
   ```
4. Start aarch64 worker:
   ```bash
   docker exec -d obs-server perl /usr/lib/obs/server/bs_worker \
     --root /var/cache/obs-worker/2 \
     --statedir /var/run/obs/worker2 \
     --arch aarch64 \
     --id worker-2-aarch64 \
     --reposerver http://localhost:5252 --nocodeupdate
   ```

### 14. Architecture Not Recognized by OBS API
**Symptom**: Creating project returns "unknown architecture: 'x86_64'" or "unknown architecture: 'aarch64'"
**Root cause**: OBS API (Rails) stores architectures in MySQL database, but they may not be populated after fresh install
**Fix**: Insert architectures into database and mark as available:
```bash
docker exec obs-server mysql --socket=/var/run/mysqld/mysqld.sock obs_api -e "
INSERT IGNORE INTO architectures (name) VALUES ('x86_64');
INSERT IGNORE INTO architectures (name) VALUES ('aarch64');
INSERT IGNORE INTO architectures (name) VALUES ('loongarch64');
UPDATE architectures SET available = 1 WHERE name IN ('x86_64', 'aarch64', 'loongarch64');
"
```
**Critical**: Must clear Rails cache after database changes:
```bash
docker exec obs-server bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner 'Rails.cache.clear'"
```
Then restart OBS API:
```bash
docker exec obs-server pkill -f "rails server"
docker exec -d obs-server bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0"
```

### 15. OBS API Database Initialization
**Symptom**: "Table 'obs_api.roles' doesn't exist" when starting OBS API
**Root cause**: Fresh OBS container needs database migration
**Fix**:
```bash
docker exec obs-server bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails db:create db:migrate"
```
**Create Admin user**:
```bash
docker exec obs-server bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner '
  u = User.find_or_initialize_by(login: \"Admin\")
  u.email = \"admin@obs.local\"
  u.password = \"admin123\"
  u.password_confirmation = \"admin123\"
  u.state = \"confirmed\"
  u.save!
'"
```

### 16. OBS Project File Format (Backend Storage)
**Symptom**: Project exists in API database but backend returns "project does not exist"
**Root cause**: OBS backend (bs_srcserver) uses different storage format than API
**Discovery**: Backend expects `$projectsdir/$projid.xml` flat files, NOT `$projectsdir/$projid/_meta` subdirectories
**Fix**: Create project XML file in correct location:
```bash
# Correct format
cat > /srv/obs/projects/home:Admin.xml << 'EOF'
<project name="home:Admin">
  <title>Admin Home Project</title>
  <repository name="standard">
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>
EOF
chown obsrun:obsrun /srv/obs/projects/home:Admin.xml

# WRONG format (will not work)
# mkdir -p /srv/obs/projects/home:Admin
# cat > /srv/obs/projects/home:Admin/_meta << 'EOF'
# ...
```
### 42. OBS Rails API Returns 500 — memcached Not Running

**Symptom**: OBS API calls return 500 Internal Server Error with `Dalli::RingError: No server available` in production.log

**Root cause**: OBS Rails API uses memcached (via Dalli gem) for caching. If memcached is not running or the configured hostname cannot be resolved, all API calls fail.

**Diagnosis**:
```bash
# Check if memcached is running
docker exec obs-server-test ps aux | grep memcached

# Check memcached_host configuration
docker exec obs-server-test cat /srv/www/obs/api/config/options.yml | grep memcached_host
```

**Fix**:
1. Modify memcached_host to localhost if configured as unresolvable hostname:
   ```bash
   docker exec obs-server-test sed -i 's/memcached_host: cache/memcached_host: localhost/' /srv/www/obs/api/config/options.yml
   ```

2. Start memcached:
   ```bash
   docker exec obs-server-test memcached -d -u root
   ```

3. Restart OBS Rails API:
   ```bash
   docker exec obs-server-test pkill -f "rails server"
   docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && export SECRET_KEY_BASE=$(openssl rand -hex 64) && RAILS_ENV=production bin/rails server -b 0.0.0.0 -p 4455 --daemon'
   ```

**Note**: OBS uses memcached (not Redis) for Rails cache. Redis is used by OBS backend (bs_sched, bs_dispatch) for inter-process communication.

### 43. OBS Rails API Returns 500 — Missing Database Columns

**Symptom**: OBS API calls return 500 with `NameError: undefined local variable or method 'X' for #<Project:...>` or `#<User:...>`

**Root cause**: OBS Rails code expects database columns that don't exist after migration or fresh install. Common missing columns:
- `users.password_digest` (bcrypt authentication)
- `users.deprecated_password`, `deprecated_password_salt`, `deprecated_password_hash_type` (legacy MD5)
- `projects.staging_workflow_id` (staging feature)
- `users.in_beta`, `users.beta_features` (beta features)

**Fix**: Add missing columns:
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

Then restart Rails API.

### 45. OBS Rails API Database Out of Sync with Backend Projects

**Symptom**: 
- OBS backend API (port 5352) returns project list with multiple projects
- OBS Rails API (port 4455) returns `unknown_project` for the same projects
- Database query shows only `deleted` project: `SELECT name FROM projects;` → only `deleted`

**Root cause**: OBS backend stores projects as XML files in `/srv/obs/projects/*.xml`, while Rails API uses MySQL database `obs_api.projects` table. After container restart or data migration, backend projects may exist but Rails database may be empty or stale.

**Diagnosis**:
```bash
# Check backend projects (should show many)
curl -s "http://localhost:5352/source/" --user "Admin:admin123"

# Check Rails database projects (may show only 'deleted')
docker exec obs-server-test mysql -u obs -pobs123 obs_api -e "SELECT name FROM projects;"
```

**Fix**: Sync backend projects to Rails database using Rails runner:
```bash
# Get list of backend projects
PROJECTS=$(curl -s "http://localhost:5352/source/" --user "Admin:admin123" | grep -oP 'entry name="[^"]+"' | sed 's/entry name="//;s/"//')

# Sync each project to database
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

**Note**: This is a one-time fix after data migration. New projects created via Rails API will automatically sync to database.

**Alternative**: Use backend API (port 5352) directly for project creation if Rails API is problematic. Backend API writes to both XML files AND triggers database sync.

**Symptom**: OBS API returns 500 with `ActionView::MissingTemplate (Missing partial models/_project with {...})`. Error shows Rails is searching in `/app/views` but templates exist at `/srv/www/obs/api/app/views/`.

**Root cause**: OBS Rails code references `/app/views` but the actual view templates are at `/srv/www/obs/api/app/views/`. In some OBS container builds (especially 2.10.28+), the `/app` symlink is missing.

**Diagnosis**:
```bash
# Check if /app symlink exists
docker exec obs-server-test ls -la /app 2>&1
# Expected: lrwxrwxrwx ... /app -> /srv/www/obs/api/app

# Check if view templates exist
docker exec obs-server-test ls -la /srv/www/obs/api/app/views/models/
```

**Fix**: Create the missing symlink:
```bash
# Create /app symlink pointing to OBS API app directory
docker exec obs-server-test ln -s /srv/www/obs/api/app /app

# Restart OBS Rails API
docker exec obs-server-test pkill -f "rails server"
docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && export SECRET_KEY_BASE=$(openssl rand -hex 64) && RAILS_ENV=production bin/rails server -b 0.0.0.0 -p 4455 --daemon'
```

**Persistence**: Add symlink creation to `/start-obs.sh`:
```bash
# Add near the top of /start-obs.sh
[ ! -e /app ] && ln -s /srv/www/obs/api/app /app
```

**Verification**: `curl -s "http://localhost:4455/source/home:Admin/_meta" --user "Admin:admin123"` should return XML, not 500 error.

**See**: `references/obs-rails-api-500-debug.md` for complete debugging session including memcached, database columns, and database sync issues.

### 18. OBS Project Validation Error on Build Element
**Symptom**: Creating project via API returns "validation error: 11:0: ERROR: Error validating value"
**Root cause**: Empty `<enable/>` element in `<build>` section causes XML schema validation failure
**Fix**: Remove `<build>` section entirely or use proper format:
```bash
# WRONG - causes validation error
curl -X PUT -u Admin:admin123 "http://localhost:4455/source/home:Admin/_meta" -d '
<project name="home:Admin">
  <build>
    <enable/>
  </build>
  ...
</project>'

# CORRECT - omit build section or use proper attributes
curl -X PUT -u Admin:admin123 "http://localhost:4455/source/home:Admin/_meta" -d '
<project name="home:Admin">
  <title>Admin Home Project</title>
  <repository name="standard">
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>'
```

### 19. OBS Container Data Directory Migration
**Symptom**: OBS container `/srv/obs` data lost on container recreation, or root partition fills up
**Root cause**: OBS stores build data, sources, and repositories in `/srv/obs` by default, which is inside container filesystem
**Critical**: Always mount OBS data directories to host to persist data and avoid root partition issues
**Fix**: Mount OBS directories to external storage:
```bash
# Create host directories (on large partition like /home)
mkdir -p /home/nando/AICICD/data/obs-srv/obs
mkdir -p /home/nando/AICICD/data/obs

# Run container with mounts
docker run -d --name obs-server \
  -v /home/nando/AICICD/data/obs-srv/obs:/srv/obs \
  -v /home/nando/AICICD/data/obs:/var/obs \
  ...
```
**Best practice**: Add to project AGENTS.md: "All disk-consuming directories MUST be created under /home/nando/AICICD"

### 17. OBS Roles Missing in Database
**Symptom**: Creating project returns "Couldn't find Role 'maintainer'"
**Root cause**: Fresh OBS install missing default roles in database
**Fix**: Insert required roles:
```bash
docker exec obs-server mysql --socket=/var/run/mysqld/mysqld.sock obs_api -e "
INSERT IGNORE INTO roles (title, global, created_at, updated_at) VALUES 
('Admin', 1, NOW(), NOW()),
('maintainer', 1, NOW(), NOW()),
('bugowner', 1, NOW(), NOW()),
('reviewer', 1, NOW(), NOW()),
('downloader', 1, NOW(), NOW()),
('reader', 1, NOW(), NOW());
"
```

### 18. BSConfig.pm Hostname Affects Build Dispatch
**Symptom**: `osc buildinfo` returns "unknown host '<hostname>'"
**Root cause**: BSConfig.pm uses `Net::Domain::hostfqdn()` which may return container hostname that workers cannot resolve
**Fix**: Override hostname in BSConfig.pm:
```bash
docker exec obs-server bash -c 'cat >> /usr/lib/obs/server/BSConfig.pm << "EOF"

# Override hostname for local development
our $srcserver = "http://localhost:5352";
our $reposerver = "http://localhost:5252";
EOF'
```
**Then restart all backend services**

### 19. Worker `build/build` Script Missing in Container
**Symptom**: Build fails immediately with `/var/run/obs/worker2/build/build: No such file or directory` or `Permission denied`
**Root cause**: OBS Worker expects `$statedir/build/build` to be an executable shell script (the OBS build system launcher). In container environments, this directory is not automatically populated. Worker calls `system("$statedir/build/build", @args)` (bs_worker line 221/3091) to execute builds.
**Fix**: Copy `/usr/lib/build/` contents into worker's statedir:
```bash
# CRITICAL: Copy contents, NOT the directory itself (to avoid nesting)
# Wrong: cp -a /usr/lib/build /var/run/obs/worker2/build  → creates /var/run/obs/worker2/build/build/ (nested dir)
# Right: cp -a /usr/lib/build/ /var/run/obs/worker2/build/  → creates /var/run/obs/worker2/build/build (script)
docker exec obs-server-test bash -c 'rm -rf /var/run/obs/worker2/build; cp -a /usr/lib/build/ /var/run/obs/worker2/build/'
# Verify: build should be a script, NOT a directory
docker exec obs-server-test file /var/run/obs/worker2/build/build
# Expected: "Bourne-Again shell script, ASCII text executable"
```
**Pitfall**: Using `cp -a /usr/lib/build /var/run/obs/worker2/build` (without trailing slash on source) creates a nested directory structure where `$statedir/build/build` becomes a directory instead of a script, causing "Permission denied" or "Is a directory" errors.

### 20. binfmt_misc Not Mounted in Privileged Container
**Symptom**: aarch64 Worker fails to execute aarch64 binaries; qemu-aarch64-static exists but `cat /proc/sys/fs/binfmt_misc/qemu-aarch64` fails inside container
**Root cause**: Even with `--privileged`, Docker containers may not mount `binfmt_misc` filesystem automatically. The host has qemu-aarch64 registered in binfmt_misc, but the container doesn't inherit the mount.
**Fix**:
```bash
# Mount binfmt_misc inside container
docker exec obs-server-test mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
# Verify registration
docker exec obs-server-test cat /proc/sys/fs/binfmt_misc/qemu-aarch64 | head -3
# Expected: "enabled", "interpreter /usr/bin/qemu-aarch64-static"
```
**Note**: This must be done after container startup. If container is restarted, binfmt_misc mount is lost and must be re-applied.

### 21. openEuler python-setuptools-wheel vs python-setuptools Version Mismatch
**Symptom**: After removing doddata (pitfall 11h), build shows "unresolvable: nothing provides python-pip-wheel needed by python3, nothing provides python-setuptools-wheel needed by python3"
**Root cause**: python3 RPM (`python3-3.11.6-2.oe2403`) depends on virtual packages `python-pip-wheel` and `python-setuptools-wheel`. In openEuler 24.03 LTS, `python-setuptools-68.0.0-1.oe2403` does NOT PROVIDES `python-setuptools-wheel`. Only the SP3 version `python-setuptools-68.0.0-2.oe2403sp3` does. Same pattern for `python-pip-wheel`: LTS version `python3-pip-23.3.1-1.oe2403` doesn't provide it, but SP3 `python-pip-wheel-23.3.1-7.oe2403sp3` does.
**How to diagnose**: Use `rpm -qp --provides <rpm>` to check if a package provides the needed virtual package:
```bash
# Check if python-setuptools provides python-setuptools-wheel
rpm -qp --provides python-setuptools.rpm | grep setuptools-wheel
# LTS version: empty output (no provides)
# SP3 version: "python-setuptools-wheel"
```
**Fix**: Replace LTS RPMs with SP3 versions in `:full` directory:
```bash
# Download SP3 versions (noarch packages, work for any arch)
curl -sL -o /tmp/python-setuptools-sp3.rpm \
  "https://repo.openeuler.org/openEuler-24.03-LTS-SP3/everything/aarch64/Packages/python-setuptools-68.0.0-2.oe2403sp3.noarch.rpm"
curl -sL -o /tmp/python-pip-wheel-sp3.rpm \
  "https://repo.openeuler.org/openEuler-24.03-LTS-SP3/everything/aarch64/Packages/python-pip-wheel-23.3.1-7.oe2403sp3.noarch.rpm"

# Replace in :full directory (use OBS naming: name.rpm)
sudo cp /tmp/python-setuptools-sp3.rpm <full_dir>/python-setuptools.rpm
sudo cp /tmp/python-pip-wheel-sp3.rpm <full_dir>/python-pip-wheel.rpm
sudo chown 1000:1000 <full_dir>/python-setuptools.rpm <full_dir>/python-pip-wheel.rpm
```
**General lesson**: When mixing LTS and SP3 packages in OBS `:full`, always verify `Provides` metadata. openEuler LTS packages may lack virtual package provides that SP3 versions add. Use `rpm -qp --provides` to verify before placing RPMs.
**Alternative approach**: Use `dnf install --downloadonly --downloaddir=/tmp/rpm-deps rpm-build` on an SP3 system to get a complete, compatible dependency tree.

### 22. Worker Stays Idle Despite Scheduled Build — Multi-Cause Diagnosis

**Symptom**: Build status is `scheduled` but Worker remains `idle` indefinitely, never picks up the job

There are **multiple root causes** for this symptom. Diagnose in this order:

#### Cause A: Worker marked as badhost (most common after previous build failures)
**Root cause**: After a build failure, `bs_dispatch` marks the worker as a "bad host" in `/srv/obs/run/dispatch.badhosts`. It also writes to `/srv/obs/jobs/<arch>/.logfile.badhost/<jobid>`. Once marked, dispatch will never assign jobs to that worker again, even after the underlying issue is fixed.
**Diagnosis**:
```bash
# Check if worker is in badhosts
docker exec obs-server-test cat /srv/obs/run/dispatch.badhosts 2>/dev/null | strings
# Check badhost log files
docker exec obs-server-test ls /srv/obs/jobs/aarch64/.logfile.badhost/ 2>/dev/null
docker exec obs-server-test cat /srv/obs/jobs/aarch64/.logfile.badhost/* 2>/dev/null
```
**Fix**:
```bash
# 1. Remove badhost data
docker exec obs-server-test rm -f /srv/obs/run/dispatch.badhosts
docker exec obs-server-test rm -rf /srv/obs/jobs/aarch64/.logfile.badhost/
# 2. Restart dispatcher (it caches badhosts in memory)
docker exec obs-server-test bash -c 'kill $(pgrep bs_dispatch); sleep 2'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_dispatch'
```

#### Cause B: Worker missing --srcserver parameter
**Root cause**: Worker needs `--srcserver` parameter to connect to the source server. Without it, Worker cannot fully process jobs from the dispatcher. The `--reposerver` parameter alone is insufficient — reposerver only provides binary packages, not source access.
**Fix**: Always include `--srcserver` when starting workers:
```bash
# WRONG - Worker can't fully process jobs
perl bs_worker --root /var/cache/obs-worker/2 --statedir /var/run/obs/worker2 \
  --arch aarch64 --id worker-2-aarch64 --reposerver http://localhost:5252 --nocodeupdate

# CORRECT - Worker can get jobs from dispatcher
perl bs_worker --root /var/cache/obs-worker/2 --statedir /var/run/obs/worker2 \
  --arch aarch64 --id worker-2-aarch64 \
  --srcserver http://localhost:5352 \
  --reposerver http://localhost:5252 --nocodeupdate
```

#### Cause C: Worker receives job but code check triggers rebooting
**Root cause**: When dispatch assigns a job via HTTP PUT `/build`, it sends `workercode` and `buildcode` parameters (MD5 of `/usr/lib/obs/server/` and `$statedir/build/` directories). If these don't match the Worker's current codes, the Worker enters `rebooting` state to update its code, then cycles back to idle without executing the build.
**Diagnosis**: Run Worker in foreground to see the code check output:
```bash
docker exec obs-server-test bash -c '
  kill $(pgrep -f "worker-2-aarch64") 2>/dev/null
  cd /usr/lib/obs/server
  timeout 30 perl bs_worker --root /var/cache/obs-worker/2 \
    --statedir /var/run/obs/worker2 \
    --arch aarch64 --id worker-2-aarch64 \
    --srcserver http://localhost:5352 \
    --reposerver http://localhost:5252 --nocodeupdate 2>&1
'
```
**Fix**: Ensure Worker's `$statedir/build/` directory is in sync with `/usr/lib/build/`:
```bash
docker exec obs-server-test bash -c 'rm -rf /var/run/obs/worker2/build; cp -a /usr/lib/build/ /var/run/obs/worker2/build/'
```

#### Dispatch→Worker Job Assignment Flow (for debugging)
Understanding the flow helps diagnose idle workers:
1. **Scheduler** creates job file in `/srv/obs/jobs/<arch>/<jobid>`
2. **Dispatcher** (main loop every ~1s) reads idle workers from `/srv/obs/workers/idle/`, reads jobs from `/srv/obs/jobs/<arch>/`, matches via `BSCando::cando` architecture compatibility
3. **Dispatcher** calls `assignjob()` which does HTTP PUT to `http://<worker_ip>:<worker_port>/build` with buildinfo XML + `workercode` + `buildcode` + `port` + `registerserver` parameters
4. **Worker** (HTTP server via BSServer) receives PUT `/build`, calls `startbuild()`, checks idle state, checks workercode/buildcode, writes job to `$statedir/job`, exits HTTP server loop, begins build

**Key debug commands**:
```bash
# Verify dispatch can see idle worker
docker exec obs-server-test ls -la /srv/obs/workers/idle/
# Worker info (ip, port, hostarch)
docker exec obs-server-test cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | head -3
# Verify dispatch is assigning (run foreground briefly)
docker exec obs-server-test timeout 5 perl /usr/lib/obs/server/bs_dispatch 2>&1
# Look for: "assignjob <arch>/<job> -> <arch>:<workerid>" and "assigned N jobs"
# Check if Worker received job file
docker exec obs-server-test cat /var/run/obs/worker2/job 2>/dev/null | head -5
# Check Worker state
docker exec obs-server-test cat /var/run/obs/worker2/state
```

### 23. BUILD_ROOT Must Be Owned by root
**Symptom**: Build fails immediately with `BUILD_ROOT=/var/cache/obs-worker/N must be owned by root. Exit...` in Worker log. Previous builds may have shown `/var/run/obs/workerN/build/build: Permission denied` (misleading error — the real cause is BUILD_ROOT ownership, not the build script itself).
**Root cause**: OBS `build` script (init_buildsystem) checks that BUILD_ROOT is owned by root. If the `--root` directory (e.g., `/var/cache/obs-worker/2`) is owned by `obsrun` or any non-root user, the build script exits immediately. This commonly happens when OBS Worker creates the directory as `obsrun` during first startup, or when `rm -rf` + directory recreation changes ownership.
**Fix**:
```bash
docker exec obs-server-test chown root:root /var/cache/obs-worker/2
# Verify
docker exec obs-server-test stat /var/cache/obs-worker/2 | grep Uid
# Expected: Uid: (0/root)
```
**Pitfall**: After fixing BUILD_ROOT ownership, you MUST also clear `dispatch.badhosts` because the previous build failure caused dispatch to mark the worker as a bad host. Without clearing badhosts, dispatch will never assign jobs to the worker again even though the root cause is fixed:
```bash
docker exec obs-server-test rm -f /srv/obs/run/dispatch.badhosts
docker exec obs-server-test bash -c 'kill $(pgrep bs_dispatch); sleep 2'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_dispatch'
```

### 24. gcc Missing in aarch64 Chroot — BuildRequires and DoD Dependencies
**Symptom**: aarch64 build log shows `gcc: command not found` during `%build` phase, even though gcc.rpm exists in the DoD `:full` directory.
**Root cause (two-part)**:
1. **Spec missing BuildRequires**: If the spec file uses `gcc` in `%build` but doesn't declare `BuildRequires: gcc`, the OBS scheduler won't include gcc in the buildinfo's `<bdep>` list, and the `build` script won't install gcc into the chroot.
2. **DoD :full missing gcc dependencies**: Even with `BuildRequires: gcc`, the scheduler can only resolve dependencies against packages physically present in `:full`. gcc requires `gmp` and `isl` (among others). If these are missing from `:full`, the scheduler marks the build as `unresolvable`.

**Fix for part 1**: Add `BuildRequires: gcc` to the spec file:
```bash
# Update spec via OBS API
curl -s -u Admin:admin123 -X PUT --data-binary @- \
  "http://localhost:4455/source/home:Admin/hello-world/hello-world.spec" << 'EOF'
Name:           hello-world
Version:        1.0.0
...
BuildRequires:  gcc
...
EOF
```

**Fix for part 2**: Download missing gcc dependencies to DoD `:full` directory:
```bash
# openEuler 24.03 LTS CDN URL (repo.openeuler.org redirects to dl-cdn.openeuler.openatom.cn)
REPO_URL="https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS/OS/aarch64/Packages"

# Download inside container (host may have permission issues with container-owned files)
docker exec obs-server-test bash -c '
  cd /srv/obs/build/home:Admin:openEuler24.03/standard/aarch64/:full/
  # Note: openEuler 24.03 LTS uses gmp-6.3.0 (not 6.2.1) and isl-0.24 (not 0.17)
  curl -sLO "${REPO_URL}/gmp-6.3.0-2.oe2403.aarch64.rpm"
  curl -sLO "${REPO_URL}/isl-0.24-2.oe2403.aarch64.rpm"
  chown obsrun:obsrun gmp-*.rpm isl-*.rpm
'

# Then restart scheduler to re-scan :full and regenerate solv
docker exec obs-server-test bash -c 'kill $(pgrep -f "bs_sched.*aarch64")'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_sched aarch64'
```

**General lesson**: When building packages with `BuildRequires` on aarch64 via DoD, always verify that ALL transitive dependencies of the required packages exist in `:full`. Use `rpm -qpR <rpm>` to check dependencies, then verify each dependency RPM is present in `:full`. openEuler LTS version numbers may differ from what you expect — always check the actual repository listing first.

**openEuler CDN URL note**: `https://repo.openeuler.org/openEuler-24.03-LTS/` redirects (302) to `https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS/`. Use the CDN URL directly to avoid redirect delays. Package listing is available at `${REPO_URL}/` — grep for `href="pkgname"` to find exact filenames.

### 25. GitLab Runner Cannot Access OBS API
**Symptom**: CI job fails with `curl: (7) Failed to connect to <host-ip> port 4455: Connection refused`
**Root cause**: GitLab Runner creates job containers with bridge network, isolating them from host
**Fix**: Configure runner to use host network:
```bash
# Edit /etc/gitlab-runner/config.toml inside runner container
[[runners]]
  executor = "docker"
  [runners.docker]
    network_mode = "host"
```
**CI variables**: Use `localhost` URLs since container shares host network:
```yaml
variables:
  OBS_API_URL: "http://localhost:4455"
```
**See**: `references/gitlab-runner-integration.md` for full details

### 26. Worker Port Mismatch After Restart

**Symptom**: Worker is idle, dispatch tries to assign job, but Worker never receives it. Foreground dispatch output shows `assignjob` but Worker state stays idle.

**Root cause**: When a Worker process is restarted, it binds to a new random HTTP port. However, the idle file (`/srv/obs/workers/idle/<arch>:<workerid>`) still records the OLD port from the previous Worker instance. Dispatch reads the idle file and tries to HTTP PUT `/build` to the old port, which fails silently (connection refused or timeout).

**Diagnosis**:
```bash
# Check Worker's actual listening port
docker exec obs-server-test bash -c 'netstat -tlnp | grep perl'
# Check idle file's recorded port
docker exec obs-server-test bash -c 'cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | grep -i port'
# If ports don't match, that's the problem
```

**Fix**: Restart the Worker so it re-registers and writes its new port to the idle file:
```bash
# Kill old Worker
docker exec obs-server-test bash -c 'kill $(pgrep -f "worker-2-aarch64")'
sleep 2
# Clear stale idle entry
docker exec obs-server-test rm -f /srv/obs/workers/idle/aarch64:worker-2-aarch64
# Restart Worker (it will register with new port)
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_worker \
  --root /var/cache/obs-worker/2 --statedir /var/run/obs/worker2 \
  --arch aarch64 --id worker-2-aarch64 \
  --srcserver http://localhost:5352 --reposerver http://localhost:5252 --nocodeupdate'
sleep 3
# Verify port match
docker exec obs-server-test bash -c 'cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | head -3'
```

**Prevention**: Always clear idle entries before restarting Workers: `rm -f /srv/obs/workers/idle/<arch>:<workerid>`

**See**: `references/worker-port-mismatch.md` for detailed debugging trace

### 27. libxcrypt-devel/libxcrypt-static Missing for glibc-devel

**Symptom**: Build marked `unresolvable` with `nothing provides libxcrypt-devel(aarch-64) >= 4.0.0 needed by glibc-devel, nothing provides libxcrypt-static(aarch-64) >= 4.0.0 needed by glibc-devel`

**Root cause**: `glibc-devel` (a dependency of gcc) requires `libxcrypt-devel >= 4.0.0` and `libxcrypt-static >= 4.0.0`. These packages may not be in the DoD `:full` directory.

**Fix**: Download the missing packages to `:full`:
```bash
REPO_URL="https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS/OS/aarch64/Packages"
docker exec obs-server-test bash -c "
  cd /srv/obs/build/<DoD-project>/standard/aarch64/:full/
  curl -sLO '${REPO_URL}/libxcrypt-devel-4.4.36-2.oe2403.aarch64.rpm'
  curl -sLO '${REPO_URL}/libxcrypt-static-4.4.36-2.oe2403.aarch64.rpm'
  chown obsrun:obsrun libxcrypt-*.rpm
"
# Restart scheduler to re-scan
```

**General lesson**: When adding `BuildRequires: gcc` to a spec, the full dependency chain is: gcc → glibc-devel → libxcrypt-devel + libxcrypt-static. Always check `rpm -qpR` recursively for all transitive dependencies.

### 34. New OBS Sub-Project Must Have _config Set

**Symptom**: OBS build in a newly created sub-project fails silently or produces unexpected errors (missing preinstall packages, wrong build type, chroot failures)

**Root cause**: OBS sub-projects created via `PUT /source/<project>/_meta` API have an empty `_config` by default. Without `Type: spec`, `Preinstall`, and `Order` directives, the scheduler cannot properly configure the build environment. This is especially critical for openEuler builds which need specific `Order:` directives to resolve filesystem/glibc conflicts.

**Fix**: Always set `_config` immediately after creating a new sub-project, using the same config as the working base project:
```bash
curl -s -u Admin:admin123 -X PUT --data-binary @- \
  "http://localhost:4455/source/home:Admin:NEW-PKG/_config" << 'EOF'
Type: spec
Required: rpm-build
Preinstall: rpm util-linux chkconfig
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
Order: filesystem:bash
Prefer: filesystem
ExpandFlags: preinstallexpand
EOF
```

**Automation tip**: When creating sub-projects programmatically (e.g., from webhook-server), always include `_config` setup as part of the project creation workflow.

### 35. OBS Source Tarball Must Include Name-Version Subdirectory

**Symptom**: OBS build fails in `%prep` phase with `cd: package-1.0.0: No such file or directory`

**Root cause**: RPM `%setup -q` macro extracts the tarball and then `cd` into `Name-Version/` directory. If the tarball was created with `tar -czvf pkg.tar.gz .` from inside the source directory, the content is flat (no subdirectory), and `%setup` cannot find the expected directory.

**Fix**: Create tarball with `Name-Version/` as the top-level directory:
```bash
# WRONG — flat content, %setup -q fails
cd hello-world && tar -czvf ../hello-world-1.0.0.tar.gz .

# CORRECT — includes Name-Version/ subdirectory
mkdir -p /tmp/hello-world-1.0.0
cp -r hello-world/* /tmp/hello-world-1.0.0/
cd /tmp && tar -czvf hello-world-1.0.0.tar.gz hello-world-1.0.0/
```

**Verify**: Always check tarball structure before uploading: `tar -tzf pkg.tar.gz | head -3`

### 38. OBS API /build/ Endpoint Returns 400 "unknown host" in Container

**Symptom**: `curl -u Admin:admin123 "http://localhost:4455/build/home:Admin/standard/x86_64/pkgname"` returns `<status code="400"><summary>unknown host 'container-hostname'</summary></status>` even though BSConfig.pm has `$hostname='localhost'`

**Root cause**: OBS Rails API generates internal redirect URLs using the container's system hostname (e.g., `nando-MS-7E56.mshome.net`), not the BSConfig.pm `$hostname`. When external clients call the `/build/` API, OBS tries to redirect/proxy to this hostname which is unresolvable outside the container. This affects both integration projects with `_link` packages and sub-projects.

**Impact**: sync-service's `list_build_binaries()` and `download_rpm()` fail with 400 errors. `sync-all` returns "No binaries found" for all packages.

**Workaround**: Sync from sub-projects directly instead of the integration project. Modify sync-service `sync-all` to:
1. Use `/source/{project}` API (not `/build/`) to get package list
2. Sync each package from its sub-project (`home:Admin:pkgname`) where builds are published

**Proper fix**: Configure OBS Rails API to use `localhost` as hostname:
- Set `OBS_API_HOSTNAME` or equivalent Rails config
- Or configure nginx reverse proxy to handle hostname resolution

### 39. Multi-Package CI/CD Setup Workflow

When adding a new package to the multi-package CI/CD pipeline, follow this checklist:

1. **Create OBS sub-project** with DoD path and `rebuild="local" block="local"`
2. **Set _config** (same as base project — see pitfall #34)
3. **Create OBS package** and upload source/spec
4. **Update integration project** — add new sub-project as `<path>`
5. **Create _link package** in integration project (use `-T` upload, NOT `--data-binary`)
6. **Create GitLab repo** and upload source files + CI template
7. **Set GitLab CI/CD variables** — `PACKAGE_NAME` and `PACKAGE_DIR` (must match OBS package name, NOT GitLab repo name)
8. **Enable Runner for new project** — `curl -X POST "http://localhost:8080/api/v4/projects/$ID/runners" -d '{"runner_id": $RUNNER_ID}'`
9. **Trigger Pipeline** and verify end-to-end

**Key**: Steps 1-5 are OBS-side setup. Steps 6-9 are GitLab-side setup. Both must be completed before the package can flow through the pipeline.

**See**: `references/multi-package-cicd-architecture.md` for full architecture design
**See**: `references/obs-api-hostname-issue.md` for detailed analysis of the /build/ API hostname problem

## Verified Success (2026-05-15)
- **Multi-package parallel CI/CD verified**: hello-world and demo-app pipelines run simultaneously with Runner concurrent=4
- Both packages build successfully in OBS (x86_64 + aarch64)
- Full 8-stage pipeline passes for both: build → obs-trigger → obs-wait → sync ×2 → quality-gate ×2 → update-repo
- CI template uses PACKAGE_NAME (per-project CI/CD variable) instead of CI_PROJECT_NAME for OBS project mapping
- Tarball includes PackageName-Version/ subdirectory for %setup -q compatibility

### 37. OBS API Source File Upload — Empty Content

**Symptom**: PUT request to update a spec file returns success (new revision), but GET shows empty file (0 bytes).

**Root cause**: Using `--data-binary @-` with heredoc input can fail silently when the heredoc contains special characters or when stdin is consumed by another operation. The API accepts the empty body as a valid update.

**Fix**: Write spec to a temporary file first, then upload with `--data-binary @/tmp/file.spec`:
```bash
cat > /tmp/hello-world.spec << 'EOF'
Name: hello-world
...
EOF
curl -s -u Admin:admin123 -X PUT \
  -H "Content-Type: text/plain" \
  --data-binary @/tmp/hello-world.spec \
  "http://localhost:4455/source/home:Admin/hello-world/hello-world.spec"
```

**Critical**: Always verify the upload by GETting the file back: `curl -s -u Admin:admin123 "http://localhost:4455/source/home:Admin/hello-world/hello-world.spec"`

### 29. Intewell-unified-packer Integration — OBS RPMs to ISO

**Goal**: Build an ISO image containing OBS-built RPMs using Intewell-unified-packer.

**Key architecture**: Packer runs `build_in_docker.sh` which launches a Docker container
(`--network host --privileged --platform linux/arm64`) that mounts `_internal/` → `/userdefos`.
Inside the container, `build.sh` extracts a base rootfs, installs packages via chroot+dnf,
then generates an ISO with genisoimage.

**Integration steps**:
1. Create a dnf repo from OBS-built RPMs: `createrepo /path/to/repo`
2. Serve via HTTP: `cd /path/to/repo && python3 -m http.server 8082`
3. Add obs.repo to `_internal/appset.d/` with `baseurl=http://localhost:8082/`
4. Create appset dir under `_internal/prebuild_cache/all_appsets/<arch>/<name>.app/`
5. Create JSON config in `_internal/system_cfg/` with applist containing the appset name
6. Run: `bash build_in_docker.sh <config.json>`

**Pitfall A: prebuild_cache must be inside _internal/** — The Docker container only
mounts `_internal/` to `/userdefos`. Appsets placed in the project-root `prebuild_cache/`
(outside `_internal/`) are invisible inside the container. The `cp -rf` step silently
skips missing directories, resulting in empty dnf install commands.
**Beware**: Some Packer distributions ship a duplicate `prebuild_cache/` at the project
root level alongside `_internal/prebuild_cache/`. These are independent directories
(different inodes), not symlinks. The outer one is never used by the build but wastes
disk space (5.1GB observed). Safe to delete after confirming `_internal/prebuild_cache/`
has all needed content.

**Pitfall B: HTTP server working directory** — `python3 -m http.server` serves files
relative to CWD. If started from the wrong directory, `repodata/repomd.xml` returns 404.
Always `cd` into the repo root before starting. Verify with:
`curl -s http://localhost:8082/repodata/repomd.xml | head -3`

**Pitfall C: runlist failure cascades to applist** — When `main.project` (runlist)
contains packages unavailable in the configured repos (e.g., `qt`, `firewall-config`),
dnf throws `PackagesNotAvailableError`. `install_rpmlist.sh` does NOT exit on failure,
but if the appset wasn't copied (pitfall A), the applist install gets an empty RPM list.
Fix: create a minimal runlist or remove it for testing.

**ISO output**: `_internal/out/package/<arch>/<board>/<kernel>-<defconfig>.iso`

**See**: `references/intewell-packer-integration.md` for full directory structure, appset format, JSON config format, and session history

**Pitfall D: Duplicate prebuild_cache directories** — Some Packer distributions ship both
`<project-root>/prebuild_cache/` and `_internal/prebuild_cache/`. These are independent
directories (different inodes, not symlinks). The outer one is NEVER used by the build
(TOPDIR = _internal, Docker mounts only _internal). It wastes disk space (5.1GB observed).
Safe to delete after confirming `_internal/prebuild_cache/` has all needed content.
**How to verify**: `ls -lid <project-root>/prebuild_cache _internal/prebuild_cache` —
if inodes differ, they're duplicates. `diff <(find outer -type f | sed ...) <(find inner -type f | sed ...)` to compare.

**Pitfall E: createrepo_c must be re-run after RPM sync** — When sync-service copies a
new RPM to the HTTP repo directory, the existing repodata does NOT include it. Must run
`createrepo_c /path/to/repo/` to regenerate repodata, then the HTTP server automatically
serves the updated metadata (no restart needed since it reads from filesystem).

### 30. glibc ABI Compatibility Between OBS Build Environment and Packer Rootfs

**Symptom**: RPM built in OBS runs fine in testing but segfaults or reports `version 'GLIBC_X.YZ' not found` when installed in the ISO rootfs.

**Root cause**: OBS DoD repository and Packer rootfs base image use different openEuler versions. If OBS builds against a newer glibc than what's in the rootfs, the compiled binary may reference ABI symbols that don't exist at runtime.

**Compatibility rule**: glibc is forward-compatible but NOT backward-compatible. A program compiled against glibc-X can run on glibc-Y where Y >= X, but NOT where Y < X.

**Current state (Intewell project)**:
- OBS DoD: openEuler 24.03 LTS SP3 → glibc-2.38-29.oe2403 (provides up to GLIBC_2.34)
- Packer rootfs: openEuler 24.03 LTS SP1 → glibc-2.38-47.oe2403sp1 (provides up to GLIBC_2.35)
- Currently compatible: SP3's GLIBC_2.34 <= SP1's GLIBC_2.35 ✅
- But fragile: if SP3 introduces GLIBC_2.38 symbols, programs will fail on SP1 rootfs

**Fix (recommended)**: Align OBS DoD repository version with Packer rootfs base version:
```xml
<!-- Change DoD download URL to match rootfs version -->
<download arch="aarch64" url="https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS-SP1/everything/aarch64/" repotype="rpmmd"/>
```

**Long-term**: Maintain a version lock matrix in project config:
```
BASE_VERSION = openEuler-24.03-LTS-SP1
OBS_DOD_URL  = corresponding SP1 repository URL
PACKER_ROOTFS = corresponding SP1 rootfs image
```
Any version upgrade must update ALL three simultaneously.

**How to diagnose**:
```bash
# Check RPM's required glibc symbols
rpm -qp --requires <rpm_file> | grep libc.so
# Or for a binary inside the RPM:
rpm2cpio <rpm_file> | cpio -idmv
readelf -V usr/bin/<binary> | grep GLIBC

# Check rootfs glibc's provided symbols
docker run --rm --platform linux/arm64 <rootfs_image> \
  bash -c "objdump -T /lib64/libc.so.6 | grep GLIBC_2 | awk '{print \$5}' | sort -V | uniq | tail -5"
```

**See**: `references/glibc-abi-compatibility.md` for detailed analysis

### 31. Multi-Package Multi-Developer CI/CD Architecture

**Goal**: Support multiple packages (e.g., ROS2 nav2, moveit) built by multiple developers in parallel, with automated end-to-end pipeline.

**Architecture**: OBS project isolation + GitLab multi-repo + CI template parameterization

```
Developer A push → GitLab repo: ros2-nav2 → CI → OBS project home:Admin:ros2-nav2
Developer B push → GitLab repo: ros2-moveit → CI → OBS project home:Admin:ros2-moveit
                                                    ↓
                                          OBS builds complete (per-project)
                                                    ↓
                                          sync-service sync-all (integration project)
                                                    ↓
                                          createrepo_c updates repodata
                                                    ↓
                                          Packer ISO build (on-demand or automated)
```

**Key design decisions**:

1. **OBS project isolation**: Each package gets its own OBS sub-project (e.g., `home:Admin:ros2-nav2`). An integration project (`home:Admin`) layer-links all sub-projects:
   ```xml
   <project name="home:Admin">
     <repository name="standard">
       <path project="home:Admin:openEuler24.03-SP1" repository="standard"/>
       <path project="home:Admin:ros2-nav2" repository="standard"/>
       <path project="home:Admin:ros2-moveit" repository="standard"/>
       <arch>aarch64</arch>
     </repository>
   </project>
   ```
   This gives each package independent build scheduling while the integration project merges all RPMs.

2. **GitLab CI template with automatic project mapping**: Use `CI_PROJECT_NAME` (GitLab built-in variable) to map repos to OBS projects automatically:
   ```yaml
   variables:
     OBS_PROJECT: "home:Admin:${CI_PROJECT_NAME}"
     OBS_PACKAGE: "${CI_PROJECT_NAME}"
     OBS_INTEGRATION_PROJECT: "home:Admin"
   ```
   Each repo uses the SAME `.gitlab-ci.yml` — no per-package customization needed.

3. **sync-all instead of per-package sync**: After OBS build, sync the entire integration project:
   ```yaml
   sync-aarch64:
     script:
       - 'curl -X POST $SYNC_URL/sync-all/$OBS_INTEGRATION_PROJECT/standard/aarch64'
       - 'curl -X POST $SYNC_URL/update-repo/aarch64'  # trigger createrepo
   ```

4. **ISO build trigger**: On-demand (manual/定时) for releases, or automated when all critical packages are synced.

**Parallel safety**: OBS sub-projects build independently. Different developers pushing different repos trigger different OBS builds with no contention. The integration project's layer-link automatically picks up new builds.

**See**: `references/multi-package-cicd-architecture.md` for full design

### 32. OBS Integration Project _link Package

**Purpose**: In OBS, `path` layer-linking only provides build dependencies — it does NOT automatically merge sub-project RPMs into the integration project's repository. To make sub-project RPMs appear in the integration project repo, create a `_link` package.

**Symptom**: Integration project `home:Admin` has `<path>` to `home:Admin:hello-world`, but `home:Admin/standard/aarch64/` repository is empty (no RPMs).

**Fix**: Create a `_link` package in the integration project pointing to the sub-project:
```bash
# 1. Create package meta in integration project
curl -s -u Admin:admin123 -X PUT -H "Content-Type: text/xml" \
  -d '<package name="hello-world"><title>Link to hello-world sub-project</title></package>' \
  "http://localhost:4455/source/home:Admin/hello-world/_meta"

# 2. Upload _link file (MUST use -T file upload, NOT --data-binary @- pipe)
echo '<link project="home:Admin:hello-world" package="hello-world"/>' > /tmp/_link
curl -s -u Admin:admin123 -X PUT -T /tmp/_link \
  "http://localhost:4455/source/home:Admin/hello-world/_link"
```

**Critical**: The `_link` file upload MUST use `-T /path/to/file` (file upload mode). Using `--data-binary @-` with pipe/heredoc causes 0-byte uploads (the file content is silently lost). This is the same issue as pitfall #28 (OBS API Source File Upload — Empty Content) but specifically affects `_link` files.

**Verify**: After upload, check `srcmd5` is NOT `d41d8cd98f00b204e9800998ecf8427e` (which indicates empty content):
```bash
curl -s -u Admin:admin123 "http://localhost:4455/source/home:Admin/hello-world" | grep srcmd5
# Expected: non-empty md5 hash, NOT d41d8cd98f00b204e9800998ecf8427e
```

**Result**: Integration project will build the linked package for all configured architectures. The RPMs will appear in the integration project's repository.

### 33. GitLab CI Template — Common YAML and Configuration Pitfalls

**Context**: When building a 5-stage CI pipeline (build → obs-trigger → obs-wait → sync → update-repo) for OBS integration.

#### Pitfall A: artifacts paths don't expand variables
```yaml
# ❌ GitLab CI does NOT expand variables in artifacts paths
artifacts:
  paths:
    - "${PACKAGE_NAME}-1.0.0.tar.gz"

# ✅ Use wildcards instead
artifacts:
  paths:
    - "*.tar.gz"
```

#### Pitfall B: CI_PROJECT_NAME ≠ package name
GitLab's `CI_PROJECT_NAME` is the repository project name (e.g., `intewell-test`), which may differ from the OBS package name (e.g., `hello-world`). Use `PACKAGE_NAME` and `PACKAGE_DIR` variables to override:
```yaml
variables:
  PACKAGE_NAME: "hello-world"   # OBS project name and spec file name
  PACKAGE_DIR: "hello-world"    # Source directory name in repo
```

#### Pitfall C: GitLab Runner tag matching issues
After adding a tag (e.g., `test`) to a Runner via API, Pipelines may fail immediately with no jobs created. The Runner's tag list may appear inconsistent between the global API and project-level API.
**Fix options**:
1. Restart the Runner container: `docker restart gitlab-runner`
2. Remove tags from both CI template and Runner (use untagged matching)
3. Ensure tags are identical in CI template `tags:` and Runner `tag_list`

#### Pitfall D: Docker service containers need rebuild for code changes
Services like sync-service have code baked into the Docker image (not volume-mounted). After modifying `app.py`, you must:
1. Rebuild: `docker build -t sync-service:latest .`
2. Stop and remove: `docker stop sync-service && docker rm sync-service`
3. Re-launch with new image
`docker restart` alone does NOT load new code.

### 34. OBS API `/build/` Endpoint Returns 400 "unknown host" — Fix with /etc/hosts

**Symptom**: `curl -u Admin:admin123 "http://localhost:4455/build/{project}/{repo}/{arch}/{package}"` returns `<status code="400"><summary>unknown host 'container-hostname'</summary></status>` even though BSConfig.pm has `$hostname='localhost'`

**Root cause**: OBS Rails API (Ruby process on port 4455) generates internal redirect URLs using the container's system hostname (e.g., `nando-MS-7E56.mshome.net`), not the BSConfig.pm `$hostname`. When external clients call the `/build/` or `/published/` API, OBS tries to proxy to this hostname which is unresolvable outside the container.

**Impact**: sync-service's `list_build_binaries()` and `download_rpm()` fail with 400 errors. `sync-all` returns "No binaries found" for all packages.

**Fix**: Add container hostname to `/etc/hosts` inside OBS container AND restart the Rails API process:
```bash
# 1. Add hostname to /etc/hosts (resolves internal URL generation)
docker exec obs-server-test bash -c 'echo "127.0.0.1 $(hostname)" >> /etc/hosts'

# 2. Restart Rails API (it caches hostname on startup)
docker exec obs-server-test bash -c 'pkill -f "rails server"'
docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0 -d'
sleep 10
# Verify: curl -u Admin:admin123 "http://localhost:4455/build/home:Admin:hello-world/standard/x86_64/hello-world"
```

**Persistence**: The `/etc/hosts` entry is lost on container restart. Make it persistent by:
1. Adding `--add-host` to `docker run`: `docker run --add-host $(hostname):127.0.0.1 ...`
2. Or modifying `/start-obs.sh` to add the entry on startup: `echo "127.0.0.1 $(hostname)" >> /etc/hosts`

**Workaround** (if fix unavailable): Sync from sub-projects directly instead of integration project. Modify sync-service `sync-all` to use `/source/{project}` API to get package list, then sync each package from its sub-project (`home:Admin:pkgname`).

### 35. OBS Container Restart Loses /etc/hosts and Backend Services

**Symptom**: After `docker restart obs-server-test`, the OBS API returns "unknown host" again and backend services (bs_repserver, bs_sched, bs_dispatch, bs_worker) are not running.

**Root cause**: Docker container restarts reset `/etc/hosts` to default. OBS start script (`/start-obs.sh`) may not start all backend services (only bs_srcserver starts reliably).

**Fix — Persistent hostname**: Modify `/start-obs.sh` inside the container to add the hostname fix on startup:
```bash
# Add after "set -e" in /start-obs.sh:
echo "127.0.0.1 $(hostname)" >> /etc/hosts
echo "   Hostname fix applied: $(hostname) -> 127.0.0.1"
```

**Fix — All backend services**: Also modify `/start-obs.sh` to start dual-architecture schedulers and workers with `--nocodeupdate`:
```bash
# Scheduler for both architectures
perl ${OBS_DIR}/bs_sched x86_64 --daemonize || true
perl ${OBS_DIR}/bs_sched aarch64 --daemonize || true

# Worker 1: x86_64
perl ${OBS_DIR}/bs_worker --root /var/cache/obs-worker/1 --statedir /var/run/obs/worker1 \
  --arch x86_64 --id worker-1-x86_64 \
  --srcserver http://localhost:5352 --reposerver http://localhost:5252 --nocodeupdate &

# Worker 2: aarch64 (cross-build via qemu)
perl ${OBS_DIR}/bs_worker --root /var/cache/obs-worker/2 --statedir /var/run/obs/worker2 \
  --arch aarch64 --id worker-2-aarch64 \
  --srcserver http://localhost:5352 --reposerver http://localhost:5252 --nocodeupdate &
```

**Fix — Persist start-obs.sh changes via docker commit**: Changes to `/start-obs.sh` inside a container are lost on `docker rm` + `docker run`. Use `docker commit` to persist them:
```bash
# 1. Copy modified start-obs.sh into container
docker cp /tmp/start-obs.sh obs-server-test:/start-obs.sh

# 2. Commit the container as a new image
docker commit obs-server-test obs-server:latest

# 3. Recreate container with committed image (preserves start-obs.sh changes)
docker stop obs-server-test && docker rm obs-server-test
docker run -d --name obs-server-test --privileged --network host \
  -v /usr/bin/qemu-aarch64-static:/usr/bin/qemu-aarch64-static \
  -v /home/nando/AICICD/data/obs-srv/obs:/srv/obs \
  -v /home/nando/AICICD/data/obs:/var/obs \
  obs-server:latest
```

**Key**: The committed image preserves the CMD (`/start-obs.sh`), hostname fix, and all modifications. Container restart (`docker restart`) re-executes CMD, so all services auto-start. This makes OBS fully automated after restart — no manual service startup needed.

### 36. OBS start-obs.sh Blocks on bs_srcserver Output

**Symptom**: Container starts but only `bs_srcserver` is running; `bs_repserver`, `bs_sched`, `bs_dispatch`, `bs_worker`, and Rails API never start. Container logs show `bs_srcserver` output (GET requests) repeating indefinitely.

**Root cause**: `perl bs_srcserver --port 5352 --daemonize` does NOT truly daemonize in all OBS versions. It keeps writing HTTP request logs to stdout, which blocks the shell script from proceeding to the next command. Even with `--daemonize`, the process holds the script's stdout pipe open.

**Fix**: Redirect all OBS backend service output to log files and background with `& disown`:
```bash
# In /start-obs.sh, replace:
perl ${OBS_DIR}/bs_srcserver --port 5352 --daemonize || true

# With:
perl ${OBS_DIR}/bs_srcserver --port 5352 --daemonize > /var/log/obs/bs_srcserver.log 2>&1 &
disown
```

Apply the same pattern to ALL perl backend commands (bs_repserver, bs_sched, bs_dispatch, bs_worker). Also disable `set -e` at the top of the script to prevent early exit on non-zero returns:
```bash
# set -e  # Disabled: allow individual services to fail
```

**Critical**: The `&` puts the process in background, `disown` removes it from the shell's job table so the script can proceed. Without BOTH, the script blocks. Just `--daemonize` alone is NOT sufficient — it keeps stdout open.

**After modifying**: `docker commit obs-server-test obs-server:latest` to persist changes, then recreate container with committed image.

**Diagnosis**: If only 2 processes show up (`ps aux | grep bs_`), the script is blocked on the first service.

**Alternative — docker run flag**: Use `--add-host` to persist the hostname fix:
```bash
docker run --add-host $(hostname):127.0.0.1 ...
```

**Manual recovery** (if start-obs.sh not modified):
```bash
# Add hostname fix
docker exec obs-server-test bash -c 'echo "127.0.0.1 $(hostname)" >> /etc/hosts'
# Start all OBS backend services
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_repserver --daemonize'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_sched x86_64'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_sched aarch64'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_dispatch'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_worker --root /var/cache/obs-worker/1 --statedir /var/run/obs/worker1 --arch x86_64 --id worker-1-x86_64 --srcserver http://localhost:5352 --reposerver http://localhost:5252 --nocodeupdate'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_worker --root /var/cache/obs-worker/2 --statedir /var/run/obs/worker2 --arch aarch64 --id worker-2-aarch64 --srcserver http://localhost:5352 --reposerver http://localhost:5252 --nocodeupdate'
# Restart Rails API
docker exec obs-server-test bash -c 'pkill -f "rails server"'
docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0 -d'
```

1. Check service status: `ps aux | grep bs_`
2. Check worker state: `cat /var/run/obs/worker1/state`
3. Check dispatcher log: Look for `/tmp/dispatch.log` or stdout
4. Check badhost errors: `cat /srv/obs/jobs/x86_64/.logfile.badhost/*`
5. Check build log via API: `curl -u Admin:admin http://<host>:4455/build/<project>/<repo>/<arch>/<package>/_log`

## Useful Commands

```bash
# Restart all OBS services in container
docker exec obs-server-test bash -c 'pkill -f bs_; redis-server --daemonize yes'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_srcserver --port 5352 --daemonize'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_repserver --daemonize'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_sched x86_64'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_dispatch'

# Trigger rebuild
curl -u Admin:admin -X POST -H "Content-Length: 0" \\
  "http://<host>:4455/build/<project>?cmd=rebuild&package=<package>"

# Check build status
curl -u Admin:admin "http://<host>:4455/build/<project>/_result"

# Update project config (openEuler template)
curl -u Admin:admin -X PUT -d "Type: spec
Required: rpm-build
Preinstall: rpm util-linux chkconfig
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
Order: filesystem:bash
Prefer: filesystem
ExpandFlags: preinstallexpand
" "http://<host>:4455/source/<project>/_config"

# Or use the template file:
# curl -u Admin:admin -X PUT --data-binary @templates/openeuler-project-config.conf \
#   "http://<host>:4455/source/<project>/_config"

# Clear worker cache
docker exec <container> bash -c 'rm -rf /var/cache/obs-worker/1/*'
```

## References
- `references/container-worker-debug.md` - Detailed session troubleshooting log (Worker startup, badhost)
- `references/preinstall-order-debug.md` - Preinstall order conflicts and Order directive usage
- `references/chroot-preinstall-debug.md` - Complete debugging session: 29 issues resolved for openEuler builds
- `references/openeuler-final-config.md` - Final working project configuration for openEuler 24.03 (verified 2026-05-13)
- `references/gitlab-runner-integration.md` - GitLab Runner network config, CI variables, pipeline automation (2026-05-13)
- `references/aarch64-worker-setup.md` - Cross-architecture builds with qemu-user-static, architecture database config (2026-05-14)
- `references/project-storage-format.md` - OBS backend project storage format ($projid.xml vs subdirectory), API/backend sync (2026-05-14)
- `references/api-authentication-debug.md` - OBS API password authentication, deprecated_password fix, project validation errors (2026-05-14)
- `references/scheduler-excluded-analysis.md` - Scheduler "excluded" status root cause analysis, source code trace through Checker.pm/PBuild/Recipe.pm, empty solv pool diagnosis (2026-05-14)
- `references/dod-deep-debug.md` - DoD deep debugging: permission mismatches, URL version conflicts, doddata regeneration, "downloading N dod packages" status, manual RPM download workaround, data flow deep dive (2026-05-14)
- `references/dod-placeholder-mechanism.md` - DoD d0d0d0d0 placeholder mechanism: why :full RPMs are ignored when doddata exists, readparsed() source code trace, isexternal() solv short-circuit, fix by removing doddata, python-setuptools vs python-setuptools-wheel distinction (2026-05-14)
- `references/aarch64-cross-build-debugging.md` - aarch64 cross-arch build debugging chain: DoD placeholder → unresolvable deps → Worker build script missing → binfmt_misc mount → Worker idle (--srcserver), openEuler LTS vs SP3 package version matrix (2026-05-14)
- `references/dispatch-worker-assignment-debug.md` - Dispatch→Worker job assignment flow: badhost clearing, code check mechanism, three root causes for idle worker, source code trace of assignjob()/startbuild() (2026-05-14)
- `references/aarch64-build-debugging.md` - aarch64 build debugging chain: BUILD_ROOT ownership, Worker port mismatch after restart, gcc missing in chroot, DoD :full missing gcc deps (gmp/isl/libxcrypt-devel/libxcrypt-static), openEuler 24.03 LTS package version matrix (2026-05-14)
- `references/worker-port-mismatch.md` - Worker port mismatch after restart: idle file records old port, dispatch connects to stale port, fix by clearing idle entry before restart (2026-05-14)
- `references/intewell-packer-integration.md` - Intewell-unified-packer integration: Packer architecture, appset format, OBS repo setup, build configuration JSON, ISO generation flow, prebuild_cache mount visibility, HTTP server CWD gotcha, runlist failure cascade (2026-05-14, updated)
- `references/gitlab-ci-obs-integration.md` - GitLab CI+OBS integration: 5-stage pipeline template, PACKAGE_NAME/PACKAGE_DIR variables, artifacts wildcard, Runner tag matching, _link package upload, sync-service new endpoints, Docker rebuild workflow

## Related Skills
- `cicd-pipeline-services` - CI/CD pipeline microservices (sync, quality-gate, cve-scanner)
- `gitlab-runner-docker` - GitLab Runner Docker executor deployment and troubleshooting
- `gitlab-ci-yaml-upload` - GitLab CI YAML upload via API with base64 encoding
- `intewell-packer` - Intewell OS ISO image build with OBS RPM integration

## Templates
- `templates/openeuler-project-config.conf` - Working project configuration for openEuler 24.03 builds

### 41. OBS _meta XML Requires <description> Element After <title>

**Symptom**: Creating OBS sub-project via `PUT /source/<project>/_meta` returns 500 Internal Server Error

**Root cause**: OBS validates project _meta XML strictly. After `<title>`, a `<description>` element is mandatory. Without it, OBS returns a validation error that manifests as 500 Internal Server Error (not a clear validation message).

**Fix**: Always include `<description>` in _meta XML:
```xml
<project name="home:Admin:pkgname">
  <title>pkgname package build</title>
  <description>pkgname package build for Intewell CI/CD</description>
  <repository name="standard">
    <path project="home:Admin:openEuler24.03-SP1" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>
```

**Note**: This is especially important when creating sub-projects programmatically (e.g., from webhook-server auto-onboard logic). The 500 error is misleading — it looks like an OBS server crash but is actually a validation failure.

**User correction**: When the user says "我们之前设计架构你阅读一下呢" or "之前设计过", STOP and read the existing architecture documents before proposing new solutions. The project has extensive design docs in `docs/architecture/` that capture earlier decisions, including webhook-server design, dual-mode architecture, and integration plans. Re-reading these avoids re-inventing solutions and missing already-deployed components.

**Specific example**: The webhook-server (`01-source-trigger/webhook-server/`) was already designed, deployed, and running on port 8091, but the agent proposed creating new webhook infrastructure because it didn't check existing code first.

**Checklist before proposing new components**:
1. Read `docs/architecture/` for existing designs
2. Check `01-source-trigger/`, `03-sync-quality-gate/`, `packer-integration/` for existing services
3. Check `docker ps` for running services
4. Check GitLab project webhooks: `curl -s --header "PRIVATE-TOKEN: $TOKEN" "http://localhost:8080/api/v4/projects/$ID/hooks"`

### 47. GitLab Webhook URL Must Use IP Address, Not localhost

**Symptom**: GitLab webhook created with `localhost` URL but push events never trigger webhook-server. Events list is empty `[]`.

**Root cause**: GitLab's internal webhook trigger mechanism doesn't work with `localhost` URLs even with `allow_local_requests_from_hooks_and_services=true`.

**Fix**: Use actual IP address:
```bash
IP=$(hostname -I | awk '{print $1}')
curl -X POST "http://localhost:8080/api/v4/projects/$ID/hooks" \
  --form "url=http://${IP}:8091/gitlab/push" --form "push_events=true"
```

**See**: `cicd-pipeline-services` skill pitfall #50 for full details.

## Verified Success (2026-05-13)
- hello-world-1.0.0-2.1.x86_64.rpm built successfully in openEuler OBS 2.10.15 container
- hello-world-1.0.0-2.1.src.rpm source package generated
- All 29 issues documented in `references/chroot-preinstall-debug.md` resolved

## Verified Success (2026-05-14)
- OBS project storage format discovered: `$projectsdir/$projid.xml` (not subdirectory)
- loongarch64 architecture added to database for future support
- Rails cache clearing required after architecture database changes
- BSConfig.pm hostname override for container environments
- hello-world package uploaded via osc CLI to home:Admin project
- OBS API authentication fixed: deprecated_password fields must be cleared for bcrypt to work
- OBS data directories migrated to `/home/nando/AICICD/data/` for persistence and disk space management
- Project validation: avoid empty `<build><enable/></build>` elements
- **Intewell-unified-packer ISO build verified**: hello-world-1.0.0-3.1.aarch64.rpm installed
  into S5000C aarch64 ISO via OBS repo → dnf install → genisoimage pipeline.
  ISO at `_internal/out/package/aarch64/S5000C/6.12.y-intewell-S5000C-rt_defconfig.iso` (1.2GB).
  Verified `./usr/bin/hello-world` in ROOTFS.TGZ via `isoinfo -x "/DATA/ROOTFS.TGZ;1" | tar tzf`.