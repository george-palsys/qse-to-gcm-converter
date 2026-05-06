<#
.SYNOPSIS
    將 IBM QSE CSV 輸出轉換為 GCM 相容的 JSON 格式

.DESCRIPTION
    此腳本讀取 QSE 的 CSV 報告(API Discovery 或 Crypto Inventory),
    並轉換為 IBM Guardium Cryptographic Manager (GCM) 可接受的 JSON 格式。
    自動補充 GCM 所需的 repositoryUrl, applicationId 等必要欄位。

.PARAMETER CsvPath
    QSE CSV 檔案的路徑

.PARAMETER ConfigPath
    包含應用程式資訊的配置檔案路徑 (JSON 格式)

.PARAMETER OutputPath
    輸出 JSON 檔案的路徑 (預設: output.json)

.PARAMETER ReportType
    報告類型: 'api' (API Discovery) 或 'crypto' (Crypto Inventory)
    如果未指定,將自動偵測

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

# 設定錯誤處理
$ErrorActionPreference = "Stop"

# 載入配置檔案
function Load-Config {
    param([string]$Path)
    
    try {
        $config = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        
        # 驗證必要欄位
        if (-not $config.repositoryUrl) {
            throw "配置檔案缺少必要欄位: repositoryUrl"
        }
        if (-not $config.applicationId) {
            throw "配置檔案缺少必要欄位: applicationId"
        }
        if (-not $config.applicationVersion) {
            throw "配置檔案缺少必要欄位: applicationVersion"
        }
        
        return $config
    }
    catch {
        Write-Error "載入配置檔案失敗: $_"
        throw
    }
}

# 偵測報告類型
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
        # 讀取第一行來判斷
        $firstLine = Get-Content -Path $CsvPath -First 1
        if ($firstLine -match "Crypto Function") {
            return "crypto"
        }
        else {
            return "api"
        }
    }
}

# 轉換 CSV 為 function calls
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
        
        # 添加可選欄位
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

# 建立 metadata properties
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

# 主要轉換函數
function Convert-QSEtoGCM {
    param(
        [string]$CsvPath,
        [object]$Config,
        [string]$Type
    )
    
    Write-Host "讀取 CSV 檔案: $CsvPath" -ForegroundColor Cyan
    
    # 讀取 CSV
    $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
    
    Write-Host "找到 $($csvData.Count) 筆記錄" -ForegroundColor Green
    Write-Host "轉換為 GCM 格式..." -ForegroundColor Cyan
    
    # 轉換為 function calls
    $functionCalls = Convert-CsvToFunctionCalls -CsvData $csvData -Type $Type
    
    # 建立 GCM JSON 結構
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

# 主程式
try {
    Write-Host "`n=== QSE to GCM Converter ===" -ForegroundColor Yellow
    Write-Host "Version: 1.0.0`n" -ForegroundColor Gray
    
    # 載入配置
    Write-Host "載入配置檔案: $ConfigPath" -ForegroundColor Cyan
    $config = Load-Config -Path $ConfigPath
    Write-Host "✓ 配置載入成功" -ForegroundColor Green
    Write-Host "  - Repository: $($config.repositoryUrl)" -ForegroundColor Gray
    Write-Host "  - Application: $($config.applicationId) v$($config.applicationVersion)" -ForegroundColor Gray
    
    # 偵測報告類型
    if ($ReportType -eq 'auto') {
        $ReportType = Detect-ReportType -CsvPath $CsvPath
        Write-Host "✓ 自動偵測報告類型: $ReportType" -ForegroundColor Green
    }
    
    # 轉換
    $result = Convert-QSEtoGCM -CsvPath $CsvPath -Config $config -Type $ReportType
    
    # 確保輸出目錄存在
    $outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # 寫入 JSON
    Write-Host "`n寫入輸出檔案: $OutputPath" -ForegroundColor Cyan
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    
    Write-Host "✓ 轉換完成!" -ForegroundColor Green
    Write-Host "`n輸出檔案: $OutputPath" -ForegroundColor Yellow
    Write-Host "總共轉換: $($result.findings.assets[0].functionCalls.Count) 個加密物件`n" -ForegroundColor Green
    
    # 顯示下一步
    Write-Host "下一步:" -ForegroundColor Yellow
    Write-Host "1. 登入 GCM Web UI" -ForegroundColor Gray
    Write-Host "2. 導航至 Asset Discovery > Import Profiles" -ForegroundColor Gray
    Write-Host "3. 選擇 'QSE analytics findings report' 或 'QSE discovery findings report'" -ForegroundColor Gray
    Write-Host "4. 上傳 $OutputPath`n" -ForegroundColor Gray
}
catch {
    Write-Host "`n✗ 錯誤: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
