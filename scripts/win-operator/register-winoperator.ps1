# Register the register-operator task with NO trigger and start it once.
# No trigger + Start-ScheduledTask = exactly one run.
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File D:\tools\win-operator\register-operator.ps1'
$principal = New-ScheduledTaskPrincipal -UserId 'DESKTOP-51G968B\1' -LogonType Interactive
Register-ScheduledTask -TaskName 'Muse-Register-WinOperator' -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'Muse-Register-WinOperator'
Write-Output 'REGISTER-STARTED'
