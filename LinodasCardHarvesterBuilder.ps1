#Requires -Version 5.1
# Linodas Card Harvester - Build Script
# MIT License
# Copyright (c) 2026 42 (ans_42@tuta.io)
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

param(
    [switch]$UseProxyFirst,
    [switch]$NoProxy
)

$Version = "2026/8/28 - Release"

Write-Host "Linodas Card Harvester Builder" -ForegroundColor Cyan
Write-Host "by 42 (ans_42@tuta.io)" -ForegroundColor Cyan
Write-Host "World of Linodas" -ForegroundColor Cyan
Write-Host "www.linodas.com" -ForegroundColor Cyan
Write-Host "by Lyragosa" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage: .\LinodasCardHarvesterBuilder.ps1 [-UseProxyFirst] [-NoProxy]" -ForegroundColor Yellow
Write-Host "  -UseProxyFirst    Prefer proxy downloads over direct links." -ForegroundColor Yellow
Write-Host "  -NoProxy          Disable all proxy URLs (overrides -UseProxyFirst)." -ForegroundColor Yellow
Write-Host ""

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RootDir

$ToolsDir    = Join-Path $RootDir "tools"
$DownloadDir = Join-Path $RootDir "download"
$Aria2Dir    = Join-Path $ToolsDir "aria2"
$MingwDir    = Join-Path $ToolsDir "mingw64"
$CurlDir     = Join-Path $ToolsDir "curl"
$IncludeDir  = Join-Path $RootDir "include"
$SevenZipDir = Join-Path $ToolsDir "7zip"

foreach ($dir in @($ToolsDir, $Aria2Dir, $MingwDir, $CurlDir, $DownloadDir, $IncludeDir, $SevenZipDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$hashTable = @{
    "aria2-1.37.0-win-64bit-build1.zip" = "6D78405DA9CF5639DBE8174787002161B8124D73880FB57CC8C0A3A63982F84E46DF4E626990C58F23452965AD925F0D37CB9147E99B25C3D7CA0EA49602F34D"
    "winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip" = "23AC519702CC8ECB9481EF45CBCEF6938F286AE01AC69E56FE346AA6A31A99AAA5AEFCD73C8041B2944985DB855B20D42B1BEA06F5C837AAC4FBB3EDDA1DC2A1"
    "curl-8.21.0_7-win64-mingw.zip" = "A0C7903849F4EA4C9465E478451AD09053719B7D9739DE3B1869A040E6DC6E1FECD15FE7959114AC14C637DEF85BE9CCE6B3292FAC43E2012E73714A1FF27243"
    "json.hpp" = "DA77FA48CA883DACF5CE147B2354E9D957AD66EDF72A7103FF5A8611C5CDA77B64F1F0CA60491295574EE158CECCCFE7797CD36FAAC5B47E75687400AC60769D"
    "7zr.exe" = "DFDCF16EDB65BADDD43181C9481A2C9453B0C678A6825108C2AB4CB30DE34497C5FDA5639721B3CED9CB4B98744FB6DAB7314BD49685385C365425B721B19279"
    "7z2602-extra.7z" = "612D54AF5793BD7A43DE8871481DC5658B0781F91E5A464F2ECE75A3654C326CDAB5CE51B5CA3930FA71EBFDF0F1846323D1F5A206F99855DF9EAEB56E285398"
}

function Test-FileValid {
    param([string]$Path, [long]$MinSize = 1)
    if (Test-Path $Path) {
        $item = Get-Item $Path -ErrorAction SilentlyContinue
        if ($item -and -not $item.PSIsContainer -and $item.Length -ge $MinSize) { return $true }
    }
    return $false
}

function Test-Hash {
    param([string]$Path, [string]$ExpectedHash)
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA512).Hash
    return ($actual -eq $ExpectedHash)
}

function Invoke-CurlDownload {
    param([string]$Url, [string]$OutputPath)
    $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curlExe) { return $false }
    Write-Host "  curl.exe downloading: $Url" -ForegroundColor Cyan
    & $curlExe.Source -L --ssl-no-revoke --connect-timeout 30 --max-time 120 -o $OutputPath $Url
    if ($LASTEXITCODE -eq 0 -and (Test-FileValid $OutputPath)) { return $true }
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Invoke-WebRequestDownload {
    param([string]$Url, [string]$OutputPath)
    Write-Host "  Invoke-WebRequest downloading: $Url" -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec 120
        return $true
    } catch {
        Write-Warning "  Download failed: $_"
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Invoke-Aria2Download {
    param([string]$Url, [string]$OutputPath, [int]$Threads = 16)
    $aria2c = Join-Path $Aria2Dir "aria2c.exe"
    if (-not (Test-Path $aria2c)) { return $false }
    Write-Host "  aria2c downloading (multi-threaded): $Url" -ForegroundColor Cyan
    $outDir = Split-Path -Parent $OutputPath
    $outFileName = Split-Path -Leaf $OutputPath
    & $aria2c --check-certificate=false --console-log-level=error `
        --dir="$outDir" --out="$outFileName" --continue=true `
        --max-connection-per-server=$Threads --split=$Threads --min-split-size=1M `
        "$Url"
    if ($LASTEXITCODE -eq 0 -and (Test-FileValid $OutputPath)) { return $true }
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Download-WithFallback {
    param(
        [string[]]$Urls,
        [string]$OutputPath,
        [string]$ExpectedHash,
        [switch]$UseAria2,
        [switch]$PreferProxy,
        [int]$MaxRetries = 5,
        [switch]$InfiniteRetry
    )
    if (Test-FileValid $OutputPath) {
        Write-Host "  Already exists, verifying hash: $OutputPath" -ForegroundColor Yellow
        if (Test-Hash -Path $OutputPath -ExpectedHash $ExpectedHash) {
            Write-Host "  Hash verification passed." -ForegroundColor Green
            return $true
        } else {
            Write-Warning "  Hash mismatch for existing file, will re-download."
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }
    }

    $orderedUrls = $Urls
    if ($PreferProxy -and -not $NoProxy) {
        $proxyUrls = @($Urls | Where-Object { $_ -like "*gh-proxy.com*" })
        $directUrls = @($Urls | Where-Object { $_ -notlike "*gh-proxy.com*" })
        $orderedUrls = @($proxyUrls + $directUrls)
    } elseif ($NoProxy) {
        $orderedUrls = @($Urls | Where-Object { $_ -notlike "*gh-proxy.com*" })
    }

    $attempt = 1
    while ($InfiniteRetry -or $attempt -le $MaxRetries) {
        if (-not $InfiniteRetry) {
            Write-Host "  Download attempt $attempt/$MaxRetries" -ForegroundColor DarkYellow
        } else {
            Write-Host "  Download attempt $attempt (infinite retry)" -ForegroundColor DarkYellow
        }

        foreach ($url in $orderedUrls) {
            if ($UseAria2) {
                if (Invoke-Aria2Download -Url $url -OutputPath $OutputPath) {
                    if (Test-Hash -Path $OutputPath -ExpectedHash $ExpectedHash) {
                        Write-Host "  Success (aria2c) with valid hash" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Warning "  Hash mismatch after aria2c download, trying next."
                        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            if (Invoke-CurlDownload -Url $url -OutputPath $OutputPath) {
                if (Test-Hash -Path $OutputPath -ExpectedHash $ExpectedHash) {
                    Write-Host "  Success (curl.exe) with valid hash" -ForegroundColor Green
                    return $true
                } else {
                    Write-Warning "  Hash mismatch after curl download, trying next."
                    Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                }
            }
            if (Invoke-WebRequestDownload -Url $url -OutputPath $OutputPath) {
                if (Test-Hash -Path $OutputPath -ExpectedHash $ExpectedHash) {
                    Write-Host "  Success (Invoke-WebRequest) with valid hash" -ForegroundColor Green
                    return $true
                } else {
                    Write-Warning "  Hash mismatch after WebRequest download, trying next."
                    Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($InfiniteRetry) {
            Write-Host "  All URLs failed in attempt $attempt, retrying indefinitely..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        } elseif ($attempt -lt $MaxRetries) {
            Write-Host "  All URLs failed or hash mismatched in attempt $attempt, retrying..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
        $attempt++
    }
    Write-Warning "All download attempts failed after $MaxRetries retries: $($orderedUrls -join ', ')"
    return $false
}

function Expand-ZipSmart {
    param([string]$ZipPath, [string]$DestinationDir, [string]$MarkerPath)
    Write-Host "  Extracting (Expand-Archive): $ZipPath -> $DestinationDir" -ForegroundColor Cyan
    $tempExpand = Join-Path $env:TEMP ("expand_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempExpand -Force | Out-Null
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $tempExpand -Force

        $items = @(Get-ChildItem -Path $tempExpand -Force)
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            $sourceDir = $items[0].FullName
        } else {
            $sourceDir = $tempExpand
        }

        $markerFile = Split-Path -Leaf $MarkerPath
        $found = Get-ChildItem -Path $sourceDir -Recurse -Filter $markerFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) {
            throw "Marker $MarkerPath not found in archive"
        }

        if (Test-Path $DestinationDir) {
            Get-ChildItem -Path $DestinationDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }

        Copy-Item -Path (Join-Path $sourceDir '*') -Destination $DestinationDir -Recurse -Force
        Write-Host "  Extraction complete (Expand-Archive)" -ForegroundColor Green
    } finally {
        if (Test-Path $tempExpand) { Remove-Item $tempExpand -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Expand-With7zOrFallback {
    param([string]$ZipPath, [string]$DestinationDir, [string]$MarkerPath)
    $sevenZa = Join-Path $SevenZipDir "7za.exe"
    if (Test-Path $sevenZa) {
        Write-Host "  Trying 7-Zip extraction..." -ForegroundColor Cyan
        $tempExpand = Join-Path $env:TEMP ("7zexpand_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tempExpand -Force | Out-Null
        try {
            & $sevenZa x $ZipPath -o"$tempExpand" -y | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $markerFile = Split-Path -Leaf $MarkerPath
                $found = Get-ChildItem -Path $tempExpand -Recurse -Filter $markerFile -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $items = @(Get-ChildItem -Path $tempExpand -Force)
                    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
                        $sourceDir = $items[0].FullName
                    } else {
                        $sourceDir = $tempExpand
                    }
                    if (Test-Path $DestinationDir) {
                        Get-ChildItem -Path $DestinationDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    } else {
                        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
                    }
                    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $DestinationDir -Recurse -Force
                    Write-Host "  Extraction complete (7-Zip)" -ForegroundColor Green
                    return $true
                } else {
                    Write-Warning "  Marker not found after 7-Zip extraction, falling back."
                }
            } else {
                Write-Warning "  7-Zip extraction failed (exit code $LASTEXITCODE), falling back."
            }
        } catch {
            Write-Warning "  7-Zip extraction error: $_"
        } finally {
            if (Test-Path $tempExpand) { Remove-Item $tempExpand -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Expand-ZipSmart -ZipPath $ZipPath -DestinationDir $DestinationDir -MarkerPath $MarkerPath
}

function Find-GppExe {
    $standard = Join-Path $MingwDir "bin\g++.exe"
    if (Test-Path $standard) { return $standard }
    $found = Get-ChildItem -Path $MingwDir -Recurse -Filter "g++.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Initialize-7Zip {
    Write-Host "`n[7-Zip] Preparing 7-Zip..." -ForegroundColor Magenta
    $sevenZa = Join-Path $SevenZipDir "7za.exe"
    if (Test-Path $sevenZa) {
        Write-Host "  7za.exe already exists, skipping." -ForegroundColor Green
        return $true
    }

    $sevenZrUrl = "https://www.7-zip.org/a/7zr.exe"
    $sevenZrPath = Join-Path $DownloadDir "7zr.exe"
    if (-not (Download-WithFallback -Urls @($sevenZrUrl) -OutputPath $sevenZrPath -ExpectedHash $hashTable["7zr.exe"] -MaxRetries 5 -PreferProxy:$UseProxyFirst)) {
        Write-Warning "7zr.exe download failed, 7-Zip will not be available."
        return $false
    }

    $extraUrls = @(
        "https://github.com/ip7z/7zip/releases/download/26.02/7z2602-extra.7z",
        "https://gh-proxy.com/https://github.com/ip7z/7zip/releases/download/26.02/7z2602-extra.7z"
    )
    $extraPath = Join-Path $DownloadDir "7z2602-extra.7z"
    if (-not (Download-WithFallback -Urls $extraUrls -OutputPath $extraPath -ExpectedHash $hashTable["7z2602-extra.7z"] -MaxRetries 5 -PreferProxy:$UseProxyFirst)) {
        Write-Warning "7z2602-extra.7z download failed, 7-Zip will not be available."
        return $false
    }

    $sevenZrExe = Join-Path $SevenZipDir "7zr.exe"
    Copy-Item $sevenZrPath -Destination $sevenZrExe -Force

    $tempExtract = Join-Path $env:TEMP ("7zsetup_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
    try {
        & $sevenZrExe x $extraPath -o"$tempExtract" -y | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $sevenZaFromExtra = Get-ChildItem -Path $tempExtract -Recurse -Filter "7za.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($sevenZaFromExtra) {
                Copy-Item $sevenZaFromExtra.FullName -Destination $sevenZa -Force
                Write-Host "  7za.exe successfully installed." -ForegroundColor Green
                return $true
            } else {
                Write-Warning "7za.exe not found in extra package."
                return $false
            }
        } else {
            Write-Warning "Failed to extract extra package with 7zr.exe (exit code $LASTEXITCODE)."
            return $false
        }
    } catch {
        Write-Warning "Exception during 7-Zip setup: $_"
        return $false
    } finally {
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

$resources = @(
    @{
        Name          = "aria2c"
        ZipFileName   = "aria2-1.37.0-win-64bit-build1.zip"
        ExtractDir    = $Aria2Dir
        Marker        = "aria2c.exe"
        Urls          = @(
            "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip",
            "https://gh-proxy.com/https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
        )
        IsSingleFile  = $false
        Critical      = $false
        MaxRetries    = 5
    },
    @{
        Name          = "MinGW-w64"
        ZipFileName   = "winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip"
        ExtractDir    = $MingwDir
        Marker        = "bin\g++.exe"
        Urls          = @(
            "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip",
            "https://gh-proxy.com/https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip"
        )
        IsSingleFile  = $false
        Critical      = $true
        MaxRetries    = 0
    },
    @{
        Name          = "libcurl"
        ZipFileName   = "curl-8.21.0_7-win64-mingw.zip"
        ExtractDir    = $CurlDir
        Marker        = "include\curl\curl.h"
        Urls          = @(
            "https://curl.se/windows/dl-8.21.0_7/curl-8.21.0_7-win64-mingw.zip"
        )
        IsSingleFile  = $false
        Critical      = $true
        MaxRetries    = 0
    },
    @{
        Name          = "nlohmann/json"
        ZipFileName   = "json.hpp"
        ExtractDir    = $IncludeDir
        Marker        = "json.hpp"
        Urls          = @(
            "https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp",
            "https://gh-proxy.com/https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp"
        )
        IsSingleFile  = $true
        Critical      = $true
        MaxRetries    = 0
    }
)

Write-Host "`nDownloading and verifying dependencies..." -ForegroundColor Magenta

$sevenZipReady = Initialize-7Zip

foreach ($res in $resources) {
    $name = $res.Name
    $zipFileName = $res.ZipFileName
    $extractDir = $res.ExtractDir
    $marker = $res.Marker
    $urls = $res.Urls
    $isSingle = $res.IsSingleFile
    $critical = $res.Critical
    $expectedHash = $hashTable[$zipFileName]

    Write-Host "`n[$name] Processing..." -ForegroundColor Cyan

    $downloadZip = Join-Path $DownloadDir $zipFileName
    $rootZip = Join-Path $RootDir $zipFileName
    $finalTarget = if ($isSingle) { Join-Path $extractDir $zipFileName } else { $extractDir }

    if ($isSingle) {
        $targetFile = Join-Path $extractDir $zipFileName
        if (Test-FileValid $targetFile) {
            Write-Host "  Already exists: $targetFile (skipping download and hash check)" -ForegroundColor Green
            continue
        }
    } else {
        $markerFull = Join-Path $extractDir $marker
        if (Test-Path $markerFull) {
            Write-Host "  Already extracted: $extractDir (skipping download and hash check)" -ForegroundColor Green
            continue
        }
    }

    $existingZip = $null
    if (Test-FileValid $downloadZip) { $existingZip = $downloadZip }
    elseif (Test-FileValid $rootZip) { $existingZip = $rootZip }

    if ($existingZip) {
        Write-Host "  Found existing archive: $existingZip" -ForegroundColor Yellow
        if (-not (Test-Hash -Path $existingZip -ExpectedHash $expectedHash)) {
            Write-Warning "  Hash mismatch for existing archive, will re-download."
            Remove-Item $existingZip -Force
            $existingZip = $null
        } else {
            Write-Host "  Hash verified." -ForegroundColor Green
        }
    }

    if (-not $existingZip) {
        $outPath = $downloadZip
        Write-Host "  Downloading to $outPath ..." -ForegroundColor Yellow
        $downloadArgs = @{
            Urls          = $urls
            OutputPath    = $outPath
            ExpectedHash  = $expectedHash
            UseAria2      = (-not $isSingle)
            PreferProxy   = $UseProxyFirst
        }
        if ($critical) {
            $downloadArgs['InfiniteRetry'] = $true
        } else {
            $downloadArgs['MaxRetries'] = 5
        }
        $downloadSuccess = Download-WithFallback @downloadArgs
        if (-not $downloadSuccess) {
            if ($critical) {
                Write-Error "Critical resource $name failed to download. Aborting."
                exit 1
            } else {
                Write-Warning "Non-critical resource $name failed to download. Skipping."
                continue
            }
        }
        $existingZip = $outPath
    }

    if ($isSingle) {
        Copy-Item $existingZip -Destination $finalTarget -Force
        Write-Host "  Copied $zipFileName to $finalTarget" -ForegroundColor Green
    } else {
        Expand-With7zOrFallback -ZipPath $existingZip -DestinationDir $finalTarget -MarkerPath $marker | Out-Null
    }

    Write-Host "[$name] Done." -ForegroundColor Green
}

Write-Host "`nVerifying tools..." -ForegroundColor Magenta

$aria2cPath = Join-Path $Aria2Dir "aria2c.exe"
if (-not (Test-Path $aria2cPath)) {
    Write-Warning "aria2c not available, falling back to single-threaded downloads (already handled)."
}

$gppExe = Find-GppExe
if (-not $gppExe) { throw "g++.exe not found after MinGW extraction" }
$mingwBin = Join-Path $MingwDir "bin"
$mingwInclude = Join-Path $MingwDir "include"
$mingwLib = Join-Path $MingwDir "lib"
if (-not (Test-Path $mingwBin) -or -not (Test-Path $mingwInclude) -or -not (Test-Path $mingwLib)) {
    throw "MinGW directory structure incomplete (bin/include/lib missing)."
}
Write-Host "  g++.exe located at: $gppExe" -ForegroundColor Green

if (-not (Test-Path (Join-Path $CurlDir "include\curl\curl.h"))) {
    throw "libcurl header not found after extraction"
}

$jsonHpp = Join-Path $IncludeDir "json.hpp"
if (-not (Test-FileValid $jsonHpp)) { throw "json.hpp not found" }

Write-Host "`nWriting crawler.cpp ..." -ForegroundColor Magenta
$cppSource = @'
/** @file crawler.cpp
 * @brief Linodas Card Harvester
 * @version __VERSION__
 *
 * MIT License
 *
 * Copyright (c) 2026 42 (ans_42@tuta.io)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <windows.h>
#include <curl/curl.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <chrono>
#include <thread>
#include <atomic>
#include <mutex>
#include <algorithm>
#include <cstdlib>
#include <csignal>
#include "json.hpp"

using json = nlohmann::json;

#pragma comment(lib, "libcurl.dll.a")

const std::string VERSION = "__VERSION__";
const std::string LICENSE_TEXT = R"(MIT License

Copyright (c) 2026 42 (ans_42@tuta.io)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.)";

int g_startId = 1;
int g_endId = 10000;
int g_threadCount = 4;
int g_requestIntervalMs = 50;
int g_retryCount = 3;
const std::string OUTPUT_FILE = "data.json";

std::atomic<bool> g_interrupted{false};

std::string stripHtml(const std::string& input) {
    std::string result;
    bool inTag = false;
    for (char c : input) {
        if (c == '<') inTag = true;
        else if (c == '>') inTag = false;
        else if (!inTag) result += c;
    }
    return result;
}

size_t findMatchingCloseTag(const std::string& html, size_t openTagEndPos, const std::string& tagName) {
    size_t pos = openTagEndPos;
    int depth = 1;
    std::string openTag = "<" + tagName;
    std::string closeTag = "</" + tagName + ">";
    while (pos < html.size()) {
        size_t nextOpen = html.find(openTag, pos);
        size_t nextClose = html.find(closeTag, pos);
        if (nextClose == std::string::npos) return std::string::npos;
        if (nextOpen != std::string::npos && nextOpen < nextClose) {
            if (nextOpen + openTag.size() < html.size() &&
                (html[nextOpen + openTag.size()] == ' ' || html[nextOpen + openTag.size()] == '>')) {
                depth++;
                pos = nextOpen + openTag.size();
            } else {
                pos = nextOpen + 1;
            }
        } else {
            depth--;
            if (depth == 0) return nextClose;
            pos = nextClose + closeTag.size();
        }
    }
    return std::string::npos;
}

std::string extractOuterHtml(const std::string& html, size_t tagStartPos, const std::string& tagName) {
    size_t tagEnd = html.find('>', tagStartPos);
    if (tagEnd == std::string::npos) return "";
    size_t closePos = findMatchingCloseTag(html, tagEnd + 1, tagName);
    if (closePos == std::string::npos) return "";
    return html.substr(tagStartPos, closePos - tagStartPos + tagName.size() + 3);
}

std::string extractInnerHtml(const std::string& html, size_t tagStartPos, const std::string& tagName) {
    size_t tagEnd = html.find('>', tagStartPos);
    if (tagEnd == std::string::npos) return "";
    size_t closePos = findMatchingCloseTag(html, tagEnd + 1, tagName);
    if (closePos == std::string::npos) return "";
    return html.substr(tagEnd + 1, closePos - tagEnd - 1);
}

static size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* output) {
    size_t total = size * nmemb;
    output->append((char*)contents, total);
    return total;
}

std::pair<long, std::string> fetchUrl(const std::string& url) {
    CURL* curl = curl_easy_init();
    std::string response;
    long http_code = 0;
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "Mozilla/5.0 (compatible; CardCrawler/1.0)");
        curl_easy_setopt(curl, CURLOPT_ENCODING, "");
        CURLcode res = curl_easy_perform(curl);
        if (res == CURLE_OK) {
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
        }
        curl_easy_cleanup(curl);
    }
    return {http_code, response};
}

json parseCardPage(const std::string& html) {
    json card;
    const std::string marker = "<div class=\"wireframe format\">";
    size_t wireframePos = html.find(marker);
    if (wireframePos == std::string::npos) return card;

    std::string rawHtml = extractOuterHtml(html, wireframePos, "div");
    card["raw_html"] = rawHtml;

    const std::string rowMarker = "<div class=\"list_row highlight flex flex-row\">";
    size_t searchPos = 0;
    while (true) {
        size_t rowStart = rawHtml.find(rowMarker, searchPos);
        if (rowStart == std::string::npos) break;
        size_t rowEnd = findMatchingCloseTag(rawHtml, rawHtml.find('>', rowStart) + 1, "div");
        if (rowEnd == std::string::npos) break;
        std::string rowHtml = rawHtml.substr(rowStart, rowEnd - rowStart + 6);

        const std::string nameClass = "class=\"pl-2 py-2 w-1/3\"";
        size_t nameTagPos = rowHtml.find(nameClass);
        if (nameTagPos == std::string::npos) { searchPos = rowEnd + 1; continue; }
        size_t nameDivStart = rowHtml.rfind("<div", nameTagPos);
        if (nameDivStart == std::string::npos) { searchPos = rowEnd + 1; continue; }
        std::string nameInner = extractInnerHtml(rowHtml, nameDivStart, "div");
        std::string fieldName = stripHtml(nameInner);

        const std::string valueClass = "class=\"pr-2 py-2 w-2/3 text-center\"";
        size_t valueTagPos = rowHtml.find(valueClass);
        if (valueTagPos == std::string::npos) { searchPos = rowEnd + 1; continue; }
        size_t valueDivStart = rowHtml.rfind("<div", valueTagPos);
        if (valueDivStart == std::string::npos) { searchPos = rowEnd + 1; continue; }
        std::string valueInner = extractInnerHtml(rowHtml, valueDivStart, "div");

        while (!fieldName.empty() && (fieldName.front() == ' ' || fieldName.front() == '\n' || fieldName.front() == '\t')) fieldName.erase(0, 1);
        while (!fieldName.empty() && (fieldName.back() == ' ' || fieldName.back() == '\n' || fieldName.back() == '\t')) fieldName.pop_back();

        if (!fieldName.empty()) {
            card[fieldName] = valueInner;
        }
        searchPos = rowEnd + 1;
    }

    if (!card.contains("\u5361\u7247ID")) {
        card.clear();
        return card;
    }
    return card;
}

void parseCommandLine(int argc, char* argv[]) {
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--license") {
            std::cout << LICENSE_TEXT << std::endl;
            exit(0);
        } else if (arg == "--version") {
            std::cout << "Linodas Card Harvester\n"
                      << "by 42 (ans_42@tuta.io)\n"
                      << "Version: " << VERSION << std::endl;
            exit(0);
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Linodas Card Harvester\n"
                      << "by 42 (ans_42@tuta.io)\n"
                      << "Version: " << VERSION << "\n"
                      << "World of Linodas\n"
                      << "www.linodas.com\n"
                      << "by Lyragosa\n\n"
                      << "Usage: crawler.exe [options]\n"
                      << "Options:\n"
                      << "  --start <n>    Start card ID (default: 1)\n"
                      << "  --end <n>      End card ID (default: 10000)\n"
                      << "  --threads <n>  Number of threads (default: 4, max: 32)\n"
                      << "  --interval <ms> Interval between requests in ms (default: 50, 0 = no delay)\n"
                      << "  --retry <n>    Retry count per request (default: 3)\n"
                      << "  --help         Show this help\n"
                      << "  --version      Show version\n"
                      << "  --license      Show MIT license\n";
            exit(0);
        }
    }

    auto getNext = [&](int& index, int argc, char* argv[]) -> std::string {
        if (index + 1 < argc) return argv[++index];
        return "";
    };

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--start" || arg == "-s") {
            std::string val = getNext(i, argc, argv);
            try { int n = std::stoi(val); if (n > 0) g_startId = n; } catch (...) {}
        }
        else if (arg == "--end" || arg == "-e") {
            std::string val = getNext(i, argc, argv);
            try { int n = std::stoi(val); if (n > 0) g_endId = n; } catch (...) {}
        }
        else if (arg == "--threads" || arg == "-t") {
            std::string val = getNext(i, argc, argv);
            try { int n = std::stoi(val); if (n >= 1 && n <= 32) g_threadCount = n; } catch (...) {}
        }
        else if (arg == "--interval" || arg == "-i") {
            std::string val = getNext(i, argc, argv);
            try { int n = std::stoi(val); if (n >= 0 && n <= 60000) g_requestIntervalMs = n; } catch (...) {}
        }
        else if (arg == "--retry" || arg == "-r") {
            std::string val = getNext(i, argc, argv);
            try { int n = std::stoi(val); if (n >= 0 && n <= 100) g_retryCount = n; } catch (...) {}
        }
    }
    if (g_endId < g_startId) { std::swap(g_startId, g_endId); }
}

BOOL WINAPI ConsoleCtrlHandler(DWORD ctrlType) {
    if (ctrlType == CTRL_C_EVENT || ctrlType == CTRL_BREAK_EVENT) {
        g_interrupted.store(true);
        return TRUE;
    }
    return FALSE;
}

int main(int argc, char* argv[]) {
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    SetConsoleCtrlHandler(ConsoleCtrlHandler, TRUE);
    curl_global_init(CURL_GLOBAL_ALL);
    parseCommandLine(argc, argv);

    std::cout << "Starting crawler with: start=" << g_startId
              << ", end=" << g_endId
              << ", threads=" << g_threadCount
              << ", interval=" << g_requestIntervalMs << "ms"
              << ", retry=" << g_retryCount << std::endl;
    std::cout.flush();

    std::atomic<int> next_id{g_startId};
    std::vector<json> allCards;
    std::mutex cardsMutex;
    std::mutex printMutex;

    auto worker = [&]() {
        while (true) {
            if (g_interrupted.load()) break;
            int id = next_id.fetch_add(1);
            if (id > g_endId) break;

            std::string url = "https://www.linodas.com/card/view/id/" + std::to_string(id);
            bool success = false;
            std::string html;
            long statusCode = 0;

            for (int attempt = 0; attempt < g_retryCount && !success; ++attempt) {
                auto [code, body] = fetchUrl(url);
                statusCode = code;
                html = body;
                if (statusCode == 200) {
                    success = true;
                } else {
                    if (attempt < g_retryCount - 1) {
                        std::lock_guard<std::mutex> lock(printMutex);
                        std::cout << "ID " << id << " : HTTP " << statusCode << " (attempt " << (attempt+1) << "/" << g_retryCount << "), retrying..." << std::endl;
                        std::this_thread::sleep_for(std::chrono::milliseconds(200));
                    }
                }
            }

            if (success) {
                json card = parseCardPage(html);
                if (!card.empty()) {
                    std::string name = "Unknown";
                    if (card.contains("\u540d\u79f0") && card["\u540d\u79f0"].is_string()) {
                        name = card["\u540d\u79f0"].get<std::string>();
                    }
                    {
                        std::lock_guard<std::mutex> lock(cardsMutex);
                        allCards.push_back(card);
                    }
                    {
                        std::lock_guard<std::mutex> lock(printMutex);
                        std::cout << "ID " << id << " : OK - " << name << std::endl;
                    }
                } else {
                    std::lock_guard<std::mutex> lock(printMutex);
                    std::cout << "ID " << id << " : parse fail (skip)" << std::endl;
                }
            } else {
                std::lock_guard<std::mutex> lock(printMutex);
                std::cout << "ID " << id << " : HTTP " << statusCode << " (skip after " << g_retryCount << " attempts)" << std::endl;
            }

            if (g_requestIntervalMs > 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(g_requestIntervalMs));
            }
        }
    };

    std::vector<std::thread> threads;
    for (int i = 0; i < g_threadCount; ++i) threads.emplace_back(worker);
    for (auto& t : threads) t.join();

    std::sort(allCards.begin(), allCards.end(), [](const json& a, const json& b) {
        std::string idA = a.value("\u5361\u7247ID", "0");
        std::string idB = b.value("\u5361\u7247ID", "0");
        return std::stoi(stripHtml(idA)) < std::stoi(stripHtml(idB));
    });

    json output = json::array();
    for (const auto& c : allCards) output.push_back(c);

    std::ofstream file(OUTPUT_FILE);
    if (file.is_open()) {
        file << output.dump(2, ' ', false, json::error_handler_t::replace);
        file.close();
        std::cout << "Successfully saved " << allCards.size() << " cards to " << OUTPUT_FILE << std::endl;
        if (g_interrupted.load()) std::cout << "Execution interrupted by user, partial data saved." << std::endl;
    } else {
        std::cerr << "Failed to open output file: " << OUTPUT_FILE << std::endl;
        curl_global_cleanup();
        return 1;
    }

    curl_global_cleanup();
    return 0;
}
'@

$cppSource = $cppSource.Replace('__VERSION__', $Version)
Set-Content -Path "crawler.cpp" -Value $cppSource -Encoding UTF8

Write-Host "`nCompiling crawler.cpp ..." -ForegroundColor Magenta
$curlInclude = Join-Path $CurlDir "include"
$curlLib = Join-Path $CurlDir "lib"
$compileArgs = @(
    "-std=c++17",
    "-O2",
    "-I", $curlInclude,
    "-I", $IncludeDir,
    "-L", $curlLib,
    "crawler.cpp",
    "-o", "crawler.exe",
    "-lcurl",
    "-lws2_32",
    "-lwldap32",
    "-lcrypt32"
)
Write-Host "  Command: $gppExe $($compileArgs -join ' ')" -ForegroundColor DarkGray
& $gppExe @compileArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed with exit code $LASTEXITCODE"
    exit 1
}

Write-Host "`nCopying required DLLs to script directory..." -ForegroundColor Magenta
$exeDir = $RootDir

$curlBin = Join-Path $CurlDir "bin"
if (Test-Path $curlBin) {
    Get-ChildItem -Path $curlBin -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName -Destination $exeDir -Force
        Write-Host "  Copied $($_.Name)" -ForegroundColor Green
    }
} else {
    Write-Warning "  curl bin directory not found, DLLs may be missing"
}

$mingwBin = Join-Path $MingwDir "bin"
$runtimeDlls = @("libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll")
foreach ($dll in $runtimeDlls) {
    $src = Join-Path $mingwBin $dll
    if (Test-Path $src) {
        Copy-Item $src -Destination $exeDir -Force
        Write-Host "  Copied $dll" -ForegroundColor Green
    }
}

Write-Host "`nTesting crawler.exe --version ..." -ForegroundColor Magenta
& "$exeDir\crawler.exe" --version
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild successful! Generated crawler.exe" -ForegroundColor Green
    Write-Host "Run with: .\crawler.exe --help" -ForegroundColor Green
} else {
    Write-Error "crawler.exe test failed with exit code $LASTEXITCODE"
}
