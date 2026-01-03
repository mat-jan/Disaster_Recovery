# README

# Disaster Recovery

## VM Backup & Hyper-V Export to Proxmox

This repository contains scripts for exporting virtual machines from **Hornet Security VM Backup** and **Hyper-V** into **Proxmox** environments.  
It includes:

- **Hornet Security VM Backup Exporter (PowerShell)**  
  Exports the last successful backup of a VM to a network share.  
  ⚠️ **Requires Hornet Security Premium or higher plan** (FREE edition does not support export functionality).  

- **Hyper-V Export Script (PowerShell)**  
  Exports a VM or snapshot from Hyper-V to a NAS share, compatible with Proxmox import workflow.  

- **Proxmox Import Script (Bash)**  
  Imports a `.vhdx` disk into Proxmox storage, attaches it to the VM, and sets boot order.  

---

## Usage

1. **Hornet Security VM Backup Exporter**  
   - Configure VM name, credentials, and network share in the script.  
   - Run on the server with Hornet Security VM Backup installed.  
   - Exports the latest successful backup to the specified share.  

2. **Hyper-V Export Script**  
   - Run on a Hyper-V host with Administrator privileges.  
   - Supports exporting from checkpoints (recommended) or live VM with VSS snapshot.  
   - Exports VM to NAS for later import into Proxmox.  

3. **Proxmox Import Script**  
   - Verify `.vhdx` file exists on mounted NAS.  
   - Removes old disk from VM configuration.  
   - Imports new disk and attaches it as `scsi0`.  
   - Sets boot order to the new disk.  

---

## Notes
- Hornet Security VM Backup export requires **Premium or higher plan**.  
- Hyper-V export requires the **Hyper-V PowerShell module**.  
- Proxmox import requires the VM ID and storage configuration.  

---

# README (PL)

## Backup VM & Eksport Hyper-V do Proxmox

Repozytorium zawiera skrypty do eksportu maszyn wirtualnych z **Hornet Security VM Backup** oraz **Hyper-V** do środowiska **Proxmox**.  
W skład wchodzą:

- **Hornet Security VM Backup Exporter (PowerShell)**  
  Eksportuje ostatni udany backup maszyny na udział sieciowy.  
  ⚠️ **Wymaga planu Premium lub wyższego** (edycja FREE nie obsługuje eksportu).  

- **Skrypt eksportu Hyper-V (PowerShell)**  
  Eksportuje maszynę lub snapshot z Hyper-V na NAS, kompatybilny z importem do Proxmox.  

- **Skrypt importu Proxmox (Bash)**  
  Importuje dysk `.vhdx` do storage Proxmox, podłącza go do VM i ustawia boot order.  

---

## Użycie

1. **Hornet Security VM Backup Exporter**  
   - Skonfiguruj nazwę VM, dane logowania i udział sieciowy w skrypcie.  
   - Uruchom na serwerze z zainstalowanym Hornet Security VM Backup.  
   - Eksportuje ostatni udany backup na wskazany udział.  

2. **Skrypt eksportu Hyper-V**  
   - Uruchom na hoście Hyper-V z uprawnieniami Administratora.  
   - Obsługuje eksport z checkpointów (zalecane) lub działającej VM z VSS snapshot.  
   - Eksportuje VM na NAS do późniejszego importu w Proxmox.  

3. **Skrypt importu Proxmox**  
   - Zweryfikuj, że plik `.vhdx` istnieje na zamontowanym NAS.  
   - Usuwa stary dysk z konfiguracji VM.  
   - Importuje nowy dysk i podłącza go jako `scsi0`.  
   - Ustawia boot order na nowy dysk.  

---

## Uwagi
- Eksport z Hornet Security VM Backup wymaga **planu Premium lub wyższego**.  
- Eksport Hyper-V wymaga modułu **Hyper-V PowerShell**.  
- Import Proxmox wymaga ID maszyny oraz konfiguracji storage.  
