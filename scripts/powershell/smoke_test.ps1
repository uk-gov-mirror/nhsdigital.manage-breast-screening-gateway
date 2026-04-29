#Requires -Version 5.1
<#
.SYNOPSIS
    Smoke test for the gateway services.
.DESCRIPTION
    Checks all 4 Windows services are Running, then sends a DICOM C-ECHO to the
    PACS server on localhost to verify it is accepting connections.
    Executed on the Arc-enabled VM via az connectedmachine run-command.
#>

$ErrorActionPreference = 'Stop'

Write-Output "=== Gateway Smoke Test ==="

# -- Service check ------------------------------------------------------------

$serviceNames = 'Gateway-PACS', 'Gateway-MWL', 'Gateway-Upload', 'Gateway-Relay'
foreach ($name in $serviceNames) {
    $svc = Get-Service -Name $name -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        throw "Service $name is not running (status: $($svc.Status))"
    }
    Write-Output "OK: $name is Running"
}

# -- DICOM C-ECHO -------------------------------------------------------------

$installPath = 'C:\Program Files\NHS\ManageBreastScreeningGateway\current'
if (-not (Test-Path $installPath)) {
    throw "Gateway install path not found: $installPath"
}

Set-Location $installPath
$env:PYTHONPATH = 'src'

$echoScript = @'
from pynetdicom import AE
from pynetdicom.sop_class import Verification
ae = AE()
ae.add_requested_context(Verification)
assoc = ae.associate("127.0.0.1", 4244)
if not assoc.is_established:
    raise SystemExit("PACS association failed — check Gateway-PACS service logs")
status = assoc.send_c_echo()
assoc.release()
if not status or status.Status != 0x0000:
    raise SystemExit("C-ECHO returned unexpected status: " + hex(status.Status if status else 0))
print("C-ECHO OK")
'@

$tempPy = Join-Path $env:TEMP 'gw_smoke_echo.py'
try {
    [System.IO.File]::WriteAllText($tempPy, $echoScript, [System.Text.Encoding]::UTF8)
    & '.venv\Scripts\python.exe' $tempPy
    if ($LASTEXITCODE -ne 0) {
        throw "DICOM C-ECHO failed (exit code: $LASTEXITCODE)"
    }
} finally {
    Remove-Item $tempPy -ErrorAction SilentlyContinue
}

Write-Output "=== Smoke test passed ==="
