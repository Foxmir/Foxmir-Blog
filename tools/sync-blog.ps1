$ErrorActionPreference = 'Stop'

$project = $env:BLOG_PROJECT
$publish = $env:BLOG_PUBLISH

if ([string]::IsNullOrWhiteSpace($project)) {
    $project = 'D:\Quarto\Foxmir_blog'
}
if ([string]::IsNullOrWhiteSpace($publish)) {
    $publish = Join-Path $project 'publish'
}

function ConvertTo-Slug {
    param([Parameter(Mandatory = $true)][string]$Name)

    $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9_-]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $md5 = [Security.Cryptography.MD5]::Create()
        $bytes = [Text.Encoding]::UTF8.GetBytes($Name)
        $hash = ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        $slug = 'category-' + $hash.Substring(0, 8)
    }
    return $slug
}

function ConvertTo-YamlSingleQuoted {
    param([AllowNull()][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-YamlPlainPath {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '\\', '/')
}

Get-ChildItem $project -Filter '*.qmd' -File |
    Where-Object {
        (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'AUTO-GENERATED-CATEGORY-PAGE'
    } |
    Remove-Item -Force

$dirs = @(Get-ChildItem $publish -Directory | Where-Object { $_.Name -notmatch '^[._]' } | Sort-Object Name)
$items = @()
$used = @{}

foreach ($dir in $dirs) {
    $slug = ConvertTo-Slug $dir.Name
    if ($used.ContainsKey($slug)) {
        $slug = $slug + '-' + ($used.Count + 1)
    }
    $used[$slug] = $true

    $items += [pscustomobject]@{
        Name = $dir.Name
        Slug = $slug
    }

    $contentsPath = ConvertTo-YamlPlainPath ('publish/' + $dir.Name)
    $page = @(
        '---'
        'title: ' + (ConvertTo-YamlSingleQuoted $dir.Name)
        'listing:'
        '  contents: ' + $contentsPath
        '  sort: "date desc"'
        '  type: default'
        '  categories: true'
        '---'
        ''
        '<!-- AUTO-GENERATED-CATEGORY-PAGE: edit folders/posts in Obsidian, not this file. -->'
    )
    Set-Content -LiteralPath (Join-Path $project ($slug + '.qmd')) -Value $page -Encoding UTF8
}

$config = @(
    'project:'
    '  type: website'
    '  output-dir: docs'
    ''
    'website:'
    '  title: "Foxmir Blog"'
    '  navbar:'
    '    left:'
    '      - href: index.qmd'
    '        text: Home'
    '      - href: about.qmd'
    '        text: About'
)

foreach ($item in $items) {
    $config += '      - href: ' + $item.Slug + '.qmd'
    $config += '        text: ' + (ConvertTo-YamlSingleQuoted $item.Name)
}

$config += @(
    ''
    'format:'
    '  html:'
    '    theme: Superhero'
    '    css: styles.css'
    '    toc: true'
)

Set-Content -LiteralPath (Join-Path $project '_quarto.yml') -Value $config -Encoding UTF8
Write-Host ('Generated categories: ' + (($items | ForEach-Object { $_.Name }) -join ', '))
