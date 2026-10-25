# SentinelShield - Local Runner for Windows (No Docker Required)
# Usage: .\run_local.ps1

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🛡️ SentinelShield - Starting Local Demo Environment    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Resolve Python executable
$pythonExe = $null
$candidates = @(
    "C:\Users\ADMIN\AppData\Local\Python\bin\python3.11.exe",
    "C:\Users\ADMIN\AppData\Local\Python\bin\python.exe",
    "py.exe",
    "python.exe"
)

foreach ($c in $candidates) {
    if (Get-Command $c -ErrorAction SilentlyContinue) {
        $pythonExe = $c
        break
    }
}

if (-not $pythonExe) {
    Write-Host "[ERROR] Python 3.11 was not found. Please ensure Python is installed." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Using Python: $pythonExe" -ForegroundColor Green

# 2. Setup Virtual Environment
if (-not (Test-Path -Path ".\.venv")) {
    Write-Host "[*] Creating virtual environment (.venv)..." -ForegroundColor Yellow
    & $pythonExe -m venv .venv
}

$venvPython = ".\.venv\Scripts\python.exe"
$venvStreamlit = ".\.venv\Scripts\streamlit.exe"

# 3. Install requirements
Write-Host "[*] Checking and installing required packages..." -ForegroundColor Yellow
& $venvPython -m pip install --quiet --upgrade pip
& $venvPython -m pip install --quiet -r protected_app/requirements.txt
& $venvPython -m pip install --quiet -r gateway/requirements.txt
& $venvPython -m pip install --quiet -r dashboard/requirements.txt

Write-Host "[*] Dependencies ready!" -ForegroundColor Green

# 4. Kill any previous lingering processes on ports 5001, 5000, 8501 if needed
$ports = @(5001, 5000, 8501)
foreach ($p in $ports) {
    $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
    if ($conns) {
        foreach ($conn in $conns) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
}

# 5. Launch Service 1: Protected App (Port 5001)
Write-Host "[1/3] Starting Protected App on http://localhost:5001..." -ForegroundColor Cyan
$p1 = Start-Process -FilePath $venvPython -ArgumentList "protected_app/app.py" -PassThru -WindowStyle Hidden

# 6. Launch Service 2: WAF Gateway (Port 5000)
Write-Host "[2/3] Starting WAF Gateway on http://localhost:5000..." -ForegroundColor Cyan
$env:PROTECTED_APP_URL = "http://localhost:5001"
$env:DB_PATH = "$PSScriptRoot\sentinelshield.db"
$env:API_SECRET = "sentinelshield-demo-secret"
$p2 = Start-Process -FilePath $venvPython -ArgumentList "gateway/app.py" -Environment @{
    PROTECTED_APP_URL = "http://localhost:5001"
    DB_PATH = "$PSScriptRoot\sentinelshield.db"
    API_SECRET = "sentinelshield-demo-secret"
    PYTHONUNBUFFERED = "1"
} -PassThru -WindowStyle Hidden

Start-Sleep -Seconds 2

# 7. Launch Service 3: Streamlit Dashboard (Port 8501)
Write-Host "[3/3] Starting Streamlit Dashboard on http://localhost:8501..." -ForegroundColor Cyan
$p3 = Start-Process -FilePath $venvStreamlit -ArgumentList "run dashboard/Home.py --server.port 8501 --server.headless true" -Environment @{
    GATEWAY_URL = "http://localhost:5000"
    API_SECRET = "sentinelshield-demo-secret"
    PYTHONUNBUFFERED = "1"
} -PassThru

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ ALL SERVICES RUNNING!" -ForegroundColor Green
Write-Host "  • Dashboard URL: http://localhost:8501" -ForegroundColor White
Write-Host "  • Gateway Health: http://localhost:5000/health" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Press Ctrl+C or close the terminal to stop."

# Wait for process exit or user break
try {
    $p3.WaitForExit()
} finally {
    Write-Host "`nStopping background services..." -ForegroundColor Yellow
    Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $p3.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned up." -ForegroundColor Gray
}

