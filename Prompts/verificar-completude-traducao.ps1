param(
    [string]$Root = ".",
    [double]$MinRatio = 0.60,
    [double]$MaxRatio = 1.80,
    [switch]$ShowOnlyIssues,
    [string]$ExportCsv = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-OriginalPathFromPtBrFile {
    param([System.IO.FileInfo]$PtFile)

    $directory = $PtFile.DirectoryName
    $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($PtFile.Name)
    $extension = $PtFile.Extension

    if ($nameWithoutExtension -notmatch "_pt-BR$") {
        return $null
    }

    $originalNameWithoutExtension = $nameWithoutExtension -replace "_pt-BR$", ""
    $originalName = "$originalNameWithoutExtension$extension"
    return Join-Path $directory $originalName
}

function Get-StatusFromRatio {
    param(
        [double]$Ratio,
        [double]$MinRatioThreshold,
        [double]$MaxRatioThreshold
    )

    if ($Ratio -lt $MinRatioThreshold) {
        return "Possivel_Incompleto"
    }

    if ($Ratio -gt $MaxRatioThreshold) {
        return "Possivel_Excesso"
    }

    return "OK"
}

$ptFiles = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
    $_.BaseName -match "_pt-BR$"
}

if (-not $ptFiles) {
    Write-Host "Nenhum arquivo _pt-BR encontrado em '$Root'."
    exit 0
}

$results = @()

foreach ($ptFile in $ptFiles) {
    $originalPath = Get-OriginalPathFromPtBrFile -PtFile $ptFile

    if (-not $originalPath -or -not (Test-Path -LiteralPath $originalPath -PathType Leaf)) {
        $results += [PSCustomObject]@{
            Status            = "Original_Nao_Encontrado"
            ArquivoOriginal   = $originalPath
            ArquivoPtBr       = $ptFile.FullName
            BytesOriginal     = $null
            BytesPtBr         = $ptFile.Length
            ProporcaoPtBr     = $null
            DiferencaAbsoluta = $null
        }
        continue
    }

    $originalFile = Get-Item -LiteralPath $originalPath

    if ($originalFile.Length -eq 0) {
        $ratio = if ($ptFile.Length -eq 0) { 1.0 } else { [double]::PositiveInfinity }
    }
    else {
        $ratio = [math]::Round($ptFile.Length / $originalFile.Length, 4)
    }

    $status = Get-StatusFromRatio -Ratio $ratio -MinRatioThreshold $MinRatio -MaxRatioThreshold $MaxRatio
    $diff = $ptFile.Length - $originalFile.Length

    $results += [PSCustomObject]@{
        Status            = $status
        ArquivoOriginal   = $originalFile.FullName
        ArquivoPtBr       = $ptFile.FullName
        BytesOriginal     = $originalFile.Length
        BytesPtBr         = $ptFile.Length
        ProporcaoPtBr     = $ratio
        DiferencaAbsoluta = $diff
    }
}

$display = if ($ShowOnlyIssues) {
    $results | Where-Object { $_.Status -ne "OK" }
}
else {
    $results
}

if (-not $display) {
    Write-Host "Nenhum problema encontrado com os limiares atuais."
}
else {
    $display |
        Sort-Object Status, ProporcaoPtBr |
        Format-Table Status, ProporcaoPtBr, BytesOriginal, BytesPtBr, ArquivoPtBr -AutoSize
}

$total = $results.Count
$ok = ($results | Where-Object { $_.Status -eq "OK" }).Count
$issues = $total - $ok

Write-Host ""
Write-Host "Resumo:"
Write-Host "  Total de pares avaliados: $total"
Write-Host "  OK: $ok"
Write-Host "  Com alerta: $issues"
Write-Host "  MinRatio: $MinRatio | MaxRatio: $MaxRatio"

if ($ExportCsv) {
    $results |
        Sort-Object Status, ProporcaoPtBr |
        Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "CSV exportado em: $ExportCsv"
}
