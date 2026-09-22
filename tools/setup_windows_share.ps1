<#
.SYNOPSIS
    Sets up a Windows folder so PKG Browser on the console can read it over SMB.

.DESCRIPTION
    Windows refuses network logons for accounts with a blank password, and it does not allow
    guest access, so a share needs an account with a password behind it. Rather than putting
    a password on the account you sign in with -- or letting every blank-password account on
    the machine log in over the network, which is what relaxing that policy does -- this
    creates one limited account that can read one folder and nothing else.

    What it does:
      * creates a local account (default "ps5") with the password you give it
      * hides that account from the Windows sign-in screen
      * shares the folder read-only to that account
      * grants it read access to the folder on disk

    Run it from an elevated PowerShell. Nothing here touches your own account.

.EXAMPLE
    .\setup_windows_share.ps1 -Path C:\Users\me\Documents\PS5JB\games -Password 'Ps5Games!2026'

.EXAMPLE
    .\setup_windows_share.ps1 -Remove
#>

[CmdletBinding()]
param(
    [string] $Path = "$env:USERPROFILE\Documents\PS5JB\games",
    [string] $ShareName = 'games',
    [string] $UserName,
    [string] $Password,
    [switch] $Remove
)

$ErrorActionPreference = 'Stop'

$elevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $elevated) {
    Write-Error "Run this from an elevated PowerShell (right-click Windows Terminal -> Run as administrator)."
    return
}

$hiddenAccounts = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'

# Asked for rather than assumed: these two are what get typed into the console, and people
# reasonably want to pick them. Both can still be passed as parameters instead.
if (-not $Remove -and -not $UserName) {
    $typed = Read-Host "User name for the console to sign in with [ps5]"
    $UserName = if ($typed.Trim()) { $typed.Trim() } else { 'ps5' }
}

if (-not $UserName) { $UserName = 'ps5' }

if ($UserName -notmatch '^[A-Za-z0-9._-]{1,20}$') {
    Write-Error "'$UserName' will not work as a Windows user name. Use letters, digits, dots, dashes or underscores, up to 20 characters."
    return
}

if ($Remove) {
    Write-Host "Removing the share and the account..." -ForegroundColor Cyan

    if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
        Remove-SmbShare -Name $ShareName -Force
        Write-Host "  share '$ShareName' removed"
    }

    if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $UserName
        Write-Host "  account '$UserName' removed"
    }

    if (Test-Path $hiddenAccounts) {
        Remove-ItemProperty -Path $hiddenAccounts -Name $UserName -ErrorAction SilentlyContinue
    }

    Write-Host "Done. Remove the source on the console as well." -ForegroundColor Green
    return
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "There is no folder at $Path"
    return
}

$Path = (Resolve-Path -LiteralPath $Path).Path

function Reveal($secureString) {
    [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString))
}

if ($Password) {
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
} else {
    # Asked twice. A typo here does not show up until the console tries to sign in, where all
    # it can say is that the share refused it.
    while ($true) {
        $secure = Read-Host "Password for '$UserName'" -AsSecureString
        $again  = Read-Host "Type it again" -AsSecureString

        if (-not (Reveal $secure)) {
            Write-Host "  A password is required - Windows refuses blank ones over the network." -ForegroundColor Yellow
            continue
        }

        if ((Reveal $secure) -ne (Reveal $again)) {
            Write-Host "  Those did not match. Try again." -ForegroundColor Yellow
            continue
        }

        break
    }
}

# Checked however it arrived: a blank password looks fine here and then fails on the console,
# because Windows will not accept one from anything on the network.
if (-not (Reveal $secure)) {
    Write-Error "The password cannot be blank - Windows refuses blank passwords for network sign-ins, so the console would never get in."
    return
}

# ---------------------------------------------------------------- the account

if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $UserName -Password $secure
    Write-Host "Account '$UserName' already existed; password updated." -ForegroundColor Yellow
} else {
    # Description is capped at 48 characters by New-LocalUser, hence the terseness.
    New-LocalUser -Name $UserName `
                  -Password $secure `
                  -FullName 'PS5 PKG Browser' `
                  -Description 'Read-only PS5 package share' `
                  -PasswordNeverExpires `
                  -UserMayNotChangePassword | Out-Null
    Write-Host "Created local account '$UserName'." -ForegroundColor Green
}

# Out of the Users group: this account exists to read one folder, and leaving it there gives
# it the read access every local user has to the rest of the machine.
try {
    Remove-LocalGroupMember -Group 'Users' -Member $UserName -ErrorAction Stop
    Write-Host "  taken out of the Users group"
} catch {
    # Not a member, which is fine.
}

# Keep it off the sign-in screen; it is not a person.
if (-not (Test-Path $hiddenAccounts)) {
    New-Item -Path $hiddenAccounts -Force | Out-Null
}
New-ItemProperty -Path $hiddenAccounts -Name $UserName -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host "  hidden from the sign-in screen"

# ---------------------------------------------------------------- the share

if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name $ShareName -Force
}

New-SmbShare -Name $ShareName -Path $Path -ReadAccess $UserName -Description 'PS5 packages' | Out-Null
Write-Host "Shared $Path as \\$env:COMPUTERNAME\$ShareName (read-only)." -ForegroundColor Green

# Share permissions and file permissions are separate gates; the account has to pass both.
& icacls $Path /grant "${UserName}:(OI)(CI)(RX)" /T /C /Q | Out-Null
Write-Host "  read access granted on disk"

# ---------------------------------------------------------------- what to type

$address = (Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway } |
            Select-Object -First 1 -ExpandProperty IPv4Address).IPAddress

Write-Host ""
Write-Host "On the console, at http://<console-ip>:9050/sources" -ForegroundColor Cyan
Write-Host "  address   \\$address\$ShareName"
Write-Host "  user name $UserName"
Write-Host "  password  the one you just set"
Write-Host ""
Write-Host "Undo all of this with:  .\setup_windows_share.ps1 -Remove" -ForegroundColor DarkGray
