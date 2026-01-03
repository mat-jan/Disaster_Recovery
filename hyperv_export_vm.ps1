<#
.SYNOPSIS
    Script to export Hyper-V virtual machine using VSS snapshot or live export
.DESCRIPTION
    Exports a Hyper-V VM to a network share (NAS) using VSS snapshot for consistent backup
    or live export if the VM is running. Compatible with the Proxmox import workflow.
.NOTES
    Must be run as Administrator on a Hyper-V host
    Requires Hyper-V PowerShell module
#>

# --- CONFIGURATION ---
$VMName = "YourVMName"                              # Name of the VM to export
$ExportPath = "\\192.168.1.100\nas_backup\b1"      # Export destination path (NAS share)
$UseVSS = $true                                      # Use VSS snapshot for consistent backup
$UseLastSnapshot = $true                             # Use last checkpoint/snapshot instead of live VM (recommended)
$RemoveOldExport = $true                             # Remove old exports created by THIS script
$ExportPrefix = "HyperV_Export"                      # Prefix for export folders (for identification)

# Network share authentication (if needed)
# If running as domain admin with NAS access, set to $false
$RequireNetworkAuth = $false                         # Set $true if authentication needed
$NetworkUsername = "DOMAIN\user"                     # Network share username (only if RequireNetworkAuth = $true)
$NetworkPassword = "YourPassword123"                 # Network share password (only if RequireNetworkAuth = $true)
# --------------------

# --- FUNCTIONS ---

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Connect-NetworkShare {
    param(
        [string]$SharePath,
        [string]$Username,
        [string]$Password,
        [bool]$RequireAuth
    )
    
    if ($RequireAuth) {
        Write-ColorOutput "Connecting to network share (with authentication)..." "Cyan"
        $netCmd = "net use `"$SharePath`" `"$Password`" /user:`"$Username`""
        Invoke-Expression $netCmd | Out-Null
        
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
            throw "Cannot connect to network share (error code: $LASTEXITCODE)"
        }
        
        Write-ColorOutput "Connected to network share" "Green"
    }
    else {
        Write-ColorOutput "Using existing user permissions..." "Cyan"
        
        # Check if share is accessible
        if (-not (Test-Path $SharePath)) {
            throw "Cannot access share: $SharePath. Check permissions or set RequireNetworkAuth = `$true"
        }
        
        Write-ColorOutput "Network share access confirmed" "Green"
    }
}

function Disconnect-NetworkShare {
    param(
        [string]$SharePath,
        [bool]$RequireAuth
    )
    
    if ($RequireAuth) {
        try {
            net use $SharePath /delete /y | Out-Null
        }
        catch {
            Write-ColorOutput "Warning: Could not disconnect network share" "Yellow"
        }
    }
}

function Get-VMInfo {
    param([string]$Name)
    
    try {
        $vm = Get-VM -Name $Name -ErrorAction Stop
        
        # Get checkpoints/snapshots
        $checkpoints = Get-VMSnapshot -VMName $Name -ErrorAction SilentlyContinue
        
        return @{
            VM = $vm
            Checkpoints = $checkpoints
        }
    }
    catch {
        throw "VM '$Name' not found on this Hyper-V host"
    }
}

function Export-HyperVVM {
    param(
        [string]$VMName,
        [string]$DestinationPath,
        [bool]$UseVSS,
        [bool]$UseSnapshot,
        [bool]$RemoveOld,
        [string]$Prefix
    )
    
    $vmInfo = Get-VMInfo -Name $VMName
    $vm = $vmInfo.VM
    $checkpoints = $vmInfo.Checkpoints
    
    Write-ColorOutput "`nVM Information:" "Cyan"
    Write-ColorOutput "  Name: $($vm.Name)" "Gray"
    Write-ColorOutput "  State: $($vm.State)" "Gray"
    Write-ColorOutput "  Generation: $($vm.Generation)" "Gray"
    Write-ColorOutput "  Memory: $([math]::Round($vm.MemoryAssigned / 1GB, 2)) GB" "Gray"
    
    # Check for snapshots
    if ($checkpoints -and $checkpoints.Count -gt 0) {
        Write-ColorOutput "  Checkpoints found: $($checkpoints.Count)" "Yellow"
        
        # Get latest checkpoint
        $latestCheckpoint = $checkpoints | Sort-Object -Property CreationTime -Descending | Select-Object -First 1
        Write-ColorOutput "  Latest checkpoint: $($latestCheckpoint.Name)" "Gray"
        Write-ColorOutput "  Created: $($latestCheckpoint.CreationTime)" "Gray"
        
        if ($UseSnapshot) {
            Write-ColorOutput "`nUsing latest checkpoint for export (recommended for consistency)" "Green"
            $exportSource = $latestCheckpoint
            $useCheckpoint = $true
        }
        else {
            Write-ColorOutput "`nCheckpoint available but not using it (UseLastSnapshot = false)" "Yellow"
            $exportSource = $vm
            $useCheckpoint = $false
        }
    }
    else {
        Write-ColorOutput "  No checkpoints available" "Gray"
        $exportSource = $vm
        $useCheckpoint = $false
    }
    
    # Create export directory with timestamp and prefix
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportFolderName = "$Prefix`_$VMName`_$timestamp"
    $exportFolder = Join-Path $DestinationPath $exportFolderName
    
    # Remove old exports created by THIS script (with the same prefix)
    if ($RemoveOld) {
        $oldExports = Get-ChildItem -Path $DestinationPath -Directory -Filter "$Prefix`_$VMName`_*" -ErrorAction SilentlyContinue
        if ($oldExports) {
            Write-ColorOutput "`nRemoving old exports created by this script..." "Yellow"
            foreach ($oldExport in $oldExports) {
                Write-ColorOutput "  Deleting: $($oldExport.Name)" "Gray"
                Remove-Item -Path $oldExport.FullName -Recurse -Force
            }
        }
    }
    
    Write-ColorOutput "`nStarting VM export..." "Cyan"
    Write-ColorOutput "  Destination: $exportFolder" "Gray"
    Write-ColorOutput "  Export method: $(if ($useCheckpoint) { 'From Checkpoint' } elseif ($UseVSS -and $vm.State -eq 'Running') { 'VSS Snapshot' } else { 'Standard' })" "Gray"
    
    try {
        # Export VM or Checkpoint
        if ($useCheckpoint) {
            # Export from checkpoint (most reliable method)
            Write-ColorOutput "  Exporting from checkpoint: $($latestCheckpoint.Name)" "Gray"
            Export-VMSnapshot -VMSnapshot $latestCheckpoint -Path $exportFolder
        }
        elseif ($vm.State -eq "Running" -and $UseVSS) {
            Write-ColorOutput "  Exporting running VM with VSS" "Gray"
            
            # Export with job for progress tracking
            $exportJob = Export-VM -Name $VMName -Path $exportFolder -AsJob
            
            # Monitor progress
            $lastProgress = -1
            while ($exportJob.State -eq "Running") {
                $progress = (Get-Job -Id $exportJob.Id).Progress
                if ($progress -and $progress.PercentComplete -ne $lastProgress) {
                    $lastProgress = $progress.PercentComplete
                    Write-Progress -Activity "Exporting VM" -Status "Progress" -PercentComplete $lastProgress
                }
                Start-Sleep -Seconds 2
            }
            
            # Check result
            $result = Receive-Job -Job $exportJob
            Remove-Job -Job $exportJob
            
            if ($result) {
                throw "Export failed: $result"
            }
        }
        else {
            Write-ColorOutput "  Exporting stopped/saved VM" "Gray"
            Export-VM -Name $VMName -Path $exportFolder
        }
        
        Write-ColorOutput "`nExport completed successfully!" "Green"
        
        # Get export size
        $exportSize = (Get-ChildItem -Path $exportFolder -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
        Write-ColorOutput "  Export size: $([math]::Round($exportSize, 2)) GB" "Gray"
        
        # Get VHDX file path (for Proxmox import)
        $vhdxFiles = Get-ChildItem -Path $exportFolder -Recurse -Filter "*.vhdx" -File
        
        if ($vhdxFiles.Count -gt 0) {
            Write-ColorOutput "`nVHDX files found (for Proxmox import):" "Cyan"
            foreach ($vhdx in $vhdxFiles) {
                Write-ColorOutput "  $($vhdx.FullName)" "Gray"
                Write-ColorOutput "  Size: $([math]::Round($vhdx.Length / 1GB, 2)) GB" "Gray"
            }
        }
        
        return @{
            Success = $true
            ExportPath = $exportFolder
            VHDXFiles = $vhdxFiles
            UsedCheckpoint = $useCheckpoint
            CheckpointName = if ($useCheckpoint) { $latestCheckpoint.Name } else { $null }
        }
    }
    catch {
        Write-ColorOutput "Export failed: $_" "Red"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# --- MAIN LOGIC ---

Write-ColorOutput "=========================================" "Cyan"
Write-ColorOutput " Hyper-V VM Export to NAS" "Cyan"
Write-ColorOutput " Compatible with Proxmox Import" "Cyan"
Write-ColorOutput "=========================================" "Cyan"

# 1. Check administrator privileges
if (-not (Test-Administrator)) {
    Write-ColorOutput "`nERROR: This script must be run as Administrator" "Red"
    exit 1
}

# 2. Check Hyper-V module
try {
    Import-Module Hyper-V -ErrorAction Stop
    Write-ColorOutput "`nHyper-V module loaded successfully" "Green"
}
catch {
    Write-ColorOutput "`nERROR: Hyper-V module not available. Is Hyper-V role installed?" "Red"
    exit 1
}

# 3. Verify VM exists
Write-ColorOutput "`nVerifying VM '$VMName'..." "Cyan"
try {
    $vmInfo = Get-VMInfo -Name $VMName
    $vm = $vmInfo.VM
    $checkpoints = $vmInfo.Checkpoints
    
    Write-ColorOutput "VM found and accessible" "Green"
    
    if ($checkpoints -and $checkpoints.Count -gt 0) {
        Write-ColorOutput "Found $($checkpoints.Count) checkpoint(s)" "Yellow"
        
        if ($UseLastSnapshot) {
            $latestCheckpoint = $checkpoints | Sort-Object -Property CreationTime -Descending | Select-Object -First 1
            Write-ColorOutput "Will use checkpoint: $($latestCheckpoint.Name) (created: $($latestCheckpoint.CreationTime))" "Green"
        }
    }
    else {
        Write-ColorOutput "No checkpoints found" "Gray"
        
        if ($UseLastSnapshot) {
            Write-ColorOutput "WARNING: UseLastSnapshot = true, but no checkpoints available. Will export live VM." "Yellow"
        }
    }
}
catch {
    Write-ColorOutput "ERROR: $_" "Red"
    exit 1
}

# 4. Connect to network share
Write-ColorOutput "`nConnecting to export destination..." "Cyan"
try {
    Connect-NetworkShare -SharePath $ExportPath -Username $NetworkUsername -Password $NetworkPassword -RequireAuth $RequireNetworkAuth
}
catch {
    Write-ColorOutput "ERROR: $_" "Red"
    exit 1
}

# 5. Export VM
try {
    $result = Export-HyperVVM -VMName $VMName -DestinationPath $ExportPath -UseVSS $UseVSS -UseSnapshot $UseLastSnapshot -RemoveOld $RemoveOldExport -Prefix $ExportPrefix
    
    if ($result.Success) {
        Write-ColorOutput "`n=========================================" "Cyan"
        Write-ColorOutput "SUCCESS: VM exported successfully" "Green"
        Write-ColorOutput "=========================================" "Cyan"
        Write-ColorOutput "VM: $VMName" "White"
        Write-ColorOutput "Export location: $($result.ExportPath)" "White"
        
        if ($result.UsedCheckpoint) {
            Write-ColorOutput "Exported from checkpoint: $($result.CheckpointName)" "Yellow"
        }
        
        if ($result.VHDXFiles.Count -gt 0) {
            Write-ColorOutput "`nNext steps for Proxmox import:" "Yellow"
            Write-ColorOutput "1. Ensure NAS is mounted on Proxmox at /mnt/pve/nas_backup" "Gray"
            Write-ColorOutput "2. Run Proxmox import script with VHDX path:" "Gray"
            Write-ColorOutput "   VHDX_PATH=`"/mnt/pve/nas_backup/b1/$(Split-Path $result.ExportPath -Leaf)/Virtual Hard Disks/*.vhdx`"" "Gray"
        }
    }
    else {
        Write-ColorOutput "`n=========================================" "Cyan"
        Write-ColorOutput "ERROR: Export failed" "Red"
        Write-ColorOutput "=========================================" "Cyan"
        Write-ColorOutput "Error: $($result.Error)" "Red"
    }
}
catch {
    Write-ColorOutput "`nUnexpected error: $_" "Red"
    Write-ColorOutput $_.ScriptStackTrace "Gray"
}
finally {
    # 6. Disconnect network share
    Disconnect-NetworkShare -SharePath $ExportPath -RequireAuth $RequireNetworkAuth
}

Write-Host "`n"