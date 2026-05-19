# OBS Scheduler "excluded" Status — Root Cause Analysis

## Symptom
Package shows `excluded` in `:packstatus` but spec file has no `ExcludeArch`/`ExclusiveArch`.

## Source Code Trace (OBS 2.10)

### Decision Chain
1. **BSSched/Checker.pm ~line 844**: Sets package to `excluded` when `$info->{'error'} eq 'excluded'`
2. **PBuild/Recipe.pm ~line 110**: Sets `$p->{'error'} = 'excluded'` when `$d->{'exclarch'}` is defined and current arch is NOT in the list
3. **PBuild/Recipe.pm ~line 165**: Same check for `disarch` (disabled architectures)
4. **Build/Rpm.pm**: Parses spec file's `ExcludeArch:` and `ExclusiveArch:` tags into `exclarch`/`disarch`

### Other "excluded" Causes
- **`$ctx->{'onlybuild'}`**: If prjconf defines `Only:` whitelist, packages not in the list are excluded
- **`$pdata->{'error'} eq 'excluded'`**: Stale error from previous Scheduler cycle (persists in `:packstatus`)
- **Project link excluded**: Package from linked project but `linkedbuild` not configured

### Most Common Root Cause (Non-obvious)
**Empty dependency pool** — If the main project's `:full.solv` is empty (120 bytes), the Scheduler cannot resolve `BuildRequire` dependencies. The Build module then marks the package as having an unresolvable error, which gets surfaced as `excluded`.

This happens when:
- DoD project has solv data but Scheduler failed to merge it into the main project's pool
- No `<path>` element pointing to a base distro project
- The `<path>` project has no `:full.solv` yet (DoD data not downloaded)

### Diagnostic Commands
```bash
# Check packstatus
cat /srv/obs/build/<project>/standard/<arch>/:packstatus

# Check solv file sizes (120 bytes = empty, ~5MB = populated)
ls -la /srv/obs/build/<project>/standard/<arch>/:full.solv
ls -la /srv/obs/build/<DoD-project>/standard/<arch>/:full.solv

# Check DoD data exists
ls -la /srv/obs/build/<DoD-project>/standard/<arch>/:full/doddata

# Force Scheduler rescan
rm -f /srv/obs/build/<project>/standard/<arch>/:schedulerstate
pkill -f "bs_sched <arch>"
# Restart scheduler

# Run Scheduler in foreground for debug output
timeout 20 perl -w /usr/lib/obs/server/bs_sched <arch> 2>&1
# Look for: "excluded: N" in output
```

### Fix Sequence
1. Verify DoD project has `:full.solv` > 120 bytes
2. Verify main project `_config` has correct `Type:` / `Preinstall:` / `Required:`
3. Delete `:schedulerstate` and `:packstatus` to clear stale errors
4. Restart Scheduler
5. If still excluded, check if `Only:` is set in prjconf
6. If still excluded, the solv merge may be failing — restart repserver + scheduler together
