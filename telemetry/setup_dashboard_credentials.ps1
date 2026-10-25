$ErrorActionPreference = "Stop"

$credentialDirectory = Join-Path $env:LOCALAPPDATA "ResonanceOfTheDark"
$credentialPath = Join-Path $credentialDirectory "supabase.secret.dpapi"
New-Item -ItemType Directory -Path $credentialDirectory -Force | Out-Null

Write-Host "Pega la clave Secret de Supabase (sb_secret_...). La entrada no se mostrará y se protegerá para tu usuario de Windows."
$secret = Read-Host "Clave Secret" -AsSecureString
if ($secret.Length -eq 0) {
	throw "La clave está vacía; no se guardó ninguna credencial."
}

# Sin -Key, ConvertFrom-SecureString usa DPAPI en Windows: solo este usuario de Windows puede descifrarla.
$protectedSecret = ConvertFrom-SecureString -SecureString $secret
Set-Content -LiteralPath $credentialPath -Value $protectedSecret -Encoding ASCII
Write-Host "Credencial guardada de forma protegida en: $credentialPath"
Write-Host "El juego podrá iniciar localhost:8765 conectado a Supabase automáticamente."
