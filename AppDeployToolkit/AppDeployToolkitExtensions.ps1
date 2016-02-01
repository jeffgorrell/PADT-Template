<#
.SYNOPSIS
	This script is a template that allows you to extend the toolkit with your own custom functions.
.DESCRIPTION
	The script is automatically dot-sourced by the AppDeployToolkitMain.ps1 script.
.NOTES
    Toolkit Exit Code Ranges:
    60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
    69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
    70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK 
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
)

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

# Variables: Script
[string]$appDeployToolkitExtName = 'PSAppDeployToolkitExt'
[string]$appDeployExtScriptFriendlyName = 'App Deploy Toolkit Extensions'
[version]$appDeployExtScriptVersion = [version]'1.5.0'
[string]$appDeployExtScriptDate = '06/11/2015'
[hashtable]$appDeployExtScriptParameters = $PSBoundParameters

##*===============================================
##* FUNCTION LISTINGS
##*===============================================

# <Your custom functions go here>

function UninstallSoftwareByQuery {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true)]
		[string]$Query,
		[Parameter(Mandatory=$false)]
		[switch]$Exact = $false,
		[Parameter(Mandatory=$false)]
		[switch]$WildCard = $false,
		[Parameter(Mandatory=$false)]
		[switch]$UseSpecifiedUninstaller = $false,
		[Parameter(Mandatory=$false)]
		[string]$Parameters
	)
	try {
		if ($UseSpecifiedUninstaller) {
			if($Parameters){
				Execute-Process -Path $Query -Parameters $Parameters
			} else {
				Execute-Process -Path $Query
			}
		} else {
			# if $Query starts with opening curly brace uninstall by product code, else search registry by name keyword and return uninstall strings
			if ($Query.StartsWith('{')) {
				if ($Parameters) {
					Execute-MSI -Action Uninstall -Path $Query -Parameters $Parameters
				} else {
					Execute-MSI -Action Uninstall -Path $Query
				}
			} else {
				if($Exact){
					$installedApplicationUninstallStrings = Get-InstalledApplication $Query -Exact | select "UninstallString" -expand "UninstallString"
				}elseif($WildCard){
					$installedApplicationUninstallStrings = Get-InstalledApplication $Query -WildCard | select "UninstallString" -expand "UninstallString"
				}else{
					$installedApplicationUninstallStrings = Get-InstalledApplication $Query | select "UninstallString" -expand "UninstallString"
				}
				if($installedApplicationUninstallStrings){
					foreach ($uninstallString in $installedApplicationUninstallStrings){
						# Check for any MSI uninstall strings
						if ($uninstallString -imatch "MsiExec.exe") {
							if ($Parameters) {
								Remove-MSIApplications $Query -Parameters $Parameters
							} else {
								Remove-MSIApplications $Query
							}
						} else {
							$uninstallStringExe,$uninstallStringParams = $uninstallString -isplit "`.exe"
							$uninstallStringExe = $uninstallStringExe + "`.exe"
							if ($Parameters) {
								Execute-Process -Path $uninstallStringExe -Parameters $Parameters
							} else {
								if($uninstallStringParams){
									$uninstallStringParams = $uninstallStringParams.TrimStart()
									Execute-Process -Path $uninstallStringExe -Parameters $uninstallStringParams
								} else {
									Execute-Process -Path $uninstallStringExe
								}
							}
						}
					}
				}else{
					Write-Log -Message "Registry query did not return any results for `"$Query`"" -Severity 2 -LogType CMTrace
				}
			}
		}
	}
	catch {
		if ($Parameters) {
			Write-Log -Message "Problem with custom uninstallation; query passed is `"$Query`" and parameters passed is `"$Parameters`"" -Severity 3 -LogType CMTrace
		} else {
			Write-Log -Message "Problem with custom uninstallation; query passed is `"$Query`"" -Severity 3 -LogType CMTrace
		}
	}
}

##*===============================================
##* END FUNCTION LISTINGS
##*===============================================

##*===============================================
##* SCRIPT BODY
##*===============================================

If ($scriptParentPath) {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] dot-source invoked by [$(((Get-Variable -Name MyInvocation).Value).ScriptName)]" -Source $appDeployToolkitExtName
}
Else {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] invoked directly" -Source $appDeployToolkitExtName
}

##*===============================================
##* END SCRIPT BODY
##*===============================================