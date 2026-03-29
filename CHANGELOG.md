# Changelog

## [2.0.0] - 2026-03-17
### Changed
- Removed expiring-soon threshold logic (handled by separate flow)
- Removed SECRET_EXPIRY_THRESHOLD_DAYS variable entirely
- Moved all inline YAML scripts to external .ps1 files
- Improved module install logic using Get-InstalledModule with load verification
- Added Pester import to test file

### Added
- scripts/Invoke-Tests.ps1 - Pester runner extracted from YAML
- scripts/Confirm-AzureLogin.ps1 - login check extracted from YAML
- scripts/Show-AgentInfo.ps1 - diagnostics extracted from YAML

## [1.0.0] - 2026-03-17
### Added
- Initial professional repo structure
- Core secret cleanup with retry logic
- Graph auth helper
- Three-stage pipeline
- Setup and documentation
