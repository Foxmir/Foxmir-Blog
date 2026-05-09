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

function Get-YamlTitleLine {
    param([Parameter(Mandatory = $true)][string]$Title)

    return ('title: {0}' -f (ConvertTo-YamlSingleQuoted -Value $Title))
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $content = [string]::Join([Environment]::NewLine, $Lines) + [Environment]::NewLine
    $tempPath = $Path + '.tmp'
    $encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText($tempPath, $content, $encoding)
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Get-FileContentLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    return [regex]::Split($content, "`r`n|`n")
}

function Add-MissingTitleFrontMatter {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-FileContentLines -Path $Path
    $titleValue = [System.IO.Path]::GetFileNameWithoutExtension($Path)

    if ($lines.Length -ge 1 -and $lines[0] -eq '---') {
        $yamlEnd = -1
        for ($index = 1; $index -lt $lines.Length; $index++) {
            if ($lines[$index] -eq '---') {
                $yamlEnd = $index
                break
            }
        }

        if ($yamlEnd -gt 0) {
            $frontMatter = @($lines[1..($yamlEnd - 1)])
            $body = if ($yamlEnd + 1 -lt $lines.Length) { @($lines[($yamlEnd + 1)..($lines.Length - 1)]) } else { @() }

            if ($frontMatter -match '^title\s*:') {
                return
            }

            $newLines = @('---', (Get-YamlTitleLine -Title $titleValue)) + $frontMatter + @('---') + $body
            Write-Utf8File -Path $Path -Lines $newLines
            return
        }
    }

    $newLines = @(
        '---',
        (Get-YamlTitleLine -Title $titleValue),
        '---',
        ''
    ) + $lines
    Write-Utf8File -Path $Path -Lines $newLines
}

Get-ChildItem $publish -Recurse -File -Include '*.md' |
    Where-Object { $_.DirectoryName -notmatch '[\\/][._]' } |
    ForEach-Object {
        Add-MissingTitleFrontMatter -Path $_.FullName
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
        '  id: category-listing'
        '  contents: ' + $contentsPath
        '  sort: "file-modified desc"'
        '  type: default'
        '  categories: true'
        '---'
        ''
        '<!-- AUTO-GENERATED-CATEGORY-PAGE: edit folders/posts in Obsidian, not this file. -->'
        ''
        ':::{#category-listing}'
        ':::'
    )
    Write-Utf8File -Path (Join-Path $project ($slug + '.qmd')) -Lines $page
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

Write-Utf8File -Path (Join-Path $project '_quarto.yml') -Lines $config
Write-Host ('Generated categories: ' + (($items | ForEach-Object { $_.Name }) -join ', '))
