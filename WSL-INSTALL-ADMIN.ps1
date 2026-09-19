# Run this file AS ADMINISTRATOR (right-click PowerShell -> Run as Admin)
# Installs WSL2 + Ubuntu for kernel builds
# After it finishes: REBOOT, then open Ubuntu from Start menu, create user, then continue.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Enabling WSL + VirtualMachinePlatform ==="
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

Write-Host "=== Setting WSL2 as default ==="
wsl --set-default-version 2

Write-Host "=== Installing Ubuntu ==="
wsl --install -d Ubuntu

Write-Host ""
Write-Host "Done. REBOOT your PC now."
Write-Host "After reboot: open Ubuntu app, create username/password, then run:"
Write-Host "  cd /mnt/c/Users/$env:USERNAME/Downloads/universal9611_gaming_kernel"
Write-Host "  bash ubuntu-setup.sh"
