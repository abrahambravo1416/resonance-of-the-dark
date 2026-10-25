param(
	[int]$Port = 8765,
	[string]$SpoolDir = "",
	[string]$ServerPath = ""
)

$ErrorActionPreference = "Stop"
$projectUrl = "https://nqcabupndnyvlhgvenwq.supabase.co"
$credentialPath = Join-Path $env:LOCALAPPDATA "ResonanceOfTheDark\supabase.secret.dpapi"

if (Test-Path -LiteralPath $credentialPath) {
	try {
		$encryptedSecret = (Get-Content -LiteralPath $credentialPath -Raw).Trim()
		$secureSecret = ConvertTo-SecureString -String $encryptedSecret
		$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
		try {
			$env:SUPABASE_SECRET_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
		} finally {
			[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
		}
		$env:SUPABASE_URL = $projectUrl
	} catch {
		Write-Warning "No se pudo leer la credencial protegida de Supabase. El panel arrancará en modo local."
	}
}

if ([string]::IsNullOrWhiteSpace($ServerPath) -or -not (Test-Path -LiteralPath $ServerPath)) {
	Write-Error "No se encontró telemetry/server.py."
	exit 1
}

# Si quedó abierto el panel iniciado por una ejecución anterior del juego, reinicia solo ese servidor.
$normalizedServerPath = [IO.Path]::GetFullPath($ServerPath).Replace("/", "\")
$listenerIds = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
	Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($listenerId in $listenerIds) {
	$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerId" -ErrorAction SilentlyContinue
	if ($null -ne $processInfo -and $processInfo.CommandLine -and
		$processInfo.CommandLine.Replace("/", "\").IndexOf($normalizedServerPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
		Stop-Process -Id $listenerId -Force -ErrorAction SilentlyContinue
	}
}
for ($attempt = 0; $attempt -lt 20; $attempt++) {
	$stillListening = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
	if ($stillListening.Count -eq 0) { break }
	Start-Sleep -Milliseconds 250
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
	$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
	if ($null -eq $pythonLauncher) {
		Write-Error "No se encontró Python. Instala Python 3 o agrega python.exe al PATH."
		exit 1
	}
	$pythonArgs = @("-3", $ServerPath, "--port", "$Port")
} else {
	$pythonArgs = @($ServerPath, "--port", "$Port")
}
if (-not [string]::IsNullOrWhiteSpace($SpoolDir)) {
	$pythonArgs += @("--spool-dir", $SpoolDir)
}

$logDirectory = Join-Path $env:LOCALAPPDATA "ResonanceOfTheDark"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory "dashboard.log"

if ($null -eq $python) {
	& $pythonLauncher.Source @pythonArgs *> $logPath
} else {
	& $python.Source @pythonArgs *> $logPath
}
exit $LASTEXITCODE
