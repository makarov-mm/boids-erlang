# builds.ps1
$erlangBin = "C:\Program Files\Erlang OTP\bin"
if (-not (Test-Path "$erlangBin\erlc.exe")) {
    Write-Error "Erlang not found at $erlangBin - fix the path"
    exit 1
}
$env:Path = "$erlangBin;$env:Path"

New-Item -ItemType Directory -Path ebin -Force | Out-Null

erlc -o ebin src\boid.erl src\boid_sup.erl src\flock.erl
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed"
    exit 1
}

erl -pa ebin