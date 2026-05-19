# DoD (Download on Demand) Deep Debugging Session

**Date**: 2026-05-14
**Context**: aarch64 hello-world build stuck at "blocked" / "downloading N dod packages"

## Problem Chain

### 1. DoD :full Directory Permission Mismatch
**Symptom**: bs_dodup silently fails to write doddata/doddata.cookie to :full directory
**Root cause**: Manually downloaded RPMs (via curl from host) are owned by `nando:nando`, but bs_dodup runs as `obsrun:obsrun`
**Fix**:
```bash
docker exec obs-server-test chown -R obsrun:obsrun /srv/obs/build/home:Admin:openEuler24.03/standard/aarch64/:full/
```
**Lesson**: ALWAYS chown :full directory to obsrun after manually placing RPMs

### 2. DoD URL vs RPM Version Mismatch
**Symptom**: doddata generated but Scheduler still reports "downloading N dod packages" indefinitely
**Root cause**: DoD project XML pointed to `openEuler-24.03-LTS-SP3` but manually downloaded RPMs were from `openEuler-24.03-LTS` (different version suffix: oe2403sp3 vs oe2403)
**Fix**: Update DoD project XML to match the actual RPM source:
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

### 3. doddata Regeneration Workflow
When doddata gets out of sync with :full directory contents:
1. Delete doddata and cookie: `rm -f :full/doddata :full/doddata.cookie`
2. Delete all Scheduler caches: `rm -f :packstatus :schedulerstate :full.solv`
3. Run bs_dodup manually: `./bs_dodup --dodfile /srv/obs/dods/<dodfile>`
4. Restart Scheduler: `pkill -f bs_sched; ./bs_sched aarch64`

**Key**: bs_dodup generates doddata by fetching repomd.xml from the remote URL, NOT by scanning :full directory. So doddata reflects what's available remotely, not what's already downloaded locally.

### 4. "downloading N dod packages" Status
**Meaning**: Scheduler has resolved dependencies but N packages are not yet in :full directory. It sends download requests to repserver which forwards to bs_dodup.

**Progress tracking**: The number decreases as bs_dodup downloads packages. In our session: 58 → 51 → 2 (over ~10 minutes).

**If stuck at small number**: The remaining packages may not exist in the remote repo, or the download is failing silently. Check:
- `ls -lt /srv/obs/build/<DoD-project>/standard/<arch>/:full/` — see if new files are appearing
- `cat /srv/obs/build/<main-project>/standard/<arch>/:packstatus` — check packerror message
- Run bs_dodup with `--dodfile` to force a recheck

### 5. DoD Data Flow (Deep Dive)
```
1. bs_dodup fetches repomd.xml from remote URL
2. bs_dodup parses primary.xml → generates doddata (binary metadata cache, ~17MB for full repo)
3. bs_dodup writes doddata + doddata.cookie to :full/
4. bs_dodup sends scanrepo event to Scheduler
5. Scheduler reads doddata via BSSched::DoD::put_doddata_in_cache()
6. Scheduler generates :full.solv for DoD project (~5MB)
7. Scheduler merges DoD project solv into main project dependency pool
8. Scheduler resolves BuildRequire dependencies
9. If packages missing from :full, Scheduler reports "downloading N dod packages"
10. Scheduler calls dodfetch() → sends request to repserver
11. Repserver triggers bs_dodup to download actual RPM files
12. Downloaded RPMs placed in :full/ as name.arch.rpm (e.g., gcc.aarch64.rpm → gcc.rpm)
13. Scheduler re-scans :full, generates main project :full.solv
14. Build can proceed once all dependencies resolved
```

### 6. Manual RPM Download as Workaround
When bs_dodup can't download all packages automatically:

```bash
# Step 1: Identify missing packages from packstatus
cat /srv/obs/build/<main-project>/standard/<arch>/:packstatus | strings

# Step 2: Search for package versions in remote repo
curl -sL "https://repo.openeuler.org/openEuler-24.03-LTS/everything/aarch64/Packages/" | \
  grep -oP 'href="gcc-[^"]*"' | head -3

# Step 3: Download in parallel using xargs + curl (wget may fail)
# Create download list
cat > /tmp/wget_list.txt << 'EOF'
https://repo.openeuler.org/openEuler-24.03-LTS/everything/aarch64/Packages/gcc-12.3.1-105.oe2403.aarch64.rpm
https://repo.openeuler.org/openEuler-24.03-LTS/everything/aarch64/Packages/rpm-build-4.18.2-6.oe2403.aarch64.rpm
EOF

# Download with parallelism
cat /tmp/wget_list.txt | xargs -P 8 -I {} curl -sL -o /tmp/rpms/{}  {}

# Step 4: Copy to :full with OBS naming convention (name.rpm)
for f in /tmp/rpms/*.rpm; do
  name=$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null || echo "")
  [ -n "$name" ] && cp "$f" ":full_dir/$name.rpm"
done

# Step 5: Fix permissions!
chown -R obsrun:obsrun :full_dir/

# Step 6: Clear caches and restart
rm -f :packstatus :schedulerstate :full.solv
pkill -f bs_sched; ./bs_sched aarch64
```

### 7. Key File Locations
- DoD project dods file: `/srv/obs/dods/<project>::<repo>::<arch>`
- DoD doddata: `/srv/obs/build/<project>/<repo>/<arch>/:full/doddata`
- DoD doddata.cookie: `/srv/obs/build/<project>/<repo>/<arch>/:full/doddata.cookie`
- DoD solv: `/srv/obs/build/<project>/<repo>/<arch>/:full.solv`
- Main project solv: `/srv/obs/build/<project>/<repo>/<arch>/:full.solv`
- Scheduler state: `/srv/obs/build/<project>/<repo>/<arch>/:schedulerstate`
- Pack status: `/srv/obs/build/<project>/<repo>/<arch>/:packstatus`

### 8. RPM Naming in :full Directory
OBS uses simplified naming in :full: `name.rpm` (e.g., `gcc.rpm`, `rpm-build.rpm`).
The actual version/arch info is stored in doddata metadata, not in the filename.
When manually placing RPMs, rename to `name.rpm` format where name = RPM %{NAME} tag.

### 9. bs_dodup Command Reference
```bash
# Run as daemon (normal operation)
./bs_dodup

# Test with specific dod file
./bs_dodup --dodfile /srv/obs/dods/<dodfile>

# Test with unparsed dod file (skip metadata parsing)
./bs_dodup --dodfile /srv/obs/dods/<dodfile> --unparsed

# Stop daemon
./bs_dodup --stop
```

### 10. Scheduler Restart Sequence for DoD Changes
After any DoD configuration change (URL, project meta, doddata):
1. Clear all caches: packstatus, schedulerstate, full.solv (both DoD and main project)
2. Restart bs_dodup: `pkill -f bs_dodup; ./bs_dodup`
3. Wait for doddata to regenerate (check file size)
4. Restart schedulers: `pkill -f bs_sched; ./bs_sched x86_64; ./bs_sched aarch64`
5. Wait 30-60 seconds for dependency resolution
6. Check packstatus for progress
