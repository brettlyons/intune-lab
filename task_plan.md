# Task Plan: Microsoft Intune Lab Setup

## Goal
Complete a documentation-first Intune lab demonstrating device enrollment, policy management, and troubleshooting workflows.

## Phases
- [x] Phase 1: Environment setup
- [x] Phase 2: Create test users and groups in Entra ID
- [x] Phase 3: Enroll Windows test device into Intune
- [x] Phase 4: Apply compliance and configuration policies
- [x] Phase 5: Document troubleshooting workflows

## Completed Tasks
- [x] Confirm Intune license assigned to test user
- [x] Fix MDM enrollment (device was Entra joined but not MDM enrolled)
- [x] Force a device sync
- [x] Apply compliance policy (Defender requirements, NIST password)
- [x] Apply configuration profile (Defender settings via Settings Catalog)
- [x] Break → fix: BitLocker compliance error on VM → disabled requirement
- [x] Update documentation with troubleshooting and lessons learned
- [x] Add screenshots to repo

## Next Session Tasks
- [x] Test automated VM deployment with Autounattend.xml (documented failures and solutions)
- [x] Verify xorriso-based ISO creation works (VM installing unattended)
- [x] Verify OOBE completes and MDM enrollment launches (works - only login required)
- [x] Remove SetupAdmin account post-enrollment (Intune script tested and working)
- [x] Create dynamic device group for automatic policy assignment
- [x] Add SPICE guest tools to unattended install for clipboard sharing
- [x] Create bash script for one-command ISO build (scripts/build-iso.sh)
- [x] Create setup-intune.ps1 to configure Intune/Entra via Microsoft Graph PowerShell (untested)
- [x] Create bash equivalent using curl + Microsoft Graph REST API (untested)
- [ ] Test setup-intune.sh against live tenant
- [ ] Investigate BitLocker on QEMU/KVM VMs with swtpm

## Key Questions
1. What compliance policies are most relevant for demonstrating real-world scenarios?
2. What configuration profiles should be applied?
3. What common troubleshooting scenarios should be documented?

## Decisions Made
- **M365 Business Premium Trial**: M365 Developer sandbox was unavailable
- **Tenant name**: lyonsitlab.onmicrosoft.com
- **Local QEMU/KVM VM**: Chosen over Azure VM for cost efficiency
- **Zammad ticketing**: Using homelab Zammad instance for change management

## Errors Encountered
- M365 Developer Program sandbox qualification failed - used Business Premium trial instead
- Azure VM default pricing (~$170/mo D2) - switched to local VM approach

## Status
**All phases complete.** Device enrolled, policies applied, troubleshooting documented.

### Completed Infrastructure
- Windows 11 VM enrolled in Intune via Entra ID join
- Compliance policy: Defender requirements, NIST password standards
- Configuration profile: Defender settings via Settings Catalog
- Dynamic device group: Intune-Managed-Devices (auto-assigns policies)
- `Autounattend.xml` with VirtIO drivers and SPICE guest tools
- `scripts/build-iso.sh` - one-command ISO build (platform-agnostic)
- `scripts/Remove-SetupAdmin.ps1` - Intune script to clean up temp admin (tested)
- `scripts/setup-intune.sh` - Graph API config script (untested)
- `scripts/setup-intune.ps1` - PowerShell config script (untested)
- Troubleshooting docs with screenshots
