# DoD d0d0d0d0 Placeholder Mechanism — Deep Dive

**Date**: 2026-05-14
**Context**: aarch64 build stuck at "downloading 2 dod packages" even though :full directory contains all needed RPMs

## Root Cause: readparsed() Forces Placeholder hdrmd5

In `BSSched/DoD.pm`, the `readparsed()` function (line 42-62) does this:

```perl
sub readparsed {
  my ($datafile) = @_;
  my $cookie = gencookie($datafile);
  return "doddata: $!" unless $cookie;
  my $data = BSUtil::retrieve($datafile, 2);
  return 'could not retrieve pre-parsed metadata' unless $data;
  my $baseurl = delete $data->{'/url'};
  return 'baseurl missing in data' unless $baseurl;
  for (values %$data) {
    $_->{'id'} = 'dod';
    $_->{'hdrmd5'} = 'd0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0';  # <-- THE PROBLEM
  }
  $data->{'/url'} = $baseurl;
  $data->{'/dodcookie'} = $cookie;
  return $data;
}
```

**Every DoD package gets `hdrmd5 = d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0`**, regardless of whether the actual RPM file exists in :full.

## How Scheduler Uses This (dodcheck)

In `BSSched/DoD.pm` dodcheck() (line 155-170):

```perl
# Line 163: Check if pkgid is the DoD placeholder
if (($pool->pkg2pkgid($p) || '') eq 'd0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0') {
  # Package needs to be downloaded
  $doddownloads->{$prpam}{$bin} = 1;
}
```

Scheduler checks each package's pkgid. If it's the placeholder, it marks the package as needing download via dodfetch.

## The addrepo_scan Flow (BSSched/BuildRepo.pm line 928+)

1. If `:full.solv` exists and is NOT external → load from file (fast path)
2. Call `put_doddata_in_cache()` → injects doddata with placeholder hdrmd5 into solv
3. Scan `:full/` directory for actual RPM files
4. Call `$repo->updatefrombins()` → should update pkgid from actual RPM headers
5. If dirty, write new `:full.solv`

**The key insight**: `updatefrombins()` SHOULD replace placeholder pkgids with real ones from actual RPM files. But if the doddata was just injected and the solv is marked as "external" (from doddata), step 1 short-circuits and returns immediately without scanning :full.

## The "external" solv Short-Circuit

In `addrepo_scan()` (line 957-961):

```perl
if (-s "$dir.solv") {
  eval {$r = $pool->repofromfile($prp, "$dir.solv");};
  warn($@) if $@;
  if ($r && $r->isexternal()) {
    $repocache->setcache($prp, $arch) if $repocache;
    return $r;  # <-- RETURNS EARLY, never scans :full directory
  }
}
```

If the existing `:full.solv` was generated from doddata (which makes it "external"), the Scheduler skips the :full directory scan entirely. This means manually placed RPMs in :full are NEVER indexed, and their pkgids remain as placeholders.

## Solution: Delete doddata to Force Local-Only Resolution

When doddata exists, it poisons the solv with placeholder pkgids. The fix is to remove doddata entirely so the Scheduler builds solv purely from :full directory RPMs:

```bash
# 1. Kill bs_dodup (otherwise it regenerates doddata)
pkill -9 -f bs_dodup

# 2. Kill scheduler
pkill -f "bs_sched aarch64"

# 3. Delete doddata and all caches
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
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && ./bs_sched aarch64'
```

**Result**: Without doddata, `addrepo_scan()` falls through to `repofrombins()` which scans :full directory RPMs directly. The solv is built from real RPM headers with real pkgids. The solv file shrinks from ~5MB (18606 packages from doddata) to ~50KB (only packages actually in :full).

## Trade-off: doddata Removal Exposes Missing Dependencies

Without doddata, the Scheduler can only resolve dependencies against packages physically present in :full. If a transitive dependency is missing, the build fails with a clear "unresolvable" error instead of the vague "downloading N dod packages" status.

**Example**: After removing doddata, the error changed from:
```
downloading 2 dod packages
```
to:
```
nothing provides python-pip-wheel needed by python3
nothing provides python-setuptools-wheel needed by python3
```

This is actually BETTER — it tells you exactly what's missing.

## Key Lesson: python-setuptools vs python-setuptools-wheel

In openEuler, `python3` Requires:
- `python-pip-wheel` (a noarch package containing pip wheel for bootstrapping)
- `python-setuptools-wheel` (a noarch package containing setuptools wheel for bootstrapping)

These are DIFFERENT from `python-pip` and `python-setuptools`. The `-wheel` variants are noarch packages that contain the pip/setuptools wheel archives used during Python virtual environment creation. You must download BOTH the regular and -wheel variants.

## Alternative: dnf --downloadonly for Complete Dependency Resolution

Instead of manually downloading RPMs one by one, use dnf to resolve the full dependency tree:

```bash
# On the host (or in a container with the same repo configured):
mkdir -p /tmp/rpm-deps
dnf install --downloadonly --downloaddir=/tmp/rpm-deps rpm-build
# This downloads rpm-build AND all its transitive dependencies

# Copy to :full with OBS naming
for f in /tmp/rpm-deps/*.rpm; do
  name=$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)
  [ -n "$name" ] && cp "$f" ":full_dir/$name.rpm"
done
chown -R obsrun:obsrun :full_dir/
```

## Source Code Reference Locations

| File | Lines | Function | Purpose |
|------|-------|----------|---------|
| BSSched/DoD.pm | 42-62 | readparsed() | Loads doddata, forces placeholder hdrmd5 |
| BSSched/DoD.pm | 155-170 | dodcheck() | Checks pkgid == d0d0d0d0... to decide if download needed |
| BSSched/DoD.pm | 200-240 | dodfetch() | Sends binaryversions request to repserver |
| BSSched/DoD.pm | 65-100 | put_doddata_in_cache() | Injects doddata into solv cache |
| BSSched/DoD.pm | 105-140 | clean_obsolete_dodpackages() | Removes RPMs not in doddata |
| BSSched/BuildRepo.pm | 928-1000 | addrepo_scan() | Main entry: loads solv or scans :full |
| BSSched/BuildRepo.pm | 957-961 | isexternal() check | Short-circuit if solv from doddata |
| BSRepServer.pm | 25-60 | addrepo_scan() | Repserver's version of :full scanning |
| bs_repserver | 455, 859, 1449 | pkgid checks | Repserver also checks d0d0d0d0... |
