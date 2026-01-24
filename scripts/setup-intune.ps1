#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.DeviceManagement

<#
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!                     WARNING: NOT YET TESTED                          !!!
!!! This script has been written but not validated against a live tenant !!!
!!! Use -WhatIf first and verify behavior before running for real        !!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

.SYNOPSIS
    Configure Intune and Entra ID for the lab environment.

.DESCRIPTION
    This script sets up the complete Intune configuration:
    - Creates dynamic device group for Intune-managed devices
    - Uploads Remove-SetupAdmin.ps1 script
    - Creates compliance policy (Defender, password requirements)
    - Creates configuration profile (Defender settings)
    - Assigns policies to the device group

.NOTES
    Prerequisites:
    - Install-Module Microsoft.Graph -Scope CurrentUser
    - Global Admin or Intune Admin role
    - Run from the intune-lab directory

.EXAMPLE
    ./scripts/setup-intune.ps1
#>

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Configuration
$TenantDomain = "lyonsitlab.onmicrosoft.com"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Resource names
$DeviceGroupName = "Intune-Managed-Devices"
$DeviceGroupDescription = "Dynamic group for all Intune MDM enrolled devices"
$ScriptName = "Remove-SetupAdmin"
$CompliancePolicyName = "Lab-Compliance-Defender-Password"
$ConfigProfileName = "Lab-Config-Defender-Settings"

function Write-Step {
    param([string]$Message)
    Write-Host "`n[$((Get-Date).ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor White
}

function Connect-ToGraph {
    Write-Step "Connecting to Microsoft Graph..."

    $scopes = @(
        "DeviceManagementConfiguration.ReadWrite.All"
        "DeviceManagementManagedDevices.ReadWrite.All"
        "Group.ReadWrite.All"
        "GroupMember.ReadWrite.All"
    )

    Connect-MgGraph -Scopes $scopes -TenantId $TenantDomain

    $context = Get-MgContext
    Write-Host "  Connected as: $($context.Account)" -ForegroundColor Green
}

function New-DynamicDeviceGroup {
    Write-Step "Creating dynamic device group: $DeviceGroupName"

    # Check if group already exists
    $existingGroup = Get-MgGroup -Filter "displayName eq '$DeviceGroupName'" -ErrorAction SilentlyContinue

    if ($existingGroup) {
        Write-Host "  Group already exists (ID: $($existingGroup.Id))" -ForegroundColor Yellow
        return $existingGroup.Id
    }

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would create group" -ForegroundColor Magenta
        return "whatif-group-id"
    }

    $groupParams = @{
        DisplayName = $DeviceGroupName
        Description = $DeviceGroupDescription
        MailEnabled = $false
        MailNickname = "intune-managed-devices"
        SecurityEnabled = $true
        GroupTypes = @("DynamicMembership")
        MembershipRule = "(device.managementType -eq `"MDM`")"
        MembershipRuleProcessingState = "On"
    }

    $group = New-MgGroup -BodyParameter $groupParams
    Write-Host "  Created group (ID: $($group.Id))" -ForegroundColor Green
    return $group.Id
}

function Add-DeviceManagementScript {
    Write-Step "Uploading device management script: $ScriptName"

    $scriptPath = Join-Path $RepoRoot "scripts/Remove-SetupAdmin.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Script not found: $scriptPath"
    }

    # Check if script already exists
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts"
    $existingScripts = Invoke-MgGraphRequest -Uri $uri -Method GET
    $existing = $existingScripts.value | Where-Object { $_.displayName -eq $ScriptName }

    if ($existing) {
        Write-Host "  Script already exists (ID: $($existing.id))" -ForegroundColor Yellow
        return $existing.id
    }

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would upload script" -ForegroundColor Magenta
        return "whatif-script-id"
    }

    # Read and encode script content
    $scriptContent = Get-Content $scriptPath -Raw
    $scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
    $scriptBase64 = [Convert]::ToBase64String($scriptBytes)

    $scriptParams = @{
        displayName = $ScriptName
        description = "Remove temporary SetupAdmin local account after Entra ID enrollment"
        scriptContent = $scriptBase64
        runAsAccount = "system"
        enforceSignatureCheck = $false
        runAs32Bit = $false
        fileName = "Remove-SetupAdmin.ps1"
    }

    $script = Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($scriptParams | ConvertTo-Json)
    Write-Host "  Uploaded script (ID: $($script.id))" -ForegroundColor Green
    return $script.id
}

function Add-CompliancePolicy {
    param([string]$GroupId)

    Write-Step "Creating compliance policy: $CompliancePolicyName"

    # Check if policy already exists
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"
    $existingPolicies = Invoke-MgGraphRequest -Uri $uri -Method GET
    $existing = $existingPolicies.value | Where-Object { $_.displayName -eq $CompliancePolicyName }

    if ($existing) {
        Write-Host "  Policy already exists (ID: $($existing.id))" -ForegroundColor Yellow
        return $existing.id
    }

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would create compliance policy" -ForegroundColor Magenta
        return "whatif-policy-id"
    }

    # Windows 10/11 compliance policy
    $policyParams = @{
        "@odata.type" = "#microsoft.graph.windows10CompliancePolicy"
        displayName = $CompliancePolicyName
        description = "Requires Defender and password standards"
        # Password requirements (NIST-aligned)
        passwordRequired = $true
        passwordMinimumLength = 8
        passwordRequiredType = "deviceDefault"
        passwordMinutesOfInactivityBeforeLock = 15
        # Defender requirements
        defenderEnabled = $true
        defenderVersion = $null
        # Don't require BitLocker (VMs may not support it)
        bitLockerEnabled = $false
        # Device health
        secureBootEnabled = $true
        codeIntegrityEnabled = $false
    }

    $policy = Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($policyParams | ConvertTo-Json -Depth 10)
    Write-Host "  Created policy (ID: $($policy.id))" -ForegroundColor Green

    # Assign to group
    if ($GroupId -and $GroupId -ne "whatif-group-id") {
        Write-Host "  Assigning to group..." -ForegroundColor Gray
        $assignUri = "$uri/$($policy.id)/assign"
        $assignParams = @{
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $GroupId
                    }
                }
            )
        }
        Invoke-MgGraphRequest -Uri $assignUri -Method POST -Body ($assignParams | ConvertTo-Json -Depth 10)
        Write-Host "  Assigned to $DeviceGroupName" -ForegroundColor Green
    }

    return $policy.id
}

function Add-ConfigurationProfile {
    param([string]$GroupId)

    Write-Step "Creating configuration profile: $ConfigProfileName"

    # Check if profile already exists
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
    $existingProfiles = Invoke-MgGraphRequest -Uri $uri -Method GET
    $existing = $existingProfiles.value | Where-Object { $_.displayName -eq $ConfigProfileName }

    if ($existing) {
        Write-Host "  Profile already exists (ID: $($existing.id))" -ForegroundColor Yellow
        return $existing.id
    }

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would create configuration profile" -ForegroundColor Magenta
        return "whatif-profile-id"
    }

    # Defender Antivirus configuration
    $profileParams = @{
        "@odata.type" = "#microsoft.graph.windows10EndpointProtectionConfiguration"
        displayName = $ConfigProfileName
        description = "Configure Defender real-time protection and cloud protection"
        # Defender settings
        defenderBlockOnAccessProtection = $true
        defenderCloudBlockLevel = "high"
        defenderCloudExtendedTimeout = 50
        defenderMonitorFileActivity = "monitorAllFiles"
        defenderScanArchiveFiles = $true
        defenderScanDownloads = $true
        defenderScanIncomingMail = $true
        defenderScanScriptsLoadedInInternetExplorer = $true
        defenderSignatureUpdateIntervalInHours = 4
    }

    $profile = Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($profileParams | ConvertTo-Json -Depth 10)
    Write-Host "  Created profile (ID: $($profile.id))" -ForegroundColor Green

    # Assign to group
    if ($GroupId -and $GroupId -ne "whatif-group-id") {
        Write-Host "  Assigning to group..." -ForegroundColor Gray
        $assignUri = "$uri/$($profile.id)/assign"
        $assignParams = @{
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $GroupId
                    }
                }
            )
        }
        Invoke-MgGraphRequest -Uri $assignUri -Method POST -Body ($assignParams | ConvertTo-Json -Depth 10)
        Write-Host "  Assigned to $DeviceGroupName" -ForegroundColor Green
    }

    return $profile.id
}

function Assign-ScriptToGroup {
    param(
        [string]$ScriptId,
        [string]$GroupId
    )

    Write-Step "Assigning script to group"

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would assign script to group" -ForegroundColor Magenta
        return
    }

    if ($ScriptId -eq "whatif-script-id" -or $GroupId -eq "whatif-group-id") {
        return
    }

    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$ScriptId/assign"

    $assignParams = @{
        deviceManagementScriptAssignments = @(
            @{
                target = @{
                    "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                    groupId = $GroupId
                }
            }
        )
    }

    Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($assignParams | ConvertTo-Json -Depth 10)
    Write-Host "  Assigned $ScriptName to $DeviceGroupName" -ForegroundColor Green
}

function Show-Summary {
    Write-Step "Setup complete!"
    Write-Host @"

  Configuration applied:
  - Dynamic device group: $DeviceGroupName
  - Device script: $ScriptName (removes SetupAdmin after enrollment)
  - Compliance policy: $CompliancePolicyName
  - Configuration profile: $ConfigProfileName

  Next steps:
  1. Build the Windows ISO: ./scripts/build-iso.sh
  2. Create a VM with the ISO
  3. Sign in with a licensed user to enroll
  4. Device will auto-join the group and receive policies

"@ -ForegroundColor Cyan
}

# Main execution
try {
    Write-Host "`n=== Intune Lab Setup ===" -ForegroundColor Cyan
    Write-Host "Tenant: $TenantDomain"

    if ($WhatIf) {
        Write-Host "[WhatIf mode - no changes will be made]" -ForegroundColor Magenta
    }

    Connect-ToGraph

    $groupId = New-DynamicDeviceGroup
    $scriptId = Add-DeviceManagementScript

    Assign-ScriptToGroup -ScriptId $scriptId -GroupId $groupId

    Add-CompliancePolicy -GroupId $groupId
    Add-ConfigurationProfile -GroupId $groupId

    Show-Summary
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
