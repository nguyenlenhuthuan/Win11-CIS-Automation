Function Invoke-CISRemediate {
    param (
        [string]$AuditResultPath = ".\Audit_Result.json"
    )

    Write-Host ">>> STARTING CIS REMEDIATION ENGINE <<<" -ForegroundColor Yellow
    
    $AuditData = Get-Content -Path $AuditResultPath -Raw | ConvertFrom-Json
    $FailedRules = $AuditData | Where-Object { $_.IsCompliant -eq $false }

    if ($FailedRules.Count -eq 0) {
        Write-Host "[INFO] All systems are compliant. No remediation needed." -ForegroundColor Green
        return
    }

    foreach ($Item in $FailedRules) {
        $Rule = $Item.RuleData

        if ($Rule.intervention_type -eq "Registry" -or $Rule.intervention_type -eq "Service") {
            try {
                $RegPath = $Rule.path -replace "^HKLM\\", "HKLM:\" -replace "^HKCU\\", "HKCU:\"
                
                # Kiem tra thu muc Registry co ton tai hay chua, neu chua thi tao moi
                if (!(Test-Path $RegPath)) {
                    New-Item -Path $RegPath -Force | Out-Null
                }

                # Phan loai DWORD / String
                $PropertyType = if ($Rule.registry_type -eq "DWORD") { "DWord" } else { "String" }

                # Ghi de cau hinh de fix loi
                Set-ItemProperty -Path $RegPath -Name $Rule.key_name -Value $Rule.expected_value_raw -Type $PropertyType -Force
                Write-Host "[FIXED] Rule $($Rule.id) ($($Rule.intervention_type)) -> Applied Value: $($Rule.expected_value_raw)" -ForegroundColor Green
            } catch {
                Write-Host "[ERROR] Could not fix Rule $($Rule.id): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        else {
            # Voi Secpol/Secedit, in ra huong dan lenh de chay thu cong hoac dung secedit
            Write-Host "[MANUAL FIX REQUIRED] Rule $($Rule.id) ($($Rule.intervention_type)): $($Rule.remediation)" -ForegroundColor DarkYellow
        }
    }
    Write-Host ">>> REMEDIATION COMPLETED <<<" -ForegroundColor Yellow
}

Export-ModuleMember -Function Invoke-CISRemediate