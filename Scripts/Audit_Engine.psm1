Function Invoke-CISAudit {
    param (
        [string]$JsonPath = ".\CIS_Rules_DB.json",
        [string]$OutputPath = ".\Audit_Result.json"
    )

    Write-Host ">>> STARTING CIS AUDIT ENGINE <<<" -ForegroundColor Cyan
    
    # Doc du lieu tu cac file Rules JSON
    $JsonData = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json
    $Rules = $JsonData.rules
    $Results = @()

    foreach ($Rule in $Rules) {
        $Status = $false
        $CurrentValue = "N/A"

        # 1. Xu ly Registry / Service
        if ($Rule.intervention_type -eq "Registry" -or $Rule.intervention_type -eq "Service") {
            try {
                # Format Path
                $RegPath = $Rule.path -replace "^HKLM\\", "HKLM:\" -replace "^HKCU\\", "HKCU:\"
                
                # Truy van Path tren may
                $Item = Get-ItemProperty -Path $RegPath -ErrorAction Stop
                $CurrentValue = $Item.$($Rule.key_name)

                # TAp dung thuat toan so sanh dua tren logic cua Rule
                if ($CurrentValue -ne $null) {
                    if ($Rule.rule_logic.operator -eq "==" -and $CurrentValue -eq $Rule.rule_logic.value) { $Status = $true }
                    elseif ($Rule.rule_logic.operator -eq ">=" -and $CurrentValue -ge $Rule.rule_logic.value) { $Status = $true }
                    elseif ($Rule.rule_logic.operator -eq "<=" -and $CurrentValue -le $Rule.rule_logic.value) { $Status = $true }
                }
            } catch {
                $Status = $false # Error
            }
        }
        # 2. Xu ly Secpol / Secedit
        else {
            # Vi Secpol can file .inf phuc tap --> danh dau Fail de Remediate xu ly
            $Status = $false 
            $CurrentValue = "Needs Secedit Check"
        }

        # In ket qua ra man hinh
        if ($Status) {
            Write-Host "[PASS] Rule $($Rule.id) - $($Rule.name)" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Rule $($Rule.id) - $($Rule.name) (Current: $CurrentValue, Expected: $($Rule.expected_value_raw))" -ForegroundColor Red
        }

        # Luu ket qua
        $Results += [PSCustomObject]@{
            RuleID = $Rule.id
            Name = $Rule.name
            InterventionType = $Rule.intervention_type
            IsCompliant = $Status
            RuleData = $Rule
        }
    }

    # Xuat file ket qua
    $Results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host ">>> AUDIT COMPLETED! Results saved to $OutputPath <<<" -ForegroundColor Cyan
}

Export-ModuleMember -Function Invoke-CISAudit