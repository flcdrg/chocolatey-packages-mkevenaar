function Assert-TcpPortIsOpen {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)][ValidateNotNullOrEmpty()][int] $portNumber
    )

    $process = Get-NetTCPConnection -State Listen -LocalPort $portNumber -ErrorAction SilentlyContinue | `
        Select-Object -First 1 -ExpandProperty OwningProcess | `
        Select-Object @{Name = "Id"; Expression = {$_} } | `
        Get-Process | `
        Select-Object Name, Path

    if ($process) {
        if ($process.Path) {
            Write-Host "Port '$portNumber' is in use by '$($process.Name)' with path '$($process.Path)'..."
        }
        else {
            Write-Host "Port '$portNumber' is in use by '$($process.Name)'..."
        }

        return $false
    }

    return $true
}

function Get-NginxInstallOptions {
    $configFile = Join-Path $env:chocolateyPackageFolder 'config.xml'
    $config = Import-CliXml $configFile

    return $config
}

function Get-NginxPaths {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][ValidateNotNullOrEmpty()][string] $installDir
    )

    $nginxDir = Get-ChildItem $installDir -Directory | Select-Object -First 1 -ExpandProperty FullName
    $confPath = Join-Path $nginxDir 'conf\nginx.conf'
    $binPath = Join-Path $nginxDir 'nginx.exe'

    return @{ NginxDir = $nginxDir; ConfPath = $confPath; BinPath = $binPath }
}

function Install-Nginx {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject] $arguments
    )

    # Move older install up one
    $existingNginxDir = Get-ChildItem $arguments.destination -Directory -Filter 'nginx*' | Sort-Object { -join $_.Name.Replace('-','.').Split('.').PadLeft(3) } -Descending | Select-Object -First 1 -ExpandProperty FullName

    Write-Verbose "existingDirectory $existingNginxDir"

    if (Test-Path $existingNginxDir) {
      Get-ChildItem $existingNginxDir | Move-Item -Destination $arguments.destination
      Remove-Item $existingNginxDir
    }

    $specificFolder = [System.IO.Path]::GetFileNameWithoutExtension($arguments.file)

    Write-Verbose "specificFolder $specificFolder"

    Get-ChocolateyUnzip `
        -file $arguments.file `
        -destination $arguments.destination `
        -packageName $env:ChocolateyPackageName `
        -specificFolder $specificFolder

    Get-ChildItem $arguments.destination

    Set-NginxConfig $arguments

    if ($arguments.serviceName) {
      Install-NginxService $arguments
    }

    Set-NginxInstallOptions $arguments
}

function Install-NginxService {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject] $arguments
    )

    $nginxPaths = Get-NginxPaths $arguments.destination

    Get-Service -Name $arguments.serviceName -ErrorAction SilentlyContinue | ForEach-Object {
      write-host "Shutting down Nginx if it is running"
      nssm stop $($arguments.serviceName) 2>&1 | Out-Null
      nssm remove $($arguments.serviceName) confirm 2>&1 | Out-Null
    }

    nssm install $($arguments.serviceName) "$($nginxPaths.BinPath)" 2>&1 | Out-Null
    nssm set $($arguments.serviceName) Description "Nginx web server" 2>&1 | Out-Null
    nssm set $($arguments.serviceName) AppDirectory  "$($nginxPaths.NginxDir)" 2>&1 | Out-Null
    nssm set $($arguments.serviceName) AppNoConsole 1 2>&1 | Out-Null # Mentioned on top off http://nssm.cc/download
    nssm set $($arguments.serviceName) AppStopMethodSkip 7 2>&1 | Out-Null
    nssm set $($arguments.serviceName) ObjectName "$($arguments.ServiceAccount)" 2>&1 | Out-Null
    nssm start $($arguments.serviceName) 2>&1 | Out-Null
}

function Set-NginxConfig {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject] $arguments
    )

    $nginxPaths = Get-NginxPaths $arguments.destination

    # Set the server root and port number
    $nginxConf = Get-Content $nginxPaths.ConfPath
    $nginxConf = $nginxConf -replace 'listen\s(.*\d)', "listen       $($arguments.port)"

    Set-Content -Path $nginxPaths.ConfPath -Value $nginxConf -Encoding Ascii
}

function Set-NginxInstallOptions {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject] $arguments
    )

    $nginxPaths = Get-NginxPaths $arguments.destination

    $config = @{
        Destination = $nginxPaths.NginxDir
        BinPath   = $nginxPaths.BinPath
        ServiceName = $arguments.serviceName
        ServiceAccount = $arguments.ServiceAccount
    }

    $configFile = Join-Path $env:chocolateyPackageFolder 'config.xml'
    Export-Clixml -Path $configFile -InputObject $config
}

function Stop-NginxService {
    $config = Get-NginxInstallOptions

    $service = Get-Service | Where-Object Name -eq $config.serviceName

    if ($service) {
        Stop-Service $config.serviceName
    }
}

function Uninstall-Nginx {
    $config = Get-NginxInstallOptions

    Uninstall-NginxService

    Remove-Item $config.destination -Recurse -Force
}

function Uninstall-NginxService {
    $config = Get-NginxInstallOptions

    if ($config.serviceName) {
      nssm stop $($config.serviceName) 2>&1 | Out-Null
      nssm remove $($config.serviceName) confirm 2>&1 | Out-Null
    }
}
