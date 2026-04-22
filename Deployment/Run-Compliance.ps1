$Clients = @("172.16.100.11", "172.16.100.12")
$LogBefore = "..\Logs\Compliance_Report_Before.csv"
$LogAfter = "..\Logs\Compliance_Report_After.csv"

Write-Host ">>> [1] KHOI DONG LUONG DIEU PHOI WINRM <<<" -ForegroundColor Cyan

# 1. Tạo phiên kết nối WinRM đa luồng đến các máy Client
$Password = ConvertTo-SecureString "nguyendinhtri" -AsPlainText -Force
$Credentials = New-Object System.Management.Automation.PSCredential ("pca", $Password)
$Sessions = New-PSSession -ComputerName $Clients -Credential $Credentials

# 2. Chuẩn bị môi trường và đẩy file sang Client
Write-Host ">>> [2] DANG DONG GOI VA DAY SCRIPT SANG CLIENTS... <<<" -ForegroundColor Yellow
Invoke-Command -Session $Sessions -ScriptBlock {
    if (!(Test-Path "C:\CIS_Temp")) { New-Item -ItemType Directory -Force -Path "C:\CIS_Temp" | Out-Null }
}

foreach ($s in $Sessions) {
    Copy-Item -Path "..\Configs\CIS_Rules_DB.json" -Destination "C:\CIS_Temp\" -ToSession $s
    Copy-Item -Path "..\Scripts\Audit_Engine.psm1" -Destination "C:\CIS_Temp\" -ToSession $s
    Copy-Item -Path "..\Scripts\Remediate_Engine.psm1" -Destination "C:\CIS_Temp\" -ToSession $s
}

# 3. Ra lệnh cho Client tự động chạy tiến trình ngầm (Re-Audit)
Write-Host ">>> [3] DANG THUC THI AUDIT & REMEDIATE TREN CLIENTS... <<<" -ForegroundColor Yellow
$RawResults = Invoke-Command -Session $Sessions -ScriptBlock {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Set-Location "C:\CIS_Temp"
    
    Import-Module .\Audit_Engine.psm1 -Force
    Import-Module .\Remediate_Engine.psm1 -Force

    # Lần 1: Quét hệ thống nguyên bản (Before)
    Invoke-CISAudit -JsonPath ".\CIS_Rules_DB.json" -OutputPath ".\Audit_Before.json"
    
    # Lần 2: Tự động khắc phục
    Invoke-CISRemediate -AuditResultPath ".\Audit_Before.json"

    # Lần 3: Xác minh tính toàn vẹn Re-Audit (After)
    Invoke-CISAudit -JsonPath ".\CIS_Rules_DB.json" -OutputPath ".\Audit_After.json"

    # Đóng gói cả 2 file gửi về Server
    $BeforeStr = Get-Content -Path ".\Audit_Before.json" -Raw
    $AfterStr = Get-Content -Path ".\Audit_After.json" -Raw
    return [PSCustomObject]@{ Before = $BeforeStr; After = $AfterStr }
}

# 4. Server tổng hợp dữ liệu và xuất 2 báo cáo CSV
Write-Host ">>> [4] DANG TONG HOP DU LIEU KIEM TOAN... <<<" -ForegroundColor Yellow
$ReportBefore = @()
$ReportAfter = @()

foreach ($Item in $RawResults) {
    $Hostname = $Item.PSComputerName
    $DataBefore = $Item.Before | ConvertFrom-Json
    $DataAfter = $Item.After | ConvertFrom-Json

    foreach ($rule in $DataBefore) {
        $ReportBefore += [PSCustomObject]@{
            Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Hostname         = $Hostname 
            PolicyID         = $rule.RuleID
            PolicyName       = $rule.Name
            InterventionType = $rule.InterventionType
            Status           = if ($rule.IsCompliant) { "Dat (True)" } else { "Canh bao (False)" }
        }
    }
    foreach ($rule in $DataAfter) {
        $ReportAfter += [PSCustomObject]@{
            Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Hostname         = $Hostname 
            PolicyID         = $rule.RuleID
            PolicyName       = $rule.Name
            InterventionType = $rule.InterventionType
            Status           = if ($rule.IsCompliant) { "Dat (True)" } else { "Canh bao (False)" }
        }
    }
}

$ReportBefore | Export-Csv -Path $LogBefore -NoTypeInformation -Encoding UTF8
$ReportAfter | Export-Csv -Path $LogAfter -NoTypeInformation -Encoding UTF8
Write-Host ">>> [5] HOAN TAT! Bao cao truoc fix: $LogBefore <<<" -ForegroundColor Green
Write-Host ">>> [5] HOAN TAT! Bao cao sau fix: $LogAfter <<<" -ForegroundColor Green

# Dọn dẹp phiên kết nối
Remove-PSSession -Session $Sessions