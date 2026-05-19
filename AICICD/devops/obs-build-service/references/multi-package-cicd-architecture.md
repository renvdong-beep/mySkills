# Multi-Package Multi-Developer CI/CD Architecture

## Problem Statement

The current CI/CD pipeline is hardcoded for a single package (hello-world).
To support multiple packages (e.g., ROS2 nav2, moveit2) with multiple developers
working in parallel, the pipeline needs:

1. Per-package OBS project isolation
2. Automatic CI project mapping (no per-repo CI config)
3. Parallel build scheduling
4. Unified sync and ISO generation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ GitLab                                                       │
│                                                              │
│  repo: ros2-nav2 ──┐                                        │
│  repo: ros2-moveit ─┤── push triggers CI ──→ OBS API upload │
│  repo: hello-world ─┘                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ OBS Projects                                                 │
│                                                              │
│  home:Admin:openEuler24.03-SP1  ← Base DoD (aligned w/rootfs)│
│  home:Admin:ros2-nav2           ← Independent build          │
│  home:Admin:ros2-moveit         ← Independent build          │
│  home:Admin:hello-world         ← Independent build          │
│  home:Admin                     ← Integration (layer-links)  │
│    └─ path: openEuler24.03-SP1                               │
│    └─ path: ros2-nav2                                         │
│    └─ path: ros2-moveit                                       │
│    └─ path: hello-world                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ sync-service                                                 │
│                                                              │
│  /sync-all/home:Admin/standard/aarch64                       │
│    → Downloads ALL RPMs from integration project             │
│    → Copies to obs-aarch64 repo                              │
│    → Runs createrepo_c                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Packer ISO Build                                             │
│                                                              │
│  appset: ros2-nav2.app + ros2-moveit.app + hello-world.app   │
│  JSON config: applist = [all .app directories]               │
│  → dnf install from obs-aarch64 repo                         │
│  → genisoimage → ISO                                         │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. OBS Project Isolation

Each package gets its own OBS sub-project. This provides:
- Independent build scheduling (no package blocks another)
- Independent dependency resolution
- Clean separation of concerns
- Easy to add/remove packages

The integration project (`home:Admin`) uses OBS's layer-link mechanism
(`<path>` elements) to merge all sub-project outputs. OBS automatically
resolves dependencies across linked projects.

### 2. GitLab CI Template with CI_PROJECT_NAME

Use GitLab's built-in `CI_PROJECT_NAME` variable to automatically map
repositories to OBS projects. Every repo uses the SAME `.gitlab-ci.yml`:

```yaml
stages:
  - build
  - obs-trigger
  - sync

variables:
  OBS_API_URL: http://localhost:4455
  OBS_USER: Admin
  OBS_PASSWORD: admin123
  OBS_PROJECT: "home:Admin:${CI_PROJECT_NAME}"  # Auto-mapped
  OBS_PACKAGE: "${CI_PROJECT_NAME}"              # Auto-mapped
  OBS_INTEGRATION_PROJECT: "home:Admin"
  SYNC_URL: http://localhost:8090

build:
  stage: build
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache tar
    - cd ${CI_PROJECT_NAME}
    - tar -czvf ../${CI_PROJECT_NAME}-1.0.0.tar.gz src ${CI_PROJECT_NAME}.spec Makefile
  artifacts:
    paths:
      - ${CI_PROJECT_NAME}-1.0.0.tar.gz
    expire_in: 1 hour

obs-trigger:
  stage: obs-trigger
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -X PUT -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/source/$OBS_PROJECT/$OBS_PACKAGE/${CI_PROJECT_NAME}-1.0.0.tar.gz" --data-binary @${CI_PROJECT_NAME}-1.0.0.tar.gz
    - curl -X PUT -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/source/$OBS_PROJECT/$OBS_PACKAGE/${CI_PROJECT_NAME}.spec" --data-binary @${CI_PROJECT_NAME}/${CI_PROJECT_NAME}.spec

sync-aarch64:
  stage: sync
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    # Wait for OBS build to complete
    - 'while ! curl -s -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/build/$OBS_INTEGRATION_PROJECT/standard/aarch64/_result" | grep -q "succeeded"; do sleep 30; done'
    # Sync entire integration project (not just current package)
    - 'curl -X POST $SYNC_URL/sync-all/$OBS_INTEGRATION_PROJECT/standard/aarch64'
    - 'curl -X POST $SYNC_URL/update-repo/aarch64'
```

### 3. OBS Sub-Project Creation (Automated)

When a new repo is created in GitLab, the corresponding OBS sub-project
needs to be set up. This can be automated via webhook-server:

```python
# webhook-server receives GitLab project creation event
# → Creates OBS sub-project via API
# → Adds sub-project as path in integration project
# → Sets DoD base project as path in sub-project
```

Or manually:
```bash
# Create sub-project
curl -X PUT -u Admin:admin123 -H "Content-Type: text/xml" \
  -d '<project name="home:Admin:ros2-nav2">
    <title>ROS2 Navigation Stack</title>
    <repository name="standard" rebuild="local" block="local">
      <path project="home:Admin:openEuler24.03-SP1" repository="standard"/>
      <arch>aarch64</arch>
    </repository>
  </project>' \
  "http://localhost:4455/source/home:Admin:ros2-nav2/_meta"

# Add to integration project
# Update home:Admin _meta to include new path
```

### 4. Packer Appset Management

Each OBS package corresponds to a `.app` directory in Packer:

```
_internal/prebuild_cache/all_appsets/aarch64/
├── hello-world.app/
│   └── hello-world.rpm.list       # content: "hello-world"
├── ros2-nav2.app/
│   └── ros2-nav2.rpm.list         # content: "ros2-nav2"
└── ros2-moveit.app/
│   └── ros2-moveit.rpm.list       # content: "ros2-moveit"
```

JSON config for full ISO:
```json
{
  "applist": ["hello-world.app", "ros2-nav2.app", "ros2-moveit.app"],
  "runlist": ["main.project"],
  "arch": "aarch64",
  "board": ["S5000C"],
  "kernel_version": ["6.12.y"],
  "kernel_config": "intewell-S5000C-rt_defconfig",
  "prebuild_dir": "local_cache"
}
```

### 5. ISO Build Trigger Modes

- **Manual/定时**: For release builds, trigger Packer manually or via cron
- **Automated**: After sync-all completes, if all critical packages succeeded,
  automatically trigger Packer build via webhook or API call

## Parallel Safety

- OBS sub-projects build independently — no contention between developers
- Integration project layer-link automatically picks up new builds
- sync-all merges all sub-project RPMs into single repo
- Packer builds are independent of OBS builds (uses cached RPMs)

## Scaling Considerations

- **OBS Worker capacity**: Each sub-project needs its own scheduler. With many
  packages, consider adding more workers or using `rebuild="local"` to avoid
  cascading rebuilds.
- **Repo size**: As packages accumulate, createrepo_c takes longer. Consider
  periodic repo cleanup or versioned repos.
- **CI queue**: GitLab Runner capacity limits parallel pipelines. Add more
  runners for high-traffic projects.