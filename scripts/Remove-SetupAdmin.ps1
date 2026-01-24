# Remove-SetupAdmin.ps1
# Deploy via Intune: Devices > Scripts and remediations > Platform scripts
#
# Purpose: Remove the temporary SetupAdmin local account after Entra ID enrollment.
# The SetupAdmin account is created by Autounattend.xml for initial OOBE bypass,
# but should be removed post-enrollment to avoid lingering admin credentials.
#
# Intune deployment settings:
#   - Run this script using the logged on credentials: No
#   - Run script in 64 bit PowerShell Host: Yes
#   - Enforce script signature check: No (or sign the script)

$AccountName = "SetupAdmin"

try {
    $user = Get-LocalUser -Name $AccountName -ErrorAction Stop
    Remove-LocalUser -Name $AccountName -ErrorAction Stop
    Write-Output "Successfully removed local account: $AccountName"
    exit 0
}
catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
    Write-Output "Account '$AccountName' does not exist - no action needed"
    exit 0
}
catch {
    Write-Error "Failed to remove account '$AccountName': $_"
    exit 1
}
