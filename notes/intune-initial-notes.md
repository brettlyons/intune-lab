# Intune Lab – Initial Notes

## Objective
Establish a Microsoft Intune test environment and validate basic device enrollment and policy application.

## Environment
- Microsoft 365 Business Premium Trial
- Tenant: lyonsitlab.onmicrosoft.com
- Entra ID
- Microsoft Intune
- Windows 10/11 test device (VM)

## Planned Tasks
- Create test users and groups
- Enroll a Windows device into Intune
- Apply a basic compliance policy
- Apply a simple configuration profile
- Observe and troubleshoot policy assignment behavior

## Change Management
Ticket management handled in Zammad homelab instance. All changes follow a ticketed workflow:
1. Create ticket describing the change
2. Document intended configuration
3. Implement change
4. Update ticket with results
5. Close ticket

## Notes
- Intune workflow is heavily group-driven; incorrect group membership is a common failure point
- Device sync timing matters — forced sync is often required during testing
- Documentation-first approach helps reduce trial-and-error during configuration

## Next Steps
- Complete device enrollment
- Document compliance policy creation
- Capture common troubleshooting steps
