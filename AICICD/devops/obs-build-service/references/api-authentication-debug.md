# OBS API Authentication Debug Session (2026-05-14)

## Problem
OBS API authentication failed after database migration and user creation:
```
curl -u Admin:admin123 "http://localhost:4455/source/home:Admin/_meta"
<status code="authentication_required">
  <summary>Unknown user 'Admin' or invalid password</summary>
</status>
```

## Root Cause Analysis

### 1. User Model Structure
OBS User model (`/srv/www/obs/api/app/models/user.rb`) uses `has_secure_password`:
```ruby
class User < ApplicationRecord
  has_secure_password validations: false
  # Fields: password_digest, deprecated_password, deprecated_password_hash_type, deprecated_password_salt
end
```

### 2. Password Authentication Flow
Rails `has_secure_password` uses bcrypt (`password_digest` field). However, OBS legacy code also supports MD5 passwords via `deprecated_password` fields.

**Critical discovery**: If `deprecated_password` field is populated, authentication fails even when `password_digest` is correctly set.

### 3. Debug Commands
```bash
# Check user fields
docker exec obs-server bash -c '
cd /srv/www/obs/api
RAILS_ENV=production bundle exec rails runner "
  u = User.find_by(login: \"Admin\")
  puts \"Password digest: #{u.password_digest[0..30]}...\" if u.password_digest
  puts \"Deprecated password: #{u.deprecated_password}\" if u.deprecated_password
"
'

# Test authentication
docker exec obs-server bash -c '
cd /srv/www/obs/api
RAILS_ENV=production bundle exec rails runner "
  u = User.find_by(login: \"Admin\")
  puts \"Authenticate: #{u.authenticate(\"admin123\").class}\"
"
'
'
```

### 4. Fix Sequence
1. Create user with bcrypt password:
```bash
docker exec obs-server bash -c '
cd /srv/www/obs/api
RAILS_ENV=production bundle exec rails runner "
  u = User.find_or_initialize_by(login: \"Admin\")
  u.email = \"admin@obs.local\"
  u.password = \"admin123\"
  u.password_confirmation = \"admin123\"
  u.state = \"confirmed\"
  u.in_beta = true
  u.save!
"
'
```

2. Clear deprecated password fields (CRITICAL):
```bash
docker exec obs-server bash -c '
cd /srv/www/obs/api
RAILS_ENV=production bundle exec rails runner "
  u = User.find_by(login: \"Admin\")
  u.deprecated_password = nil
  u.deprecated_password_hash_type = nil
  u.deprecated_password_salt = nil
  u.save!
  puts \"Authenticate: #{u.authenticate(\"admin123\").class}\"
"
'
'
```

Expected output: `Authenticate: User` (not `FalseClass`)

## Project Validation Error

### Problem
Creating project with `<build><enable/></build>` returned validation error:
```
<status code="validation_failed">
  <summary>project validation error: 11:0: ERROR: Error validating value </summary>
</status>
```

### Fix
Remove `<build>` section or use proper format. OBS enables builds by default for new projects.

## Architecture Database Configuration

### Problem
aarch64 architecture not available after database migration.

### Fix
```bash
# Enable architectures
docker exec obs-server bash -c '
cd /srv/www/obs/api
RAILS_ENV=production bundle exec rails runner "
  Architecture.find_by(name: \"aarch64\").update!(available: true)
  Architecture.find_or_create_by(name: \"loongarch64\").update!(available: true)
"
'

# Clear Rails cache (CRITICAL)
docker exec obs-server bash -c "cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails runner 'Rails.cache.clear'"
```

## Data Directory Migration

### Disk Usage Analysis
```
Root partition /: 69G total, 42G used (64%), 24G available
Home partition /home: 1.8T total, 22G used (2%), 1.6T available
```

### OBS Container Mount Points
```bash
# Before migration - data inside container (lost on recreation)
docker inspect obs-server-test --format '{{json .Mounts}}'

# After migration - data persisted on host
docker run -d --name obs-server-test \
  -v /home/nando/AICICD/data/obs-srv/obs:/srv/obs \
  -v /home/nando/AICICD/data/obs:/var/obs \
  ...
```

## Lessons Learned

1. **Always clear deprecated_password fields** when setting bcrypt password for OBS users
2. **Rails cache must be cleared** after any database changes to architectures
3. **Mount OBS data directories** to host to persist data and avoid root partition exhaustion
4. **Project validation is strict** - avoid empty elements like `<enable/>`
5. **User model has `in_beta` field** (not `admin` field) for admin-like permissions