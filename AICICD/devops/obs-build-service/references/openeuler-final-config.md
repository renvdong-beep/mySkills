# OBS Project Configuration for openEuler 24.03 - Verified Working

**Date**: 2026-05-13
**OBS Version**: 2.10.15 (openEuler)
**Container**: obs-server-test
**Result**: hello-world-1.0.0-2.1.x86_64.rpm built successfully

## Final Working Configuration

```
Type: spec
Required: rpm-build
Preinstall: rpm util-linux chkconfig
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
Order: filesystem:bash
Prefer: filesystem
ExpandFlags: preinstallexpand
```

## How to Apply

```bash
curl -u Admin:admin123 -X PUT -d "Type: spec
Required: rpm-build
Preinstall: rpm util-linux chkconfig
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
Order: filesystem:bash
Prefer: filesystem
ExpandFlags: preinstallexpand
" "http://localhost:4455/source/home:Admin/_config"
```

## Key Elements Explained

| Directive | Purpose |
|-----------|---------|
| `Type: spec` | Build type - OBS expects build type names, not binary type names |
| `Required: rpm-build` | Build environment requirement |
| `Preinstall: rpm util-linux chkconfig` | Minimal preinstall - rpm for database, util-linux for `su`, chkconfig for `alternatives` |
| `Order: filesystem:glibc` | Ensures filesystem installs before glibc (prevents /lib64 conflict) |
| `Prefer: filesystem` | Prefer filesystem package when multiple providers exist |
| `ExpandFlags: preinstallexpand` | Expand preinstall dependencies automatically |

## Why This Works

1. **Minimal Preinstall**: Only essential packages, OBS auto-resolves dependencies
2. **Order Constraints**: Prevents glibc from creating `/lib64` before filesystem
3. **chkconfig**: Required for binutils postinstall to create `/usr/bin/ld` symlink via alternatives
4. **util-linux**: Required for `su` command used by OBS build scripts

## Common Mistakes to Avoid

1. **Don't use `Type: rpm`** - Use `Type: spec` for spec file builds
2. **Don't add too many Preinstall packages** - OBS resolves dependencies automatically
3. **Don't forget Order constraints** - filesystem must come before glibc
4. **Don't skip chkconfig** - gcc needs ld symlink from alternatives

## Build Verification

```bash
# Trigger rebuild
curl -u Admin:admin123 -X POST -H "Content-Length: 0" \
  "http://localhost:4455/build/home:Admin?cmd=rebuild&package=hello-world"

# Check status
curl -u Admin:admin123 "http://localhost:4455/build/home:Admin/_result"

# Download result
curl -u Admin:admin123 "http://localhost:4455/build/home:Admin/openEuler_24_03/x86_64/hello-world"
```

## Related Documentation

- Full debugging session: `references/chroot-preinstall-debug.md`
- OBS advanced guide: project docs/architecture/obs-advanced-guide.md