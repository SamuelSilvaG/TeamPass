$ErrorActionPreference = "Stop"

$Version = "3.1.4.30"
$RegistryPush = "192.168.3.159:30500"
$Repository = "teampass"
$Tag = "$Version-arm64"
$ImagePush = "$RegistryPush/$Repository`:$Tag"
$TempDir = Join-Path $env:TEMP "teampass-$Version-build"

if (Test-Path $TempDir) {
  Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

Write-Host "Preparing build context for $Version..."

Push-Location $TempDir
try {
  git -C "c:\nso-repo\nso-teampass\_upstream" archive $Version | tar -xf -

  $dockerfilePath = Join-Path $TempDir "Dockerfile"
  $startScriptPath = Join-Path $TempDir "teampass-docker-start.sh"

  $dockerfile = [System.IO.File]::ReadAllText($dockerfilePath)
  $dockerfile = $dockerfile -replace 'FROM richarvey/nginx-php-fpm:latest', 'FROM docker.io/richarvey/nginx-php-fpm:latest'
  $dockerfile = $dockerfile -replace '#ENV GIT_TAG 3\.0\.0\.14', 'ENV GIT_TAG 3.1.4.30'
  [System.IO.File]::WriteAllText($dockerfilePath, $dockerfile, [System.Text.UTF8Encoding]::new($false))

  $startScript = [System.IO.File]::ReadAllText($startScriptPath)
  $startScript = $startScript -replace "`r`n", "`n"
  $watchBlock = @"

(
    while [ ! -f `${VOL}/includes/config/settings.php ];
    do
        sleep 5
    done
    rm -rf `${VOL}/install || true
) &
"@
  $startScript = $startScript -replace "(?s)# Pass off to the image's script\s*exec /start\.sh", ($watchBlock + "`n# Pass off to the image's script`nexec /start.sh")
  [System.IO.File]::WriteAllText($startScriptPath, $startScript, [System.Text.UTF8Encoding]::new($false))

  Write-Host "Building $ImagePush locally with docker buildx..."
  docker buildx build --platform linux/arm64 --tag $ImagePush --output "type=image,name=$ImagePush,push=true,registry.insecure=true" .
  if ($LASTEXITCODE -ne 0) {
    throw "docker buildx build failed"
  }

  Write-Host "Image published: $ImagePush"
}
finally {
  Pop-Location
  if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
  }
}
