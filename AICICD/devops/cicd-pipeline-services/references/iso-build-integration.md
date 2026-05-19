# ISO Build Integration with webhook-server

## Problem

When webhook-server triggers ISO build via `build_in_docker.sh`, the ISO file is not generated in `_internal/out/package/aarch64/S5000C/` directory.

## Root Cause Analysis

### Issue 1: Wrong Script Path

webhook-server was calling `build_in_docker.sh` from `/packer/` (Packer root directory), but the script is actually located at `/packer/_internal/build_in_docker.sh`.

**Symptom**: `build.sh: No such file or directory` in ISO build logs

**Fix**: Update webhook-server `trigger_iso_build()` function:
```python
# WRONG
build_script = os.path.join(PACKER_DIR, "build_in_docker.sh")
cmd = f"docker run ... -w /packer ... bash build_in_docker.sh {config}"

# CORRECT
build_script = os.path.join(PACKER_DIR, "_internal", "build_in_docker.sh")
cmd = f"docker run ... -w /packer/_internal ... bash build_in_docker.sh {config}"
```

### Issue 2: Container Exits Before ISO Packaging Complete

The ISO build container uses `--rm` flag and exits after starting the build process. The actual ISO packaging step (`genisoimage`) may not complete.

**Symptom**: 
- Build container exits
- `iso_dir/data/` contains kernel and rootfs.tar.gz
- No `.iso` file in `_internal/out/package/aarch64/S5000C/`

**Root Cause**: `build_in_docker.sh` starts a nested Docker container for the actual build. The outer container (alpine) exits immediately after starting the inner container. If the inner container fails or takes too long, the ISO is never generated.

### Issue 3: Permission Denied During ISO Packaging

When running `build.sh` manually on host, permission errors occur because rootfs files were created by Docker container with root ownership.

**Symptom**:
```
cp: 无法删除 '.../rootfs/lib/modules/...': Permission denied
tar: .../rootfs.tar.gz: 无法 open: Permission denied
genisoimage: Permission denied. Unable to open disc image file '.../6.12.y-intewell-S5000C-rt_defconfig.iso'.
```

**Fix**: Fix permissions before running build:
```bash
# Fix ownership (requires root)
sudo chown -R nando:nando /home/nando/Intewell-unified-packer/_internal/out/main_base_aarch64-S5000C/

# Or run build in Docker container (has root inside)
docker run --rm --privileged \
  -v /home/nando/Intewell-unified-packer:/packer \
  -w /packer/_internal \
  rootfs_openeuler_24.03-lts-sp1_aarch64 \
  bash build.sh main_base_aarch64-S5000C.json
```

## Correct ISO Build Flow

### From webhook-server (Automated)

```python
def trigger_iso_build(package_name: str, iso_configs: list) -> dict:
    """Trigger Packer ISO build via Docker on host"""
    PACKER_DIR = os.getenv("PACKER_DIR", "/home/nando/Intewell-unified-packer")
    
    for config in iso_configs:
        container_name = f"iso-trigger-{package_name}"
        
        # Run on HOST via docker.sock
        # The container executes build_in_docker.sh which creates the actual build container
        cmd = f"""docker run -d --name {container_name} --rm \
            -v {PACKER_DIR}:/packer \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -w /packer/_internal \
            alpine:latest \
            sh -c 'apk add bash && bash build_in_docker.sh {config}'"""
        
        subprocess.Popen(cmd, shell=True)
```

**Key Points**:
1. Working directory must be `/packer/_internal` (where `build_in_docker.sh` and `build.sh` are located)
2. Mount `docker.sock` so the container can create nested build containers
3. Use `--rm` to auto-cleanup after completion

### Manual Verification

```bash
# Check if build container is running
docker ps | grep rootfs

# Check build progress
docker logs <container_name>

# Check ISO output
ls -la /home/nando/Intewell-unified-packer/_internal/out/package/aarch64/S5000C/

# Manual build (if automated fails)
cd /home/nando/Intewell-unified-packer/_internal
docker run --rm --privileged \
  -v /home/nando/Intewell-unified-packer:/packer \
  -w /packer/_internal \
  rootfs_openeuler_24.03-lts-sp1_aarch64 \
  bash build.sh main_base_aarch64-S5000C.json
```

## Build Time Expectations

- OBS build (x86_64 + aarch64): ~2-3 minutes
- ISO build (kernel + rootfs + packaging): ~5-10 minutes
- Total end-to-end: ~10-15 minutes from push to ISO

## Verification Checklist

After ISO build completes:

1. Check ISO file exists and is recent:
   ```bash
   ls -la /home/nando/Intewell-unified-packer/_internal/out/package/aarch64/S5000C/*.iso
   ```

2. Verify ISO contains the new package:
   ```bash
   # Mount ISO and check RPM is present
   sudo mount -o loop /path/to/iso /mnt/iso
   ls /mnt/iso/Packages/ | grep <package-name>
   sudo umount /mnt/iso
   ```

3. Check build logs for errors:
   ```bash
   docker logs <build-container>
   ```

## Session Reference

- **Date**: 2026-05-18
- **Test**: test36 full chain automation
- **Result**: Pipeline #175 success, OBS build success, ISO generated (1.18GB)
- **Issues Fixed**: 
  - build_in_docker.sh path correction
  - Permission issues during ISO packaging
  - Working directory set to /packer/_internal

## Additional Issues (2026-05-18)

### Issue 4: genisoimage Not Found in Build Container

**Symptom**: `genisoimage: command not found` during pack.sh execution

**Root Cause**: 
1. `rootfs_openeuler` container's default repo points to unreachable internal FTP (192.168.11.33)
2. Container doesn't have genisoimage pre-installed
3. build.sh tries to install via dnf but fails due to unreachable repo

**Fix**: Delete default repos, use accessible mirror, install genisoimage before build.sh:
```python
# In trigger_iso_build()
packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"  # HOST path
repo_content = "[OS]\\nname=OS\\nbaseurl=https://mirrors.aliyun.com/openeuler/openEuler-24.03-LTS-SP1/OS/aarch64/\\nenabled=1\\ngpgcheck=0"

cmd = f"docker run -d --name {container_name} --privileged --network host --platform {platform} " \
      f"-v {packer_internal_path}:/userdefos -w /userdefos {docker_image} /bin/bash -c " \
      f"'rm -f /etc/yum.repos.d/*.repo && echo -e \"{repo_content}\" > /etc/yum.repos.d/openeuler.repo " \
      f"&& dnf -y install genisoimage && bash build.sh {config} 2>&1 | tee {log_file}'"
```

### Issue 5: Docker-in-Docker Volume Path Mismatch

**Symptom**: ISO build container can't find files that exist in webhook-server's mounted volume

**Root Cause**: When webhook-server has `/packer` mounted from host's `/home/nando/Intewell-unified-packer`, and starts a new container with `-v /packer/_internal:/userdefos`, the new container gets an EMPTY directory because `/packer` only exists in webhook-server's namespace.

**Fix**: Always use HOST's actual path for volume mounts:
```python
# WRONG - /packer only exists in webhook-server container
cmd = f"docker run ... -v /packer/_internal:/userdefos ..."

# CORRECT - use host's actual path
packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"
cmd = f"docker run ... -v {packer_internal_path}:/userdefos ..."
```

**Verified**: test100 full-chain automation succeeded with webhook-server v3.4 (2026-05-18 19:26)
