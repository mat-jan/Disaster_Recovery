<#
.SYNOPSIS
    Script to export the last successful backup from Hornet Security VM Backup FREE to a network share
.DESCRIPTION
    The script uses PowerShell Cmdlets from Hornet Security VM Backup to retrieve the VM list,
    find the last successful backup and copy it to a network share.
    
    Works with the free FREE Edition!
.NOTES
    Requires running on a server with Hornet Security VM Backup installed
    Script must be run as Administrator
#>

# ==================== CONFIGURATION ====================

# Virtual machine name to export (EXACT name from VM Backup!)
$VMName = "Your-VM-Name"  # CHANGE TO YOUR VM NAME!

# Authentication credentials for local VM Backup server
$VMBackupUsername = "Administrator"  # User with administrator privileges
$VMBackupDomain = $env:COMPUTERNAME  # Domain or computer name

# Network share path
$NetworkShare = "\\192.168.1.100\backups$"  # CHANGE TO YOUR PATH

# Network share authentication
# If the user running the script ALREADY HAS ACCESS to the share, set to $false
$RequireNetworkAuth = $false  # set $true if you need to provide different login credentials

# Network share credentials (only when $RequireNetworkAuth = $true)
$NetworkUsername = "DOMAIN\user"      # CHANGE TO YOUR USERNAME
$NetworkPassword = "YourPassword123"   # CHANGE TO YOUR PASSWORD

# Path to VM Backup cmdlets
$CmdletsPath = "C:\Program Files\Hornetsecurity\VMBackup\Cmdlets"

# Create ZIP archive (recommended for large backups)
$CreateZipArchive = $false  # set $true if you want ZIP

# Automatic mode (no user interaction)
$AutomaticMode = $true  # set $false if you want manual selection

# ==================== FUNCTIONS ====================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-VMBackupInstallation {
    if (-not (Test-Path $CmdletsPath)) {
        Write-ColorOutput "ERROR: VM Backup cmdlets not found in: $CmdletsPath" "Red"
        Write-ColorOutput "Check if VM Backup is installed and if the path is correct" "Yellow"
        return $false
    }
    
    # Check if service is running (for version 9.1+)
    $service = Get-Service -Name "Hornetsecurity.VMBackup" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        Write-ColorOutput "WARNING: VM Backup service is not running. Attempting to start..." "Yellow"
        try {
            Start-Service -Name "Hornetsecurity.VMBackup"
            Start-Sleep -Seconds 3
            Write-ColorOutput "Service started successfully" "Green"
        }
        catch {
            Write-ColorOutput "Cannot start service: $_" "Red"
            return $false
        }
    }
    
    return $true
}

function Start-VMBackupSession {
    Write-ColorOutput "`nLogging into VM Backup..." "Cyan"
    
    $startSessionScript = Join-Path $CmdletsPath "StartSessionPasswordHidden.ps1"
    
    if (-not (Test-Path $startSessionScript)) {
        Write-ColorOutput "ERROR: StartSessionPasswordHidden.ps1 script not found" "Red"
        return $null
    }
    
    try {
        # Call cmdlet to start session
        $result = & $startSessionScript -username $VMBackupUsername -domain $VMBackupDomain
        
        if ($result -and $result.SessionToken) {
            Write-ColorOutput "Logged in successfully! Token: $($result.SessionToken)" "Green"
            return $result.SessionToken
        }
        else {
            Write-ColorOutput "Login error - no token in response" "Red"
            return $null
        }
    }
    catch {
        Write-ColorOutput "Error during login: $_" "Red"
        return $null
    }
}

function Get-VMBackupList {
    param([string]$SessionToken)
    
    Write-ColorOutput "`nRetrieving virtual machine list..." "Cyan"
    
    $getVMsScript = Join-Path $CmdletsPath "GetVMs.ps1"
    
    try {
        $result = & $getVMsScript -sessiontoken $SessionToken
        
        if ($result -and $result.VirtualMachines) {
            Write-ColorOutput "Found $($result.VirtualMachines.Count) virtual machine(s)" "Green"
            return $result.VirtualMachines
        }
        else {
            Write-ColorOutput "No virtual machines found" "Yellow"
            return $null
        }
    }
    catch {
        Write-ColorOutput "Error retrieving VM list: $_" "Red"
        return $null
    }
}

function Get-VMBackupHistory {
    param(
        [string]$SessionToken,
        [string]$VMRef
    )
    
    $getHistoryScript = Join-Path $CmdletsPath "GetBackupHistory.ps1"
    
    try {
        $result = & $getHistoryScript -sessiontoken $SessionToken -vmref $VMRef
        
        if ($result -and $result.BackupHistory) {
            # Filter only successful backups
            $successfulBackups = $result.BackupHistory | Where-Object { $_.Result -eq "Success" }
            
            if ($successfulBackups) {
                # Sort by date and return the latest
                $latestBackup = $successfulBackups | Sort-Object -Property TimeStamp -Descending | Select-Object -First 1
                return $latestBackup
            }
        }
        
        return $null
    }
    catch {
        Write-ColorOutput "Error retrieving backup history: $_" "Red"
        return $null
    }
}

function Get-BackupLocation {
    param([string]$SessionToken)
    
    $getLocationsScript = Join-Path $CmdletsPath "GetBackupLocations.ps1"
    
    try {
        $result = & $getLocationsScript -sessiontoken $SessionToken
        
        if ($result -and $result.BackupLocations) {
            return $result.BackupLocations[0].Path
        }
        
        return $null
    }
    catch {
        Write-ColorOutput "Error retrieving backup location: $_" "Red"
        return $null
    }
}

function Copy-BackupToNetwork {
    param(
        [string]$SourcePath,
        [string]$DestinationShare,
        [string]$VMName,
        [string]$NetUser,
        [string]$NetPass,
        [bool]$CreateZip,
        [bool]$RequireAuth
    )
    
    try {
        # Create folder name with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $destinationFolder = "${VMName}_${timestamp}"
        
        # Map network share only if required
        if ($RequireAuth) {
            Write-ColorOutput "`nConnecting to network share (with authentication)..." "Cyan"
            $netCmd = "net use `"$DestinationShare`" `"$NetPass`" /user:`"$NetUser`""
            Invoke-Expression $netCmd | Out-Null
            
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
                throw "Cannot connect to network share (error code: $LASTEXITCODE)"
            }
            
            Write-ColorOutput "Connected to network share" "Green"
        }
        else {
            Write-ColorOutput "`nUsing existing user permissions..." "Cyan"
            
            # Check if share is accessible
            if (-not (Test-Path $DestinationShare)) {
                throw "Cannot access share: $DestinationShare. Check permissions or set RequireNetworkAuth = `$true"
            }
            
            Write-ColorOutput "Network share access confirmed" "Green"
        }
        
        $fullDestPath = Join-Path $DestinationShare $destinationFolder
        
        if ($CreateZip) {
            # Create ZIP archive
            Write-ColorOutput "`nCreating ZIP archive..." "Cyan"
            $zipPath = "$fullDestPath.zip"
            
            Add-Type -Assembly "System.IO.Compression.FileSystem"
            [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $zipPath, "Optimal", $false)
            
            Write-ColorOutput "ZIP archive created: $zipPath" "Green"
            $exportedPath = $zipPath
        }
        else {
            # Copy folder directly
            Write-ColorOutput "`nCopying backup files..." "Cyan"
            Write-ColorOutput "Source: $SourcePath" "Gray"
            Write-ColorOutput "Destination: $fullDestPath" "Gray"
            
            # Get backup size
            $sourceSize = (Get-ChildItem -Path $SourcePath -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
            Write-ColorOutput "Backup size: $([math]::Round($sourceSize, 2)) GB" "Gray"
            
            Copy-Item -Path $SourcePath -Destination $fullDestPath -Recurse -Force
            
            Write-ColorOutput "Files copied successfully" "Green"
            $exportedPath = $fullDestPath
        }
        
        # Disconnect share only if it was mapped
        if ($RequireAuth) {
            net use $DestinationShare /delete /y | Out-Null
        }
        
        return $exportedPath
    }
    catch {
        Write-ColorOutput "Error during copy: $_" "Red"
        
        # Try to disconnect share in case of error (only if it was mapped)
        if ($RequireAuth) {
            try { net use $DestinationShare /delete /y | Out-Null } catch { }
        }
        
        return $null
    }
}

function Stop-VMBackupSession {
    param([string]$SessionToken)
    
    $endSessionScript = Join-Path $CmdletsPath "EndSession.ps1"
    
    try {
        & $endSessionScript -sessiontoken $SessionToken | Out-Null
        Write-ColorOutput "`nAPI session closed successfully" "Green"
    }
    catch {
        Write-ColorOutput "Warning: Failed to close API session" "Yellow"
    }
}

# ==================== MAIN LOGIC ====================

Clear-Host
Write-ColorOutput "=========================================" "Cyan"
Write-ColorOutput " Hornet Security VM Backup - Exporter" "Cyan"
Write-ColorOutput "   Free Edition Compatible" "Cyan"
Write-ColorOutput "=========================================" "Cyan"

# Check installation
if (-not (Test-VMBackupInstallation)) {
    exit 1
}

# Change working directory to cmdlets
Push-Location $CmdletsPath

try {
    # Start session
    $sessionToken = Start-VMBackupSession
    
    if (-not $sessionToken) {
        Write-ColorOutput "`nCannot start session. Check login credentials." "Red"
        exit 1
    }
    
    # Get VM list
    $vms = Get-VMBackupList -SessionToken $sessionToken
    
    if (-not $vms -or $vms.Count -eq 0) {
        Write-ColorOutput "`nNo virtual machines found in configuration." "Red"
        Stop-VMBackupSession -SessionToken $sessionToken
        exit 1
    }
    
    # Select VM - automatic or manual
    $selectedVM = $null
    
    if ($AutomaticMode -and $VMName) {
        # Automatic mode - find VM by name
        Write-ColorOutput "`nAutomatic mode: Looking for machine '$VMName'..." "Cyan"
        
        $selectedVM = $vms | Where-Object { $_.Name -eq $VMName }
        
        if (-not $selectedVM) {
            Write-ColorOutput "`nMachine not found with name: $VMName" "Red"
            Write-ColorOutput "Available machines:" "Yellow"
            foreach ($vm in $vms) {
                Write-ColorOutput "  - $($vm.Name)" "Gray"
            }
            Stop-VMBackupSession -SessionToken $sessionToken
            exit 1
        }
        
        Write-ColorOutput "Found machine: $($selectedVM.Name)" "Green"
    }
    else {
        # Manual mode - display list for selection
        Write-ColorOutput "`n=========================================" "Cyan"
        Write-ColorOutput "Available virtual machines:" "Cyan"
        Write-ColorOutput "=========================================" "Cyan"
        
        for ($i = 0; $i -lt $vms.Count; $i++) {
            $vm = $vms[$i]
            Write-Host "[$i] " -NoNewline -ForegroundColor Yellow
            Write-Host "$($vm.Name)" -NoNewline
            Write-Host " ($($vm.Type))" -ForegroundColor Gray
        }
        
        # Select VM
        Write-Host "`n"
        $vmIndex = Read-Host "Select virtual machine number to export [0-$($vms.Count-1)]"
        
        if ([int]$vmIndex -lt 0 -or [int]$vmIndex -ge $vms.Count) {
            Write-ColorOutput "Invalid selection!" "Red"
            Stop-VMBackupSession -SessionToken $sessionToken
            exit 1
        }
        
        $selectedVM = $vms[$vmIndex]
        Write-ColorOutput "`nSelected: $($selectedVM.Name)" "Green"
    }
    
    # Get last successful backup
    Write-ColorOutput "`nSearching for last successful backup..." "Cyan"
    $lastBackup = Get-VMBackupHistory -SessionToken $sessionToken -VMRef $selectedVM.AltaroVirtualMachineRef
    
    if (-not $lastBackup) {
        Write-ColorOutput "`nNo successful backup found for this machine!" "Red"
        Write-ColorOutput "Make sure the backup for this machine has been performed and completed successfully." "Yellow"
        Stop-VMBackupSession -SessionToken $sessionToken
        exit 1
    }
    
    Write-ColorOutput "`nFound last successful backup:" "Green"
    Write-ColorOutput "  Date: $($lastBackup.TimeStamp)" "Gray"
    Write-ColorOutput "  Type: $($lastBackup.Type)" "Gray"
    
    # Get backup location
    $backupLocation = Get-BackupLocation -SessionToken $sessionToken
    
    if (-not $backupLocation) {
        Write-ColorOutput "`nCannot retrieve backup location!" "Red"
        Stop-VMBackupSession -SessionToken $sessionToken
        exit 1
    }
    
    Write-ColorOutput "`nBackup location: $backupLocation" "Gray"
    
    # Construct path to VM backup
    # Structure: BackupLocation\VMName\
    $vmBackupPath = Join-Path $backupLocation $selectedVM.Name
    
    if (-not (Test-Path $vmBackupPath)) {
        Write-ColorOutput "`nBackup directory not found: $vmBackupPath" "Red"
        Stop-VMBackupSession -SessionToken $sessionToken
        exit 1
    }
    
    Write-ColorOutput "Found backup directory: $vmBackupPath" "Green"
    
    # Display contents
    $backupFiles = Get-ChildItem -Path $vmBackupPath -Recurse
    $totalSize = ($backupFiles | Measure-Object -Property Length -Sum).Sum / 1GB
    Write-ColorOutput "Number of files: $($backupFiles.Count)" "Gray"
    Write-ColorOutput "Total size: $([math]::Round($totalSize, 2)) GB" "Gray"
    
    # Confirm export only in manual mode
    if (-not $AutomaticMode) {
        Write-Host "`n"
        $confirm = Read-Host "Do you want to export this backup to $NetworkShare? (Y/N)"
        
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-ColorOutput "Cancelled." "Yellow"
            Stop-VMBackupSession -SessionToken $sessionToken
            exit 0
        }
    }
    else {
        Write-ColorOutput "`nAutomatic mode - starting export..." "Cyan"
    }
    
    # Copy backup
    $exportedPath = Copy-BackupToNetwork `
        -SourcePath $vmBackupPath `
        -DestinationShare $NetworkShare `
        -VMName $selectedVM.Name `
        -NetUser $NetworkUsername `
        -NetPass $NetworkPassword `
        -CreateZip $CreateZipArchive `
        -RequireAuth $RequireNetworkAuth
    
    # End session
    Stop-VMBackupSession -SessionToken $sessionToken
    
    # Summary
    Write-ColorOutput "`n=========================================" "Cyan"
    if ($exportedPath) {
        Write-ColorOutput "✓ SUCCESS! Backup has been exported" "Green"
        Write-ColorOutput "=========================================" "Cyan"
        Write-ColorOutput "Machine: $($selectedVM.Name)" "White"
        Write-ColorOutput "Backup date: $($lastBackup.TimeStamp)" "White"
        Write-ColorOutput "Location: $exportedPath" "White"
    }
    else {
        Write-ColorOutput "✗ ERROR! Export failed" "Red"
        Write-ColorOutput "=========================================" "Cyan"
    }
}
catch {
    Write-ColorOutput "`nUnexpected error: $_" "Red"
    Write-ColorOutput $_.ScriptStackTrace "Gray"
}
finally {
    # Return to previous directory
    Pop-Location
}

Write-Host "`n"
