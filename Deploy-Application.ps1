<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
	Deploy-Application.ps1
.EXAMPLE
	Deploy-Application.ps1 -DeployMode 'Silent'
.EXAMPLE
	Deploy-Application.ps1 -AllowRebootPassThru -AllowDefer
.EXAMPLE
	Deploy-Application.ps1 -DeploymentType Uninstall
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
	[Parameter(Mandatory=$false)][ValidateSet('Install','Uninstall')][string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)][ValidateSet('Interactive','Silent','NonInteractive')][string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)][switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)][switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)][switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}
	
	##* Do not modify section below
	#region DoNotModify
	
	## Variables: Exit Code
	[int32]$mainExitCode = 0
	
	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.6.5'
	[string]$deployAppScriptDate = '08/17/2015'
	[hashtable]$deployAppScriptParameters = $psBoundParameters
	
	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent
	
	#endregion DoNotModify
	##* Do not modify section above
	
	##*===============================================
	##* REFERENCES
	##*===============================================
	##	http://www.applicationsdownloadpage.com
	##	 - document any non-standard msi parameters or executable switches
	
	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Company' #optional
	[string]$appName = 'Application Name' #required (only leave blank to trigger $useDefaultMSI = $true)
	[string]$appVersion = '3.21.0' #optional
	[string]$appArch = 'x64' #optional (x86 or x64)
	[string]$appLang = '' #optional
	[string]$appRevision = '' #optional
	[string]$appScriptVersion = '1.0.0' #required
	[string]$appScriptDate = 'dd/MM/yyyy' #required
	[string]$appScriptAuthor = 'Firstname Surname - UQBS IS Team' #optional
	##*===============================================
	
	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}
	
	##*===============================================
	##* VARIABLE DECLARATION - CUSTOM
	##*===============================================
	## Variables not included in default PSAppDeployToolkit
	[string]$appVersionFull = '' #optional (useful for $appInstaller when naming does not use $appVersion)
	[string]$appInstaller = "" #required (can be either .exe, .msi or .msp)
	[string]$appInstallerParams = '/passive /norestart' #optional (if /S for exe be careful of required capitalisation)
	[string]$closeApps = 'process1,"process 2",process3' #optional (Process "Name" as it appears in Get-Process)
	[string]$stopServices = '' #optional (Service "Name" as it appears in Get-Service)
	[string]$UninstallNameOrProductCode = ''	#optional (eg. 'adobe reader' or '{56F691FC-E126-4620-A1B9-F2ED86C267D3}')
	[switch]$UseSpecifiedUninstaller = $false #optional or $true if(specify $UninstallNameOrProductCode as custom uninstall string, and optionally provide $UninstallerParams)
	[switch]$WildcardMatch = $false #optional (do not use with $ExactMatch = $true) (must specify * in desired place in $UninstallNameOrProductCode)
	[switch]$ExactMatch = $false #optional (do not use with $WildcardMatch = $true)
	[string]$UninstallerParams = '' #optional (specify custom parameters to pass to the UninstallSoftwareByQuery function)
	[string]$suppressNotifications = $true	#if $true will not show dialog boxes with messages
	
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================
	
	If ($deploymentType -ine 'Uninstall') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'
		
		## Stop running services
		if($stopServices -ine ''){
			foreach ($serviceToStop in $stopServices) {
				Stop-ServiceAndDependencies -Name $serviceToStop
			}
		}
		
		## Show Welcome Message
		if($closeApps -ine ''){
			# -CloseAppsCountdown (only takes effect if deferral is not allowed or has expired)
			# -CheckDiskSpace (required disk space is calculated automatically based on the size of the script source and associated files)
			# -RequiredDiskSpace <Int32> (Specify required disk space in MB, used in combination with CheckDiskSpace)
			Show-InstallationWelcome -CloseApps $closeApps -CloseAppsCountdown 5400 -PromptToSave -AllowDeferCloseApps -DeferTimes 8 -CheckDiskSpace -MinimizeWindows $false
		}else{
			Show-InstallationWelcome -AllowDefer -DeferTimes 8 -MinimizeWindows $false
		}
		
		if(!($suppressNotifications -eq $true)){
			## Show Progress Message (with the default message)
			Show-InstallationProgress
		}
		
		## <Perform Pre-Installation tasks here>
			#Example:  Remove-File -Path "C:\Users\Public\Desktop\DummyShortcut.lnk" 
			#Example:  Remove-File -Path "C:\ProgramData\DummyDir" -Recurse
			#Example:  Remove-Folder -Path "C:\ProgramData\DummyDir"
			#Example:  Set-RegistryKey -Key "HKLM:SOFTWARE\Policies\Google\Update" -Name AutoUpdateCheckPeriodMinutes -Type DWord -Value 0
			#Example:  Copy-File -Path "$dirSupportFiles\Skins\" -Destination "C:\Program Files\Miranda NG\" -Recurse
			#Example:  Copy-File -Path "$dirSupportFiles\autoexec_sounds.ini" -Destination "C:\Program Files\Miranda NG\"
			# Write-Log Severity Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
			#Write-Log -Message "write your own text" -LogType CMTrace -Severity 2
		#### comment/uncomment uninstallation block as required ####
		<#
		if ($UninstallNameOrProductCode -ine '') {
			if ($UseSpecifiedUninstaller -eq $true) {
				if ($UninstallerParams -ine '') {
					UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams -UseSpecifiedUninstaller
				} else {
					UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -UseSpecifiedUninstaller
				}
			} else {
				if ($WildcardMatch -eq $true) {
					if ($UninstallerParams -ine '') {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams -Wildcard
					} else {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Wildcard
					}
				} elseif ($ExactMatch -eq $true) {
					if ($UninstallerParams -ine '') {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams -Exact
					} else {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Exact
					}
				} else {
					if ($UninstallerParams -ine '') {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams
					} else {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode
					}
				}
			}
		}
		#>
		
		##*===============================================
		##* INSTALLATION 
		##*===============================================
		[string]$installPhase = 'Installation'
		
		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		} else {
			## <Perform Installation tasks here>
			if ($appInstaller -imatch "`.msi") {
				if($appInstallerParams){
					Execute-MSI -Path "$dirFiles\$appInstaller" -Parameters $appInstallerParams
				}else{
					Execute-MSI -Path "$dirFiles\$appInstaller"
				}
			}
			if ($appInstaller -imatch "`.msp") {
				if($appInstallerParams){
					Execute-MSI -Action Patch -Path "$dirFiles\$appInstaller" -Parameters $appInstallerParams
				}else{
					Execute-MSI -Action Patch -Path "$dirFiles\$appInstaller"
				}
			}
			if ($appInstaller -imatch "`.exe") {
				if($appInstallerParams){
					Execute-Process -Path "$dirFiles\$appInstaller" -Parameters $appInstallerParams
				}else{
					Execute-Process -Path "$dirFiles\$appInstaller"
				}
			}
		}
		
		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'
		
		## <Perform Post-Installation tasks here>
			#Example:  Remove-File -Path "C:\Users\Public\Desktop\DummyShortcut.lnk" 
			#Example:  Remove-File -Path "C:\ProgramData\DummyDir" -Recurse
			#Example:  Remove-Folder -Path "C:\ProgramData\DummyDir"
			#Example:  Set-RegistryKey -Key "HKLM:SOFTWARE\Policies\Google\Update" -Name AutoUpdateCheckPeriodMinutes -Type DWord -Value 0
			#Example:  Copy-File -Path "$dirSupportFiles\Skins\" -Destination "C:\Program Files\Miranda NG\" -Recurse
			#Example:  Copy-File -Path "$dirSupportFiles\autoexec_sounds.ini" -Destination "C:\Program Files\Miranda NG\"
			# Write-Log Severity Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
			#Write-Log -Message "write your own text" -LogType CMTrace -Severity 2
		
		$PublicDesktop = "$env:PUBLIC\Desktop"
		<#
		If (Test-Path -Path "$PublicDesktop\DummyShortcut.lnk") {
			Remove-File -Path "$PublicDesktop\DummyShortcut.lnk"
		}
		#>
		
		if(!($suppressNotifications -eq $true)){
			## Display a message at the end of the install
			$installationPromptMessage = "Software Deployment script has completed.`n`nIf you notice any errors or experience issues with this package please report it to the IT Helpdesk by sending an email to `n`nhelpdesk@business.uq.edu.au`n`n with a screenshot and/or as much information as you can.`n`n`nWarm regards, UQBS IS Team"
			If (-not $useDefaultMsi) { Show-InstallationPrompt -Message $installationPromptMessage -ButtonRightText 'OK' -Icon Information -NoWait }
		}
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'
		
		## Stop running services
		if($stopServices -ine ''){
			foreach ($serviceToStop in $stopServices) {
				Stop-ServiceAndDependencies -Name $serviceToStop
			}
		}
		
		if ($closeApps -ine '') {
			Show-InstallationWelcome -CloseApps $closeApps
		}
		
		if(!($suppressNotifications -eq $true)){
			## Show Progress Message (with the default message)
			Show-InstallationProgress
		}
		
		## <Perform Pre-Uninstallation tasks here>
			#Example:  Remove-File -Path "C:\Users\Public\Desktop\DummyShortcut.lnk" 
			#Example:  Remove-File -Path "C:\ProgramData\DummyDir" -Recurse
			#Example:  Remove-Folder -Path "C:\ProgramData\DummyDir"
			#Example:  Set-RegistryKey -Key "HKLM:SOFTWARE\Policies\Google\Update" -Name AutoUpdateCheckPeriodMinutes -Type DWord -Value 0
			#Example:  Copy-File -Path "$dirSupportFiles\Skins\" -Destination "C:\Program Files\Miranda NG\" -Recurse
			#Example:  Copy-File -Path "$dirSupportFiles\autoexec_sounds.ini" -Destination "C:\Program Files\Miranda NG\"
			# Write-Log Severity Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
			#Write-Log -Message "write your own text" -LogType CMTrace -Severity 2
		
		
		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'
		
		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		} else {
			## <Perform Uninstallation tasks here>
			if ($UninstallNameOrProductCode -ine '') {
				if ($UseSpecifiedUninstaller -eq $true) {
					if ($UninstallerParams -ine '') {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams -UseSpecifiedUninstaller
					} else {
						UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -UseSpecifiedUninstaller
					}
				} else {
					if ($WildcardMatch -eq $true) {
						if ($UninstallerParams -ine '') {
							UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams -Wildcard
						} else {
							UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Wildcard
						}
					} elseif ($ExactMatch -eq $true) {
						if ($UninstallerParams -ine '') {
							UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams -Exact
						} else {
							UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Exact
						}
					} else {
						if ($UninstallerParams -ine '') {
							UninstallSoftwareByQuery -Query $UninstallNameOrProductCode -Parameters $UninstallerParams
						} else {
							UninstallSoftwareByQuery -Query $UninstallNameOrProductCode
						}
					}
				}
			}
		}
		
		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'
		
		## <Perform Post-Uninstallation tasks here>
			#Example:  Remove-File -Path "C:\Users\Public\Desktop\DummyShortcut.lnk" 
			#Example:  Remove-File -Path "C:\ProgramData\DummyDir" -Recurse
			#Example:  Remove-Folder -Path "C:\ProgramData\DummyDir"
			#Example:  Set-RegistryKey -Key "HKLM:SOFTWARE\Policies\Google\Update" -Name AutoUpdateCheckPeriodMinutes -Type DWord -Value 0
			#Example:  Copy-File -Path "$dirSupportFiles\Skins\" -Destination "C:\Program Files\Miranda NG\" -Recurse
			#Example:  Copy-File -Path "$dirSupportFiles\autoexec_sounds.ini" -Destination "C:\Program Files\Miranda NG\"
			# Write-Log Severity Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
			#Write-Log -Message "write your own text" -LogType CMTrace -Severity 2
		
		
	}
	
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================
	
	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}