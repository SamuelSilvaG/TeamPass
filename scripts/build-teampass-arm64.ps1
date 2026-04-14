$ErrorActionPreference = "Stop"

$RegistryPush = "192.168.3.159:30500"
$RegistryPull = "localhost:30500"
$Repository = "teampass"
$Version = "3.1.7.5"
$Tag = "$Version-arm64-r5"
$ImagePush = "$RegistryPush/$Repository`:$Tag"
$ImagePull = "$RegistryPull/$Repository`:$Tag"
$BuilderName = "teampass-builder"
$EntrypointPath = Join-Path $PSScriptRoot "..\_upstream\TeamPass\docker\docker-entrypoint.sh"

Write-Host "Building $ImagePush locally with docker buildx..."

$entrypointContent = [System.IO.File]::ReadAllText($EntrypointPath)
$entrypointContent = $entrypointContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($EntrypointPath, $entrypointContent, [System.Text.UTF8Encoding]::new($false))

docker buildx inspect $BuilderName *> $null
if ($LASTEXITCODE -ne 0) {
  docker buildx create --name $BuilderName --use | Out-Null
} else {
  docker buildx use $BuilderName
}

docker buildx inspect --bootstrap | Out-Null

$buildArgs = @(
  "buildx", "build",
  "--platform", "linux/arm64",
  "--tag", $ImagePush,
  "--build-arg", "TEAMPASS_VERSION=$Version",
  "--output", "type=image,name=$ImagePush,push=true,registry.insecure=true",
  "_upstream"
)

docker @buildArgs

if ($LASTEXITCODE -ne 0) {
  throw "docker buildx build failed"
}

Write-Host "Image published for push as: $ImagePush"
Write-Host "Cluster image reference remains: $ImagePull"
