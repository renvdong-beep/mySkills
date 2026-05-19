# ISO Build genisoimage Fix (2026-05-18)

## Problem

ISO build triggered by webhook-server fails with:
```
/userdefos/out/main_base_aarch64-S5000C/image_base_path/pack.sh: line 32: genisoimage: command not found
```

## Root Causes

1. **Unreachable internal repo**: `rootfs_openeuler` container's default `/etc/yum.repos.d/intewell.repo` points to `ftp://192.168.11.33/` which is unreachable from the build environment

2. **Missing package**: Container doesn't have `genisoimage` pre-installed

3. **Docker-in-Docker path mismatch**: webhook-server container's `/packer` mount doesn't translate to host path when starting sibling containers

## Solution

### Complete webhook-server trigger_iso_build() Implementation

```python
def trigger_iso_build(package_name: str, iso_configs: list) -> dict:
    """Trigger ISO build after Pipeline success"""
    PACKER_DIR = os.getenv("PACKER_DIR", "/home/nando/Intewell-unified-packer")
    
    results = []
    for config in iso_configs:
        config_path = os.path.join(PACKER_DIR, "_internal", "system_cfg", config)
        if not os.path.exists(config_path):
            logger.error(f"Packer 配置文件不存在: {config_path}")
            continue
        
        # Parse config to determine architecture and docker image
        with open(config_path) as f:
            config_data = json.load(f)
        arch = config_data.get("arch", "aarch64")
        docker_image = f"rootfs_openeuler_24.03-lts-sp1_{arch}"
        platform = f"linux/{arch}"
        
        container_name = f"iso-build-{package_name}-{config.replace('.json','')}"
        log_file = f"/tmp/iso-build-{package_name}-{config.replace('.json','')}.log"
        
        # Delete existing container if present
        subprocess.run(f"docker rm -f {container_name} 2>/dev/null", shell=True)
        
        # CRITICAL: Use HOST's actual path, not container's mount point
        packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"
        
        # CRITICAL: Remove default repos, use accessible mirror, install genisoimage
        repo_content = "[OS]\\nname=OS\\nbaseurl=https://mirrors.aliyun.com/openeuler/openEuler-24.03-LTS-SP1/OS/aarch64/\\nenabled=1\\ngpgcheck=0"
        
        cmd = f"docker run -d --name {container_name} --privileged --network host --platform {platform} " \
              f"-v {packer_internal_path}:/userdefos -w /userdefos {docker_image} /bin/bash -c " \
              f"'rm -f /etc/yum.repos.d/*.repo && echo -e \"{repo_content}\" > /etc/yum.repos.d/openeuler.repo " \
              f"&& dnf -y install genisoimage && bash build.sh {config} 2>&1 | tee {log_file}'"
        
        logger.info(f"开始构建: {config}")
        proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        logger.info(f"ISO 构建已触发: image={docker_image}, config={config}, container={container_name}")
        
        results.append({
            "config": config,
            "container": container_name,
            "status": "triggered"
        })
    
    return {"status": "success", "builds": results}
```

## Key Points

1. **Delete default repos first**: `rm -f /etc/yum.repos.d/*.repo` — Internal FTP servers are often unreachable

2. **Use accessible public mirror**: Aliyun (`mirrors.aliyun.com`) works reliably in China

3. **Install genisoimage before build.sh**: The `pack.sh` script called by `build.sh` requires `genisoimage`

4. **Use host path for volume mounts**: When webhook-server creates sibling containers via docker.sock, volume paths are resolved on the HOST, not in webhook-server's namespace

5. **Set working directory**: `-w /userdefos` ensures `build.sh` is found

## Verification

```bash
# Check ISO build container
docker ps -a | grep iso-build

# Check build logs
docker logs iso-build-test100-main_base_aarch64-S5000C

# Check ISO file
ls -la /home/nando/Intewell-unified-packer/_internal/out/package/aarch64/S5000C/
```

## Test Results

- **test36**: Pipeline #184 → ISO build success (1.19GB, 19:06)
- **test100**: Pipeline #186 → ISO build success (1.19GB, 19:26)

## Version History

- **v3.5**: Added CI variable setting logging for verification
- **v3.4**: Fixed genisoimage installation, Docker-in-Docker path, working directory
- **v3.3**: Fixed heredoc syntax
- **v3.2**: Added repo replacement
- **v3.1**: Initial ISO trigger implementation

## Related: CI Variable Setting Logging

When webhook-server processes a push event, it sets CI variables (PACKAGE_NAME, PACKAGE_DIR) via GitLab API. Without logging, it's impossible to verify if variables were actually set.

**Added in v3.5**:
```python
def set_gitlab_ci_variables(project_id: int, package_name: str, package_dir: str) -> bool:
    logger.info(f"设置CI变量: PACKAGE_NAME={package_name}, PACKAGE_DIR={package_dir}")
    # ... existing code ...
    if result:
        logger.info(f"CI变量 {key}={value} 设置成功")
```

**Log output example**:
```
2026-05-19 01:36:51,052 - app - INFO - 设置CI变量: PACKAGE_NAME=test100, PACKAGE_DIR=test100
2026-05-19 01:36:51,080 - app - INFO - CI变量 PACKAGE_NAME=test100 设置成功
2026-05-19 01:36:51,108 - app - INFO - CI变量 PACKAGE_DIR=test100 设置成功
```

**Manual verification**:
```bash
curl -s "http://localhost:8080/api/v4/projects/1/variables/PACKAGE_NAME" \
  --header "PRIVATE-TOKEN: $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('value'))"
```
