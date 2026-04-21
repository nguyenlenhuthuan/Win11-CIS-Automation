$Clients = @("172.16.100.11", "172.16.100.12")
$ServerLogPath = "..\Logs\Compliance_Report.csv"

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

# Fix lỗi mảng Array: Dùng vòng lặp gửi file cho từng máy 
foreach ($s in $Sessions) {
    Copy-Item -Path "..\Configs\CIS_Rules_DB.json" -Destination "C:\CIS_Temp\" -ToSession $s
    Copy-Item -Path "..\Scripts\Audit_Engine.psm1" -Destination "C:\CIS_Temp\" -ToSession $s
    Copy-Item -Path "..\Scripts\Remediate_Engine.psm1" -Destination "C:\CIS_Temp\" -ToSession $s
}

# 3. Ra lệnh cho Client tự động chạy tiến trình ngầm
Write-Host ">>> [3] DANG THUC THI AUDIT & REMEDIATE TREN CLIENTS... <<<" -ForegroundColor Yellow
$RawResults = Invoke-Command -Session $Sessions -ScriptBlock {
    # THÊM DÒNG NÀY ĐỂ MỞ KHÓA CHO CLIENT:
    Set-ExecutionPolicy Bypass -Scope Process -Force

    Set-Location "C:\CIS_Temp"
    
    # Nạp module vào bộ nhớ Client
    Import-Module .\Audit_Engine.psm1 -Force
    Import-Module .\Remediate_Engine.psm1 -Force

    # Chạy quy trình
    Invoke-CISAudit -JsonPath ".\CIS_Rules_DB.json" -OutputPath ".\Audit_Result.json"
    Invoke-CISRemediate -AuditResultPath ".\Audit_Result.json"

    # Lấy kết quả trả về Server
    $ResultData = Get-Content -Path ".\Audit_Result.json" -Raw | ConvertFrom-Json
    return $ResultData
}

# 4. Server tổng hợp dữ liệu và xuất báo cáo CSV
Write-Host ">>> [4] DANG TONG HOP DU LIEU KIEM TOAN... <<<" -ForegroundColor Yellow
$ReportData = @()

foreach ($Item in $RawResults) {
    $ReportData += [PSCustomObject]@{
        Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Hostname         = $Item.PSComputerName 
        PolicyID         = $Item.RuleID
        PolicyName       = $Item.Name
        InterventionType = $Item.InterventionType
        Status           = if ($Item.IsCompliant) { "Dat (True)" } else { "Canh bao (False)" }
    }
}

$ReportData | Export-Csv -Path $ServerLogPath -NoTypeInformation -Encoding UTF8
Write-Host ">>> [5] HOAN TAT! Bao cao da duoc ket xuat tai: $ServerLogPath <<<" -ForegroundColor Green

# Dọn dẹp phiên kết nối
Remove-PSSession -Session $Sessions
