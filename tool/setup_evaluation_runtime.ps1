$ErrorActionPreference = 'Stop'
# Keep the optional evaluation environment inside ignored build output.
$runtimeRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'build/evaluation-runtime'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$pythonExe = Join-Path $runtimeRoot 'python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
    $archivePath = Join-Path $runtimeRoot 'python.zip'
    Invoke-WebRequest 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip' -OutFile $archivePath
    Expand-Archive -LiteralPath $archivePath -DestinationPath $runtimeRoot -Force
    $pathConfig = Join-Path $runtimeRoot 'python311._pth'
    $config = [IO.File]::ReadAllText($pathConfig).Replace('#import site', 'import site')
    [IO.File]::WriteAllText($pathConfig, $config)
}
$pipBootstrap = Join-Path $runtimeRoot 'get-pip.py'
if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot 'Lib/site-packages/pip'))) {
    Invoke-WebRequest 'https://bootstrap.pypa.io/get-pip.py' -OutFile $pipBootstrap
    & $pythonExe $pipBootstrap --no-cache-dir --disable-pip-version-check
    if ($LASTEXITCODE -ne 0) { throw 'pip bootstrap failed' }
}
& $pythonExe -m pip install --no-cache-dir --disable-pip-version-check 'ai-edge-litert==2.1.3' 'Pillow==11.1.0' 'numpy==2.2.4'
if ($LASTEXITCODE -ne 0) { throw 'Evaluation dependencies failed to install' }
