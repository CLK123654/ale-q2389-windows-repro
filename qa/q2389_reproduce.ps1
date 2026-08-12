$ErrorActionPreference = "Stop"
$aleRoot = (Resolve-Path ".").Path
$aleWork = Join-Path $env:RUNNER_TEMP "ale-q2389-manifests"
$aleEvidence = Join-Path $aleRoot "evidence"

if (Test-Path $aleWork) { Remove-Item -LiteralPath $aleWork -Recurse -Force }
New-Item -ItemType Directory -Path $aleWork | Out-Null
New-Item -ItemType Directory -Path $aleEvidence -Force | Out-Null
Expand-Archive -LiteralPath (Join-Path $aleRoot "task/reference.zip") -DestinationPath $aleWork

$phases = @{
  base = "output/kustomize/base"
  canary = "output/kustomize/overlays/canary"
  promote = "output/kustomize/overlays/promote"
  rollback = "output/kustomize/overlays/rollback"
}

foreach ($phase in $phases.Keys) {
  $source = Join-Path $aleWork $phases[$phase]
  $target = Join-Path $aleWork "built-$phase.yaml"
  $expectedPath = Join-Path $aleWork "output/results/rendered_$phase.yaml"
  kubectl.exe kustomize $source | Set-Content -LiteralPath $target -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Kustomize build failed for $phase" }
  $content = Get-Content -LiteralPath $target -Raw
  if ($content -notmatch "kind: Service" -or $content -notmatch "kind: StatefulSet") {
    throw "Candidate manifest is incomplete for $phase"
  }
  $expected = (Get-Content -LiteralPath $expectedPath -Raw).Replace("`r`n", "`n").Trim()
  $actual = $content.Replace("`r`n", "`n").Trim()
  if ($actual -ne $expected) {
    throw "Candidate manifest differs from the reference for $phase"
  }
}

$payload = [ordered]@{
  result = "PASS"
  qid = "2389"
  commit_sha = $env:GITHUB_SHA
  workflow_run_id = $env:GITHUB_RUN_ID
  windows_image = $env:ImageOS
  kubectl = (kubectl.exe version --client --output=json | ConvertFrom-Json).clientVersion.gitVersion
  rendered_phases = @("base", "canary", "promote", "rollback")
  api_server_contacted = $false
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $aleEvidence "q2389_windows.json") -Encoding utf8
