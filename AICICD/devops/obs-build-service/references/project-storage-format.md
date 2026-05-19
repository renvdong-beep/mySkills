# OBS Project Storage Format

## Problem
OBS API shows project exists but backend returns "project does not exist".

## Root Cause
OBS has two separate storage mechanisms:
1. **API (Rails/MySQL)**: Stores project metadata in `projects` table
2. **Backend (bs_srcserver)**: Reads from filesystem `$projectsdir/*.xml`

These are NOT automatically synchronized. The backend uses a simple filesystem scan.

## Backend Code Reference

From `/usr/lib/obs/server/BSRevision.pm`:

```perl
sub lsprojects_local {
  my ($deleted) = @_;
  if ($deleted) {
    my @projids = grep {s/\.pkg$//} ls("$projectsdir/_deleted");
    @projids = grep {! -e "$projectsdir/$_.xml"} @projids;
    return sort @projids;
  }
  local *D;
  return () unless opendir(D, $projectsdir);
  my @projids = grep {s/\.xml$//} readdir(D);  # <-- Key line: reads .xml files
  closedir(D);
  return sort @projids;
}
```

## Correct Project Creation Sequence

### Option A: Via API (Recommended)
```bash
# API will create both database entry and backend XML file
curl -X PUT -u Admin:admin123 "http://localhost:4455/source/home:Admin/_meta" \
  -H "Content-Type: text/xml" -d '<project name="home:Admin">...</project>'
```

### Option B: Manual Backend File (For Debugging)
```bash
# Create backend XML file
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

# Create database entry
docker exec obs-server mysql --socket=/var/run/mysqld/mysqld.sock obs_api -e "
INSERT INTO projects (name, title, created_at, updated_at) 
VALUES ('home:Admin', 'Admin Home Project', NOW(), NOW());
"

# Clear API cache
docker exec obs-server bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner 'Rails.cache.clear'"
```

## Verification

```bash
# Check backend sees project
curl -s http://localhost:5352/source
# Should show: <directory><entry name="home:Admin"/></directory>

# Check API sees project
curl -s -u Admin:admin123 http://localhost:4455/source/home:Admin/_meta
# Should return project XML
```

## Common Mistakes

1. Creating subdirectory `/srv/obs/projects/home:Admin/_meta` - WRONG
2. Creating file `/srv/obs/projects/home:Admin/_meta.xml` - WRONG
3. Creating file `/srv/obs/projects/home:Admin.xml` - CORRECT

## Session Reference
- Date: 2026-05-14
- Issue: Project created via database but not visible to backend
- Resolution: Use `.xml` flat file format in projects directory
