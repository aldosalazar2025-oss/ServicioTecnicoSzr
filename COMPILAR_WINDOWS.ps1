$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
Write-Host 'Preparando proyecto Flutter para Windows...'
flutter create --platforms=windows .
if ($LASTEXITCODE -ne 0) { throw 'flutter create fallo' }
$icon = Join-Path $PSScriptRoot 'windows_icon\app_icon.ico'
$target = Join-Path $PSScriptRoot 'windows\runner\resources\app_icon.ico'
Copy-Item -LiteralPath $icon -Destination $target -Force
$cpp = Join-Path $PSScriptRoot 'windows\runner\main.cpp'
$source = [System.IO.File]::ReadAllText($cpp)
if (-not $source.Contains('SZR_SINGLE_INSTANCE_V93')) {
  $source = '#include <windows.h>' + "`r`n" + $source
  $pattern = '(?s)(int APIENTRY wWinMain\s*\([^)]*\)\s*\{)'
  $injection = @'

  // SZR_SINGLE_INSTANCE_V93: prevent duplicate Windows processes.
  HANDLE szr_instance_mutex = CreateMutexW(nullptr, TRUE, L"Local\\ServicioTecnicoSZR_Instance");
  if (szr_instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(nullptr, L"Servicio Técnico SZR");
    if (existing == nullptr) existing = FindWindowW(nullptr, L"servicio_tecnico_szr");
    if (existing != nullptr) {
      if (IsIconic(existing)) ShowWindow(existing, SW_RESTORE);
      ShowWindow(existing, SW_SHOW);
      SetForegroundWindow(existing);
    }
    CloseHandle(szr_instance_mutex);
    return 0;
  }
'@
  $new = [regex]::Replace($source, $pattern, { param($m) $m.Value + $injection }, 1)
  if ($new -eq $source) { throw 'No se encontro wWinMain en windows/runner/main.cpp. Envia este archivo para ajustar el parche.' }
  [System.IO.File]::WriteAllText($cpp, $new, (New-Object System.Text.UTF8Encoding($false)))
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get fallo' }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Compilacion fallo: revisa el mensaje anterior' }
Write-Host 'LISTO: revisa build\windows\x64\runner\Release' -ForegroundColor Green
