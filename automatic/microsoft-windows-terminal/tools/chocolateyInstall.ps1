﻿$ErrorActionPreference = 'Stop';

$toolsDir       = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$fileName       = "$toolsDir\Microsoft.WindowsTerminal_0.11.1251.0_8wekyb3d8bbwe.msixbundle"
$version        = "0.11.1251.0"

$WindowsVersion=[Environment]::OSVersion.Version
if ($WindowsVersion.Major -ne "10") {
  throw "This package requires Windows 10."
}
#The .msixbundle format is not supported on Windows 10 version 1709 and 1803. https://docs.microsoft.com/en-us/windows/msix/msix-1709-and-1803-support
$IsCorrectBuild=[Environment]::OSVersion.Version.Build
if ($IsCorrectBuild -lt "18362") {
  throw "This package requires at least Windows 10 version 1903/OS build 18362.x."
}

if ((Get-AppxPackage -name Microsoft.WindowsTerminal).Version -Match $version) {
  if($env:ChocolateyForce) {
    # you can't install the same version of an appx package, you need to remove it first
    Write-Host Removing already installed version first.
    Get-AppxPackage -Name Microsoft.WindowsTerminal | Remove-AppxPackage
  } else {
    Write-Host The $version version of Windows-Terminal is already installed. If you want to reinstall use --force
    return
  }
}

Add-AppxPackage -Path $fileName
