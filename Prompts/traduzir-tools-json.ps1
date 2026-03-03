param(
    [string]$SourceDir = ".",
    [string]$OutputSuffix = "_pt-BR"
)

# Dicionário de tradução para campos comuns em tools.json
$translationMap = @{
    "description"   = "descricao"
    "parameters"    = "parametros"
    "properties"    = "propriedades"
    "items"         = "itens"
    "type"          = "tipo"
    "required"      = "obrigatorio"
    "string"        = "string"
    "object"        = "objeto"
    "array"         = "matriz"
    "boolean"       = "booleano"
    "number"        = "numero"
    "Example"       = "Exemplo"
    "Use this tool" = "Use esta ferramenta"
}

# Funciona somente com estrutura JSON tools - traduz descriptions mantendo commands/examples em inglês
function Translate-ToolsJson {
    param([string]$JsonPath)
    
    try {
        Write-Host "Processando: $JsonPath" -ForegroundColor Cyan
        
        $json = Get-Content $JsonPath -Raw | ConvertFrom-Json
        
        # Se é array
        if ($json -is [array]) {
            foreach ($tool in $json) {
                if ($tool.description) {
                    # Traduz description mantendo nomes de ferramentas
                    $tool.description = Translate-Description $tool.description
                }
                if ($tool.parameters -and $tool.parameters.properties) {
                    foreach ($prop in $tool.parameters.properties.PSObject.Properties) {
                        if ($prop.Value.description) {
                            $prop.Value.description = Translate-Description $prop.Value.description
                        }
                    }
                }
            }
        }
        
        $outputPath = $JsonPath -replace '\.json$', "$OutputSuffix.json"
        $json | ConvertTo-Json -Depth 100 | Out-File -FilePath $outputPath -Encoding UTF8
        
        Write-Host "✓ Salvo: $outputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Erro: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Translate-Description {
    param([string]$Text)
    
    # Como não temos acesso a API de tradução, apenas marcamos como necessário tradução
    # Em produção, integraria com Google Translate API ou similar
    if ($Text.Length -gt 200) {
        return "[TRADUÇÃO NECESSÁRIA - Descrição longa]`n$Text"
    }
    
    # Retorna o texto original (em produção seria traduzido automaticamente)
    return $Text
}

# Localiza todos os tools.json
$toolsFiles = Get-ChildItem -Path $SourceDir -Recurse -Filter "tools.json" -ErrorAction SilentlyContinue
$toolsFiles += Get-ChildItem -Path $SourceDir -Recurse -Filter "*Tools.json" -ErrorAction SilentlyContinue
$toolsFiles += Get-ChildItem -Path $SourceDir -Recurse -Filter "*tools.json" -ErrorAction SilentlyContinue
$toolsFiles = $toolsFiles | Select-Object -Unique

if ($toolsFiles.Count -eq 0) {
    Write-Host "Nenhum arquivo tools.json encontrado." -ForegroundColor Yellow
    exit 1
}

Write-Host "Encontrados $($toolsFiles.Count) arquivo(s) tools.json`n" -ForegroundColor Cyan

$processed = 0
foreach ($file in $toolsFiles) {
    if (Translate-ToolsJson $file.FullName) {
        $processed++
    }
}

Write-Host "`n✓ Processados: $processed de $($toolsFiles.Count) arquivos" -ForegroundColor Green
