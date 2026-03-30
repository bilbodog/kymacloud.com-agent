# Installation Script Updates - v2.1

## Summary

The `install/install/install.sh` script has been comprehensively updated to reflect the new v2.1 platform enhancements with the unified command system.

## Key Updates Made

### 1. Version Updates ✅
- **Platform version:** `2.0.0` → `2.1.0`
- **Banner:** Updated to show v2.1 with "36 Unified Commands Available"
- **Welcome message:** Enhanced to show the new command system

### 2. Path Updates ✅
- **Site manager path:** `/opt/kymacloud/platform/site-manager.sh` → `/opt/kymacloud/platform/scripts/utilities/site-manager.sh`
- **Script permissions:** Now sets executable for `scripts/`, `modules/`, and `lib/` directories
- **Verification:** Added checks for all 7 new/enhanced modules

### 3. Module Verification ✅
Added verification for all modules:
- `modules/site.sh`
- `modules/user.sh`
- `modules/database.sh`
- `modules/system.sh`
- **`modules/credentials.sh`** (NEW)
- **`modules/diagnostics.sh`** (NEW)
- **`modules/backup.sh`** (NEW)

### 4. Bash Aliases Updated ✅

**Before:**
```bash
alias kyma='sudo /opt/kymacloud/platform/site-manager.sh'
alias kyma-sites='...'
```

**After:**
```bash
alias kyma='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh'
alias kyma-sites='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh site:list'
alias kyma-status='...'
alias kyma-logs='...'
alias kyma-backup='...'  # NEW!
```

### 5. Welcome Message Enhanced ✅

**New login message:**
```
Kyma Hosting Platform v2.1
═══════════════════════════════════════
Unified Command System - 36 commands available!
═══════════════════════════════════════
Usage: kyma <category>:<action> [options]

Examples:
  kyma site:list              # List all sites
  kyma credentials:show <domain>
  kyma diagnose:site <domain>
  kyma backup:all             # Backup everything

Help: kyma --help
```

### 6. Service Verification Updated ✅

**Before:** Checked for legacy shared PHP containers (`php-fpm-82`, `php-fpm-81`)

**After:** 
- Checks only core services (`traefik`, `nginx`, `mariadb`)
- Recognizes per-site PHP containers are created on-demand
- Shows informative message: "Ingen PHP containers endnu (oprettes per site)"

### 7. Sudo Configuration Updated ✅

Added both old and new paths for backward compatibility:
```bash
# Allow kymacloud to run site-manager.sh as root (updated path)
kymacloud ALL=(ALL) NOPASSWD: /opt/kymacloud/platform/scripts/utilities/site-manager.sh
kymacloud ALL=(ALL) NOPASSWD: /opt/kymacloud/platform/site-manager.sh
```

### 8. README File Enhanced ✅

**Added to configuration README:**
```
AVAILABLE COMMANDS (36 total):
  Site:         kyma site:add|remove|list|info|backup|restore
  Users:        kyma user:sftp:add|remove|list
                kyma user:ftp:add|remove|list
  Database:     kyma db:backup|restore|list
  Credentials:  kyma credentials:show|sftp
  Diagnostics:  kyma diagnose:ftp|sftp|site
  Backup:       kyma backup:all|platform
  System:       kyma system:start|stop|restart|status|verify|update
```

### 9. Completion Message Enhanced ✅

**New steps added:**
```bash
1. Log ind som kymacloud bruger:
   ssh kymacloud@<server_ip>

2. Tilføj dit første website:
   kyma site:add example.com php-fpm-82 wordpress

3. Se system status:
   kyma system:status

4. Se alle tilgængelige kommandoer:
   kyma --help

5. Diagnosticer site efter oprettelse:  # NEW!
   kyma diagnose:site example.com

6. Se credentials for site:             # NEW!
   kyma credentials:show example.com
```

### 10. Platform Features Listed ✅

**Added feature highlights:**
```
Platform Features:
  ✓ 36 unified commands via 'kyma' interface
  ✓ Per-site PHP containers (isolation & custom config)
  ✓ Built-in diagnostics (kyma diagnose:*)
  ✓ Comprehensive backup system (kyma backup:*)
  ✓ Credentials management (kyma credentials:*)
  ✓ JSON API support (--json flag)
```

### 11. Documentation References ✅

**Added quick access to docs:**
```bash
Quick Reference: cat $KYMA_HOME/platform/QUICK_REFERENCE.md
Full Docs:       cat $KYMA_HOME/platform/README.md
Command Guide:   cat $KYMA_HOME/platform/COMMAND_SYSTEM.md
```

## File Verification Enhancements

The install script now verifies:

### Required Files
- ✅ `scripts/utilities/site-manager.sh` (new path)
- ✅ `lib/config.sh`
- ✅ `docker-compose.yml`

### Required Modules (with warnings if missing)
- ✅ `modules/site.sh`
- ✅ `modules/user.sh`
- ✅ `modules/database.sh`
- ✅ `modules/system.sh`
- ✅ `modules/credentials.sh` (NEW)
- ✅ `modules/diagnostics.sh` (NEW)
- ✅ `modules/backup.sh` (NEW)

## Backward Compatibility

All updates maintain backward compatibility:
- Old script paths still supported in sudoers
- Legacy PHP containers recognized if present
- Fallback configuration generation if templates missing
- Warnings instead of errors for missing optional modules

## Testing Checklist

Before release, verify:
- [ ] Install script runs successfully
- [ ] All 7 modules are copied correctly
- [ ] Sudo permissions work for both paths
- [ ] Bash aliases function correctly
- [ ] Core services start properly
- [ ] Documentation files are present
- [ ] kyma command works after installation
- [ ] Module verification doesn't fail on missing optional files

## Changes Summary

**Files Modified:** 1 (`install/install/install.sh`)
**Lines Changed:** ~50+ updates across multiple sections
**New Features:** 3 new modules recognized
**Version Bump:** 2.0.0 → 2.1.0
**Commands Added:** References to 13 new commands
**Backward Compatible:** ✅ Yes

## Migration Notes

For existing installations upgrading from v2.0 to v2.1:
1. New modules are automatically recognized
2. Bash aliases are updated on next login
3. Sudoers may need manual update (or run upgrade script)
4. Documentation files are automatically available
5. No breaking changes to existing functionality

## Example Installation Flow

```bash
# Download and run installer
curl -sSL https://install.kymacloud.com/install.sh | bash -s -- <QUERY_ID>

# After installation, user sees:
Kyma Hosting Platform v2.1
═══════════════════════════════════════
Unified Command System - 36 commands available!
═══════════════════════════════════════

# User can immediately use:
kyma site:add myblog.com php-fpm-82 wordpress
kyma credentials:show myblog.com
kyma diagnose:site myblog.com
kyma backup:all
```

## Benefits

The updated install script ensures:
1. ✅ All new features are properly installed
2. ✅ Users are informed about new capabilities
3. ✅ Proper permissions and paths are set
4. ✅ Documentation is accessible
5. ✅ Backward compatibility maintained
6. ✅ Clear upgrade path from v2.0

---

**Install Script Status:** ✅ **UPDATED AND READY**
**Version:** 2.1.0
**Date:** November 1, 2025

