# 실기기 벤치마크 — 측정이 끝나면 **스스로 종료한다.**
#
# `flutter run` 을 쓰지 않는다. 그것은 측정이 끝나도 hot reload 대기 상태로
# 계속 돌아서, 호출한 쪽이 도구 타임아웃까지 하염없이 기다리게 된다.
# 빌드 · 설치 · 실행 · 로그 수집을 분리하면 각 단계가 스스로 끝난다.
#
# 사용법 (source/android 에서):
#   pwsh tool/bench.ps1                    # 채택 팔레트로 측정
#   pwsh tool/bench.ps1 -Sea flat          # 단색과 교대 측정
#   pwsh tool/bench.ps1 -SkipBuild         # 이미 설치된 APK 로 다시 측정
param(
  [string]$Sea = 'cerulean',
  [int]$TimeoutSec = 240,
  [switch]$SkipBuild,
  [string]$Serial = 'R3CY50AX1HK'
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$pkg = 'kr.bangbang.mapscratch'
$apk = 'build\app\outputs\flutter-apk\app-profile.apk'

if (-not (Test-Path $adb)) { throw "adb 를 찾을 수 없다: $adb" }

# 기기 확인 — 비어 있으면 "보안 위험 자동 차단 해제" 를 사용자에게 요청해야 한다.
$devices = & $adb devices | Select-String -Pattern "$Serial\s+device"
if (-not $devices) {
  throw "기기 $Serial 가 붙어 있지 않다. 사용자에게 '보안 위험 자동 차단 해제' 를 요청할 것."
}

if (-not $SkipBuild) {
  Write-Host "[bench] 빌드 (SEA=$Sea)"
  & flutter build apk --profile --dart-define=AUTOBENCH=true --dart-define=SEA=$Sea
  if ($LASTEXITCODE -ne 0) { throw '빌드 실패' }

  Write-Host '[bench] 설치'
  # 설치 실패를 놓치면 옛 빌드가 돌아 "새 코드가 반영 안 됐다" 로 오진하게 된다.
  & $adb -s $Serial install -r $apk
  if ($LASTEXITCODE -ne 0) { throw '설치 실패' }
}

# 화면이 꺼지면 티커가 멈춰 프레임이 0 이 된다.
& $adb -s $Serial shell svc power stayon true | Out-Null
& $adb -s $Serial shell am force-stop $pkg | Out-Null
& $adb -s $Serial logcat -c | Out-Null

Write-Host '[bench] 실행'
& $adb -s $Serial shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null

# logcat 을 blocking 으로 읽되 종료 표지를 만나면 파이프라인을 끊는다.
# Start-Sleep 폴링이 아니라 이벤트 기반이라 대기가 늘어지지 않는다.
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$done = $false
$out = New-Object System.Collections.Generic.List[string]

& $adb -s $Serial logcat -v raw -s flutter:I | ForEach-Object {
  if ($_ -match '\[BENCH\]') {
    $out.Add($_)
    Write-Host $_
  }
  if ($_ -match '측정 종료') { $done = $true; break }
  if ((Get-Date) -gt $deadline) { break }
}

# logcat 프로세스가 남지 않게 정리한다.
Get-Process -Name 'adb' -ErrorAction SilentlyContinue |
  Where-Object { $_.StartTime -gt (Get-Date).AddSeconds(-$TimeoutSec - 60) } |
  Out-Null

& $adb -s $Serial shell am force-stop $pkg | Out-Null
& $adb -s $Serial shell svc power stayon false | Out-Null

if (-not $done) {
  Write-Host "[bench] 종료 표지를 못 봤다 ($TimeoutSec 초 초과). 위 로그를 확인할 것."
  exit 1
}
Write-Host '[bench] 완료 · stayon 복구'
