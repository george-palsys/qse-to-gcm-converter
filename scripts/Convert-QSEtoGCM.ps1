<#
.SYNOPSIS
    Convert IBM QSE CSV output to GCM-compatible JSON format

.DESCRIPTION
    This script reads QSE CSV reports (API Discovery or Crypto Inventory)
    and converts them to IBM Guardium Cryptographic Manager (GCM) compatible JSON format.
    Automatically adds required fields like repositoryUrl, applicationId, etc.

.PARAMETER CsvPath
    Path to the QSE CSV file

.PARAMETER ConfigPath
    Path to the configuration file (JSON format) containing application information

.PARAMETER OutputPath
    Path for the output JSON file (default: output.json)

.PARAMETER ReportType
    Report type: 'api' (API Discovery) or 'crypto' (Crypto Inventory)
    If not specified, will auto-detect

.EXAMPLE
    .\Convert-QSEtoGCM.ps1 -CsvPath "API discovery results.csv" -ConfigPath "config.json"

.EXAMPLE
    .\Convert-QSEtoGCM.ps1 -CsvPath "Crypto inventory.csv" -ConfigPath "config.json" -OutputPath "output\crypto.json"

.NOTES
    Author: QSE to GCM Converter Project
    Version: 1.0.0
    Date: 2026-05-06
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$CsvPath,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "output.json",

    [Parameter(Mandatory=$false)]
    [ValidateSet('api', 'crypto', 'auto')]
    [string]$ReportType = 'auto'
)

$ErrorActionPreference = "Stop"

function Load-Config {
    param([string]$Path)
    
    try {
        $config = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        
        if (-not $config.repositoryUrl) {
            throw "Config file missing required field: repositoryUrl"
        }
        if (-not $config.applicationId) {
            throw "Config file missing required field: applicationId"
        }
        if (-not $config.applicationVersion) {
            throw "Config file missing required field: applicationVersion"
        }
        
        return $config
    }
    catch {
        Write-Error "Failed to load config file: $_"
        throw
    }
}

function Detect-ReportType {
    param([string]$CsvPath)
    
    $fileName = [System.IO.Path]::GetFileName($CsvPath).ToLower()
    
    if ($fileName -match "api.*discovery") {
        return "api"
    }
    elseif ($fileName -match "crypto.*inventory") {
        return "crypto"
    }
    else {
        $firstLine = Get-Content -Path $CsvPath -First 1
        if ($firstLine -match "Crypto Function") {
            return "crypto"
        }
        else {
            return "api"
        }
    }
}

function Convert-CsvToFunctionCalls {
    param(
        [array]$CsvData,
        [string]$Type
    )
    
    $functionCalls = @()
    
    foreach ($row in $CsvData) {
        $functionCall = @{
            functionName = $row.'Crypto Artefact Name'
            location = @{
                fileName = $row.'File Path'
                line = [int]$row.'Line Number'
                startColumn = [int]$row.'Start Position'
                endColumn = [int]$row.'End Position'
            }
            cryptoProperties = @{
                library = $row.Library
                assetType = $row.'Asset Type'
            }
        }
        
        if ($row.Primitive) {
            $functionCall.cryptoProperties.primitive = $row.Primitive
        }
        if ($row.Variant) {
            $functionCall.cryptoProperties.variant = $row.Variant
        }
        if ($row.Oid) {
            $functionCall.cryptoProperties.oid = $row.Oid
        }
        if ($row.'Digest Size') {
            $functionCall.cryptoProperties.digestSize = $row.'Digest Size'
        }
        if ($row.'Crypto Function') {
            $functionCall.cryptoProperties.cryptoFunction = $row.'Crypto Function'
        }
        if ($row.'Block Size') {
            $functionCall.cryptoProperties.blockSize = $row.'Block Size'
        }
        if ($row.'Private Key Size') {
            $functionCall.cryptoProperties.privateKeySize = $row.'Private Key Size'
        }
        if ($row.'Public Key Size') {
            $functionCall.cryptoProperties.publicKeySize = $row.'Public Key Size'
        }
        if ($row.Mode) {
            $functionCall.cryptoProperties.mode = $row.Mode
        }
        if ($row.Padding) {
            $functionCall.cryptoProperties.padding = $row.Padding
        }
        if ($row.'is Final') {
            $functionCall.cryptoProperties.isFinal = $row.'is Final'
        }
        
        $functionCalls += $functionCall
    }
    
    return $functionCalls
}

function Build-MetadataProperties {
    param($Config)
    
    $properties = @()
    
    if ($Config.metadata) {
        foreach ($key in $Config.metadata.PSObject.Properties.Name) {
            $properties += @{
                name = $key
                value = $Config.metadata.$key
            }
        }
    }
    
    return $properties
}

function Convert-QSEtoGCM {
    param(
        [string]$CsvPath,
        [object]$Config,
        [string]$Type
    )
    
    Write-Host "Reading CSV file: $CsvPath" -ForegroundColor Cyan
    
    $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
    
    Write-Host "Found $($csvData.Count) records" -ForegroundColor Green
    Write-Host "Converting to GCM format..." -ForegroundColor Cyan
    
    $functionCalls = Convert-CsvToFunctionCalls -CsvData $csvData -Type $Type
    
    $gcmJson = @{
        findings = @{
            assets = @(
                @{
                    repositoryUrl = $Config.repositoryUrl
                    applicationId = $Config.applicationId
                    applicationVersion = $Config.applicationVersion
                    functionCalls = $functionCalls
                }
            )
        }
        metadata = @{
            properties = Build-MetadataProperties -Config $Config
        }
    }
    
    return $gcmJson
}

try {
    Write-Host "`n=== QSE to GCM Converter ===" -ForegroundColor Yellow
    Write-Host "Version: 1.0.0`n" -ForegroundColor Gray
    
    Write-Host "Loading config file: $ConfigPath" -ForegroundColor Cyan
    $config = Load-Config -Path $ConfigPath
    Write-Host "[OK] Config loaded successfully" -ForegroundColor Green
    Write-Host "  - Repository: $($config.repositoryUrl)" -ForegroundColor Gray
    Write-Host "  - Application: $($config.applicationId) v$($config.applicationVersion)" -ForegroundColor Gray
    
    if ($ReportType -eq 'auto') {
        $ReportType = Detect-ReportType -CsvPath $CsvPath
        Write-Host "[OK] Auto-detected report type: $ReportType" -ForegroundColor Green
    }
    
    $result = Convert-QSEtoGCM -CsvPath $CsvPath -Config $config -Type $ReportType
    
    $outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    Write-Host "`nWriting output file: $OutputPath" -ForegroundColor Cyan
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    
    Write-Host "[OK] Conversion completed!" -ForegroundColor Green
    Write-Host "`nOutput file: $OutputPath" -ForegroundColor Yellow
    Write-Host "Total converted: $($result.findings.assets[0].functionCalls.Count) crypto objects`n" -ForegroundColor Green
    
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Login to GCM Web UI" -ForegroundColor Gray
    Write-Host "2. Navigate to Asset Discovery > Import Profiles" -ForegroundColor Gray
    Write-Host "3. Select 'QSE analytics findings report' or 'QSE discovery findings report'" -ForegroundColor Gray
    Write-Host "4. Upload $OutputPath`n" -ForegroundColor Gray
}
catch {
    Write-Host "`n[ERROR] $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}