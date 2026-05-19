# OBS Preinstall Order Debug Session

**Date**: 2026-05-13
**Container**: obs-server-test
**Issue**: chroot environment initialization failures

## Problem Chain

### Issue 1: chroot rpm Not Found
- **Symptom**: `chroot: failed to run command 'rpm': No such file or directory`
- **Investigation**:
  - Checked `/var/cache/obs-worker/1/usr/bin/rpm` - exists
  - Ran `chroot /var/cache/obs-worker/1 /usr/bin/rpmdb --version` - failed
  - Ran `ldd /var/cache/obs-worker/1/usr/bin/rpmdb` - all libs found
- **Root cause**: Dynamic linker `/lib64/ld-linux-x86-64.so.2` missing in chroot
- **Fix attempt**: Add `glibc` to Preinstall

### Issue 2: rpm Shared Libraries Missing
- **Symptom**: `/usr/bin/rpmdb: error while loading shared libraries: librpm.so.9`
- **Investigation**: `rpm -qRp /var/cache/obs-worker/1/.pkgs/rpm.rpm` showed many library deps
- **Fix attempt**: Add `rpm-libs` to Preinstall

### Issue 3: More Library Dependencies
- **Symptom**: `libcap.so.2: cannot open shared object file`
- **Fix attempt**: Add all rpm dependencies to Preinstall:
  ```
  Preinstall: filesystem setup glibc libgcc libcap libacl libarchive bzip2 xz-libs zstd openssl-libs libselinux libsepol popt readline ncurses lua rpm-libs bash coreutils rpm
  ```

### Issue 4: Preinstall Order Conflict (CURRENT)
- **Symptom**:
  ```
  [11/22] preinstalling filesystem...
  ./lib64: Can't replace existing directory with non-directory: Directory not empty
  ./sbin: Can't replace existing directory with non-directory: Directory not empty
  bsdtar: Error exit delayed from previous errors.
  ```
- **Root cause**:
  - OBS preinstall order algorithm resolves dependencies automatically
  - glibc package contains files in `/lib64/` (e.g., `/lib64/ld-linux-x86-64.so.2`)
  - When glibc is preinstalled before filesystem, it creates `/lib64` directory
  - Then filesystem package tries to install `/lib64` as a directory entry
  - bsdtar fails because directory already exists with different content
- **Fix attempts**:
  1. Reorder Preinstall list - OBS ignores manual order
  2. Add `Order: filesystem:glibc` directive - testing in progress
  3. Add `ExpandFlags: preinstallexpand` - may help

## Key Discovery: OBS Order Directive

From Fedora config (`/usr/lib/build/configs/fedora33.conf`):
```
Order: filesystem:glibc
Order: filesystem:vim-filesystem
Order: filesystem:emacs-filesystem
Order: filesystem:acl
Order: filesystem:attr
Order: filesystem:libgcc
Order: filesystem:setup
```

This tells OBS to install filesystem before glibc, setup, libgcc, etc.

## Project Config Template for openEuler

```
Type: spec

# Required for rpm based builds
Required: rpm-build

# Preinstall packages
Preinstall: rpm

# Order constraints - filesystem must come first
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc

# Expand preinstall packages
ExpandFlags: preinstallexpand
```

## Debug Commands

```bash
# Check preinstall order in build log
docker exec obs-server-test bash -c 'curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin/openEuler_24_03/x86_64/hello-world/_log" | grep preinstall'

# Check filesystem package contents
docker exec obs-server-test bash -c 'rpm -qlp /var/cache/obs-worker/1/.pkgs/filesystem.rpm | head -30'

# Check glibc package contents
docker exec obs-server-test bash -c 'rpm -qlp /var/cache/obs-worker/1/.pkgs/glibc.rpm | grep lib64'

# Check rpm dependencies
docker exec obs-server-test bash -c 'rpm -qRp /var/cache/obs-worker/1/.pkgs/rpm.rpm | head -30'

# Update project config
docker exec obs-server-test bash -c 'curl -s -u Admin:admin123 -X PUT -d "Type: spec
Preinstall: rpm
Order: filesystem:glibc
ExpandFlags: preinstallexpand
" http://localhost:4455/source/home:Admin/_config'

# Clear worker cache and rebuild
docker exec obs-server-test bash -c 'rm -rf /var/cache/obs-worker/1/*'
docker exec obs-server-test bash -c 'curl -s -u Admin:admin123 -X POST -H "Content-Length: 0" "http://localhost:4455/build/home:Admin?cmd=rebuild&package=hello-world"'
```

## Lessons Learned

1. **OBS preinstall order is dependency-driven**: Manual order in Preinstall line is ignored
2. **Order directive controls sequence**: Use `Order: A:B` to ensure A installs before B
3. **filesystem must come first**: It creates the base directory structure
4. **glibc creates /lib64**: This conflicts with filesystem's /lib64 entry
5. **bsdtar is strict**: Won't replace directory with different content
