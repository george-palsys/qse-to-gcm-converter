# QSE to GCM Converter

將 IBM QSE (Quantum Safe Explorer) CSV 輸出轉換為 IBM Guardium Cryptographic Manager (GCM) 可接受的 JSON 格式。

## 問題背景

IBM QSE 只能輸出 CSV 格式的加密物件掃描結果,但 GCM 的 QSE import profile 需要特定的 JSON 結構,包含以下必要欄位:
- `repositoryUrl` - 程式碼儲存庫 URL
- `applicationId` - 應用程式識別碼
- `applicationVersion` - 應用程式版本
- `functionCalls` - 加密函數調用詳情

## 功能特色

- ✅ 將 QSE CSV 轉換為 GCM 相容的 JSON 格式
- ✅ 自動補充必要的 metadata 欄位
- ✅ 支援 API Discovery 和 Crypto Inventory 兩種報告類型
- ✅ 可配置的應用程式資訊
- ✅ 保留所有 QSE 掃描的加密物件詳細資訊

## 系統需求

- PowerShell 5.1 或更高版本
- Windows, Linux, 或 macOS
- IBM Guardium Cryptographic Manager (GCM) 2.0+

## 快速開始

### 1. 下載腳本

```powershell
git clone https://github.com/YOUR_USERNAME/qse-to-gcm-converter.git
cd qse-to-gcm-converter
```

### 2. 準備配置檔案

複製範例配置檔案並修改:

```powershell
Copy-Item examples\config.example.json config.json
```

編輯 `config.json`:

```json
{
  "repositoryUrl": "https://github.com/your-org/your-repo",
  "applicationId": "your-application-name",
  "applicationVersion": "1.0.0",
  "metadata": {
    "branch": "main",
    "product": "your-product-name",
    "ci_pipeline": "jenkins",
    "cd_pipeline": "argocd"
  }
}
```

### 3. 轉換 CSV 檔案

```powershell
# 轉換 API Discovery 報告
.\scripts\Convert-QSEtoGCM.ps1 -CsvPath "path\to\API discovery results.csv" -ConfigPath "config.json" -OutputPath "output\api_discovery.json"

# 轉換 Crypto Inventory 報告
.\scripts\Convert-QSEtoGCM.ps1 -CsvPath "path\to\Crypto inventory results.csv" -ConfigPath "config.json" -OutputPath "output\crypto_inventory.json"
```

### 4. 上傳到 GCM

1. 登入 GCM Web UI
2. 導航至 **Asset Discovery** > **Import Profiles**
3. 選擇 **QSE analytics findings report** 或 **QSE discovery findings report**
4. 點擊 **Upload** 並選擇轉換後的 JSON 檔案

## 使用說明

### 腳本參數

| 參數 | 必要 | 說明 | 預設值 |
|------|------|------|--------|
| `-CsvPath` | 是 | QSE CSV 檔案路徑 | - |
| `-ConfigPath` | 是 | 配置檔案路徑 | - |
| `-OutputPath` | 否 | 輸出 JSON 檔案路徑 | `output.json` |
| `-ReportType` | 否 | 報告類型: `api` 或 `crypto` | 自動偵測 |

### 配置檔案格式

```json
{
  "repositoryUrl": "https://github.com/org/repo",
  "applicationId": "app-name",
  "applicationVersion": "1.0.0",
  "metadata": {
    "branch": "main",
    "product": "product-name",
    "ci_pipeline": "jenkins",
    "cd_pipeline": "argocd",
    "revision_id": "abc123"
  }
}
```

## 輸出格式

轉換後的 JSON 符合 GCM QSE findings 格式:

```json
{
  "findings": {
    "assets": [
      {
        "repositoryUrl": "https://github.com/org/repo",
        "applicationId": "app-name",
        "applicationVersion": "1.0.0",
        "functionCalls": [
          {
            "functionName": "java.security.MessageDigest.getInstance",
            "location": {
              "fileName": "target/dependency/guava-15.0.jar",
              "line": 0,
              "startColumn": 0,
              "endColumn": 0
            },
            "cryptoProperties": {
              "library": "JCA",
              "primitive": "hash",
              "variant": "SHA2",
              "assetType": "algorithm"
            }
          }
        ]
      }
    ]
  },
  "metadata": {
    "properties": [
      {"name": "branch", "value": "main"},
      {"name": "product", "value": "product-name"}
    ]
  }
}
```

## 範例

查看 `examples/` 目錄中的範例檔案:
- `config.example.json` - 配置檔案範例
- `sample_api_discovery.csv` - API Discovery CSV 範例
- `sample_crypto_inventory.csv` - Crypto Inventory CSV 範例

## 故障排除

### Import 失敗: "No assets found"

**原因**: 缺少必要欄位 `repositoryUrl` 或 `applicationId`

**解決方案**: 確認 `config.json` 包含所有必要欄位

### Import 失敗: "Transformation failed"

**原因**: JSON 格式不符合 GCM 期望的結構

**解決方案**: 
1. 使用最新版本的轉換腳本
2. 檢查 GCM audit logs 查看詳細錯誤訊息
3. 驗證 CSV 檔案格式正確

### CSV 編碼問題

**原因**: CSV 檔案使用非 UTF-8 編碼

**解決方案**: 使用 `-Encoding UTF8` 參數或先轉換 CSV 編碼

## 貢獻

歡迎提交 Pull Requests 或回報 Issues!

## 授權

MIT License

## 相關連結

- [IBM Guardium Cryptographic Manager 文件](https://www.ibm.com/docs/en/guardium-cryptographic-manager)
- [IBM Quantum Safe Explorer](https://www.ibm.com/quantum/quantum-safe)
- [GCM API 文件](https://www.ibm.com/docs/en/guardium-cryptographic-manager/2.0?topic=api-reference)

## 更新日誌

### v1.0.0 (2026-05-06)
- 初始版本
- 支援 API Discovery 和 Crypto Inventory 報告轉換
- 自動補充 GCM 必要欄位
