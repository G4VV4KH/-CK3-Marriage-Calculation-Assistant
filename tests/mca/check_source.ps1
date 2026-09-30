<#
Read-only MCA source checks. NOT a CK3 parser or a runtime/UI test.
The frozen GUI patch applies to pinned vanilla after CRLF -> LF normalization;
reconstruction must equal the pinned production GUI. No files are written.
#>
[CmdletBinding()]
param(
    [string]$McaRoot,
    [string]$GameRoot = 'D:\SteamLibrary\steamapps\common\Crusader Kings III\game'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($McaRoot)) {
    $McaRoot = Join-Path $PSScriptRoot '..\..\mod\marriage_calc_assistant'
}
$script:CheckCount = 0
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$Lf = [string][char]10
$CrLf = [string][char]13 + [char]10

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Set {
    param([string[]]$Actual, [string[]]$Expected, [string]$Label)
    $a = @($Actual | Sort-Object -CaseSensitive)
    $e = @($Expected | Sort-Object -CaseSensitive)
    Assert-True (($a.Count -eq $e.Count) -and (($a -join $Lf) -ceq ($e -join $Lf))) "$Label mismatch. Actual: $($a -join ', ')"
}
function Read-Utf8 {
    param([string]$Path)
    return $Utf8Strict.GetString([System.IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF)
}
function Count-Matches {
    param([string]$Text, [string]$Pattern)
    return [regex]::Matches($Text, $Pattern).Count
}
function Pass {
    param([string]$Label)
    $script:CheckCount++
    Write-Output "PASS $script:CheckCount - $Label"
}
function Lines-Lf {
    param([string]$Text)
    Assert-True ($Text.EndsWith($Lf)) 'Text must have a final LF'
    $lines = $Text.Replace($CrLf, $Lf).Split([char]10)
    return $lines[0..($lines.Length - 2)]
}
function Apply-FrozenPatchInMemory {
    param([string]$BaseText, [string]$PatchText)
    $src = @(Lines-Lf $BaseText)
    $patch = @(Lines-Lf $PatchText)
    Assert-True ($patch.Count -gt 2) 'Frozen patch is empty'
    Assert-True ($patch[0] -ceq '--- a/gui/interaction_marriage.gui') 'Wrong frozen patch source'
    Assert-True ($patch[1] -ceq '+++ b/gui/interaction_marriage.gui') 'Wrong frozen patch destination'
    $out = New-Object 'System.Collections.Generic.List[string]'
    $cursor = 0; $p = 2; $hunks = 0
    while ($p -lt $patch.Count) {
        Assert-True ($patch[$p] -match '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:.*)$') "Invalid patch hunk header at line $($p + 1)"
        $oldStart = [int]$Matches[1]
        $oldCount = if ([string]::IsNullOrEmpty($Matches[2])) { 1 } else { [int]$Matches[2] }
        $newStart = [int]$Matches[3]
        $newCount = if ([string]::IsNullOrEmpty($Matches[4])) { 1 } else { [int]$Matches[4] }
        $targetCursor = if ($oldCount -eq 0) { $oldStart } else { $oldStart - 1 }
        Assert-True ($targetCursor -ge $cursor -and $targetCursor -le $src.Count) 'Overlapping/out-of-range patch hunk'
        while ($cursor -lt $targetCursor) { $out.Add($src[$cursor]); $cursor++ }
        $expectedOutput = if ($newCount -eq 0) { $newStart } else { $newStart - 1 }
        Assert-True ($out.Count -eq $expectedOutput) 'Wrong patch output offset'
        $oldConsumed = 0; $newProduced = 0; $p++
        while ($p -lt $patch.Count -and -not $patch[$p].StartsWith('@@ ')) {
            $line = $patch[$p]
            Assert-True ($line.Length -gt 0) "Unprefixed empty patch line $($p + 1)"
            $body = $line.Substring(1)
            switch ($line[0]) {
                ' ' {
                    Assert-True ($cursor -lt $src.Count -and $src[$cursor] -ceq $body) "Patch context differs at vanilla line $($cursor + 1)"
                    $out.Add($body); $cursor++; $oldConsumed++; $newProduced++
                }
                '-' {
                    Assert-True ($cursor -lt $src.Count -and $src[$cursor] -ceq $body) "Patch removal differs at vanilla line $($cursor + 1)"
                    $cursor++; $oldConsumed++
                }
                '+' { $out.Add($body); $newProduced++ }
                default { throw "Unsupported patch prefix at line $($p + 1)" }
            }
            $p++
        }
        Assert-True ($oldConsumed -eq $oldCount -and $newProduced -eq $newCount) 'Patch hunk count mismatch'
        $hunks++
    }
    while ($cursor -lt $src.Count) { $out.Add($src[$cursor]); $cursor++ }
    Assert-True ($hunks -gt 0) 'Frozen patch has no hunks'
    return ($out.ToArray() -join $Lf) + $Lf
}
function Get-NamedBlock {
    param([string]$Text, [string]$Type, [string]$Name)
    $pattern = '(?m)^\s*' + [regex]::Escape($Type) + '\s*=\s*\{\s*\n\s*name\s*=\s*"' + [regex]::Escape($Name) + '"'
    $found = [regex]::Matches($Text, $pattern)
    Assert-True ($found.Count -eq 1) "Expected one $Type block named $Name"
    $open = $Text.IndexOf('{', $found[0].Index)
    $depth = 0; $quoted = $false; $escaped = $false; $comment = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($comment) { if ($ch -eq [char]10) { $comment = $false }; continue }
        if ($quoted) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $quoted = $false }
            continue
        }
        if ($ch -eq '#') { $comment = $true; continue }
        if ($ch -eq '"') { $quoted = $true; continue }
        if ($ch -eq '{') { $depth++ }
        if ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($open, $i - $open + 1) }
        }
    }
    throw "Unclosed $Name block"
}
function Assert-Structure {
    param([string]$Text, [string]$Label)
    $depth = 0; $quoted = $false; $escaped = $false; $comment = $false
    foreach ($ch in $Text.ToCharArray()) {
        if ($comment) { if ($ch -eq [char]10) { $comment = $false }; continue }
        if ($quoted) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $quoted = $false }
            continue
        }
        if ($ch -eq '#') { $comment = $true; continue }
        if ($ch -eq '"') { $quoted = $true; continue }
        if ($ch -eq '{') { $depth++ }
        if ($ch -eq '}') { $depth--; Assert-True ($depth -ge 0) "$Label has an unmatched closing brace" }
    }
    Assert-True ($depth -eq 0 -and -not $quoted) "$Label has unbalanced braces/strings"
}

function Remove-ScriptComments {
    param([string]$Text)
    # Preserve quoted GUI expressions and localization markup such as #low ... #!.
    return [regex]::Replace($Text, '"(?:\\.|[^"\\])*"|#[^\r\n]*', {
        param($Match)
        if ($Match.Value.StartsWith('#')) { return ' ' * $Match.Length }
        return $Match.Value
    })
}
function Get-GuiCallArguments {
    param([string]$Text, [int]$Open)
    $arguments = New-Object 'System.Collections.Generic.List[string]'
    $depth = 1; $quoted = $false; $escaped = $false; $start = $Open + 1
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($quoted) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq "'") { $quoted = $false }
            continue
        }
        if ($ch -eq "'") { $quoted = $true; continue }
        if ($ch -eq '(') { $depth++ }
        if ($ch -eq ')') { $depth-- }
        if (($ch -eq ',' -and $depth -eq 1) -or $depth -eq 0) {
            $arguments.Add($Text.Substring($start, $i - $start).Trim())
            $start = $i + 1
        }
        if ($depth -eq 0) { return [pscustomobject]@{ Arguments = $arguments.ToArray() } }
    }
    throw 'Standalone localization: unclosed GUI localization call'
}
function Get-GuiLocalizationBranchKeys {
    param([string]$Expression)
    $literal = [regex]::Match($Expression, "^'([A-Za-z_]\w*)'$")
    if ($literal.Success) { return $literal.Groups[1].Value }
    Assert-True ([regex]::IsMatch($Expression, '^Select_CString\s*\(')) "Standalone localization: unreviewed computed key $Expression"
    $call = Get-GuiCallArguments $Expression $Expression.IndexOf('(')
    Assert-True ($call.Arguments.Count -eq 3) 'Standalone localization: Select_CString needs three arguments'
    Get-GuiLocalizationBranchKeys $call.Arguments[1]
    Get-GuiLocalizationBranchKeys $call.Arguments[2]
}
function Assert-McaStandalone {
    param(
        [hashtable]$Sources, [string[]]$ValueNames, [string[]]$GuiNames,
        [string[]]$LocKeys, [System.Collections.Generic.HashSet[string]]$NativeLocKeys
    )
    $descriptorCode = Remove-ScriptComments $Sources['descriptor.mod']
    Assert-True (-not [regex]::IsMatch($descriptorCode, '\bdependencies\s*=')) 'Standalone dependency: MCA must declare no required mod'
    $code = (($Sources.Keys | Where-Object { $_ -match '\.(txt|gui)$' } | Sort-Object | ForEach-Object { Remove-ScriptComments $Sources[$_] }) -join "`n")
    $gui = (($Sources.Keys | Where-Object { $_ -match '\.gui$' } | Sort-Object | ForEach-Object { Remove-ScriptComments $Sources[$_] }) -join "`n")

    # All custom values, including Select_CString capture alternatives, are local.
    foreach ($match in [regex]::Matches($code, '\b[A-Za-z_]\w*_value\b')) {
        Assert-True ($ValueNames -ccontains $match.Value) "Standalone value: unresolved $($match.Value)"
    }
    foreach ($match in [regex]::Matches($gui, "\b(?:ScriptValue|GetScriptValueBreakdown)\(\s*'([A-Za-z_]\w*)'")) {
        Assert-True ($ValueNames -ccontains $match.Groups[1].Value) "Standalone value: unresolved $($match.Groups[1].Value)"
    }
    foreach ($match in [regex]::Matches($gui, "\bGetScriptedGui\(\s*'([A-Za-z_]\w*)'")) {
        Assert-True ($GuiNames -ccontains $match.Groups[1].Value) "Standalone scripted GUI: unresolved $($match.Groups[1].Value)"
    }

    # Optional adapter descriptions are the only intentionally external keys.
    # Accept each occurrence only inside its matching nonzero-component guard;
    # the standalone component must still be the exact formula-zero default.
    foreach ($side in @('p','r')) {
        foreach ($component in 1..4) {
            $key = "tnt_ma_adapter_$($side)_c$component"
            $value = $key + '_value'
            Assert-True ((Count-Matches $code ('(?m)^' + $value + '\s*=\s*\{\s*value\s*=\s*0\s*\}\s*$')) -eq 1) "Standalone adapter: $value must default to formula zero"
            $guard = 'if\s*=\s*\{\s*limit\s*=\s*\{\s*' + $value + '\s*!=\s*0\s*\}\s*add\s*=\s*\{\s*value\s*=\s*' + $value + '\s+desc\s*=\s*' + $key + '\s*\}\s*\}'
            $code = [regex]::Replace($code, $guard, '')
            Assert-True (-not [regex]::IsMatch($code, '\b' + $key + '\b')) "Standalone adapter: unguarded description $key"
        }
    }

    $locCode = (($Sources.Keys | Where-Object { $_ -match '\.yml$' } | Sort-Object | ForEach-Object { Remove-ScriptComments $Sources[$_] }) -join "`n")
    $locReferences = @([regex]::Matches($code, '\b(?:text|tooltip|desc)\s*=\s*"?([A-Za-z_]\w*)\b') | ForEach-Object { $_.Groups[1].Value })
    $locReferences += @([regex]::Matches($locCode, '\$([A-Za-z_]\w*)\$') | ForEach-Object { $_.Groups[1].Value })
    foreach ($match in [regex]::Matches($gui, '\bSelectLocalization\s*\(')) {
        $call = Get-GuiCallArguments $gui ($match.Index + $match.Length - 1)
        Assert-True ($call.Arguments.Count -eq 3) 'Standalone localization: SelectLocalization needs three arguments'
        $locReferences += @(Get-GuiLocalizationBranchKeys $call.Arguments[1])
        $locReferences += @(Get-GuiLocalizationBranchKeys $call.Arguments[2])
    }
    foreach ($key in $locReferences) {
        Assert-True (($LocKeys -ccontains $key) -or $NativeLocKeys.Contains($key)) "Standalone localization: unresolved $key"
    }

    # Scope aliases, variable/list names and GUI types are supplied locally,
    # not by a Parley session. Derive declarations instead of allowing tnt_ma_*.
    $localNames = @($ValueNames) + @($GuiNames) + @($LocKeys) + @('tnt_gr_me','tnt_gr_p','tnt_gr_side','tnt_sp_one')
    $localNames += @([regex]::Matches($code, '\b(?:name\s*=|type|save_temporary_scope_as\s*=)\s*"?(tnt_ma_\w+)\b') | ForEach-Object { $_.Groups[1].Value })
    $localNames += @([regex]::Matches($gui, "\bAddScope(?:Value)?\(\s*'(tnt_ma_\w+)'\s*,") | ForEach-Object { $_.Groups[1].Value })
    foreach ($match in [regex]::Matches($code + "`n" + $locCode, '\btnt_\w+\b')) {
        Assert-True ($localNames -ccontains $match.Value) "Standalone custom symbol: unresolved $($match.Value)"
    }
    Assert-True (-not [regex]::IsMatch($gui, '\bTnt\w+\s*\(')) 'Standalone GUI macro: Parley Tnt macro reference'
}

try {
    $mod = (Resolve-Path -LiteralPath $McaRoot).Path.TrimEnd([char[]]'\/')
    $game = (Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd([char[]]'\/')
    $languages = @('english','french','german','japanese','korean','polish','russian','simp_chinese','spanish')
    $expectedFiles = @(
        'descriptor.mod','README.md','thumbnail.png',
        'common/scripted_guis/tnt_ma_sort.txt',
        'common/script_values/tnt_ma_00_adapter_defaults.txt',
        'common/script_values/tnt_ma_52_grade.txt',
        'common/script_values/tnt_ma_sort_capture.txt',
        'gui/interaction_marriage.gui','gui/tnt_ma_character_list_item.gui'
    ) + @($languages | ForEach-Object { "localization/$_/tnt_ma_l_$_.yml" })
    $files = @(Get-ChildItem -LiteralPath $mod -Recurse -File -Force)
    $relative = @($files | ForEach-Object { $_.FullName.Substring($mod.Length + 1).Replace('\','/') })
    Assert-Set $relative $expectedFiles '18-file MCA inventory'
    $runtime = @($files | Where-Object { $_.Extension -in @('.txt','.gui','.yml','.mod') })
    $collisions = @($runtime | ForEach-Object {
        $rel = $_.FullName.Substring($mod.Length + 1).Replace('\','/')
        if (Test-Path -LiteralPath (Join-Path $game $rel) -PathType Leaf) { $rel }
    })
    Assert-Set $collisions @('gui/interaction_marriage.gui') 'Vanilla path allowlist'
    $descriptor = Read-Utf8 (Join-Path $mod 'descriptor.mod')
    Assert-True ((Count-Matches $descriptor '(?m)^version\s*=\s*"3\.1\.0"\s*$') -eq 1) 'Expected MCA descriptor version 3.1.0'
    Assert-True ((Count-Matches $descriptor '(?m)^supported_version\s*=\s*"1\.20\.\*"\s*$') -eq 1) 'Expected reviewed CK3 supported_version 1.20.*'
    Assert-True (-not [regex]::IsMatch((Remove-ScriptComments $descriptor), '\bdependencies\s*=')) 'Standalone dependency: MCA must declare no required mod'
    Pass 'exact 18-file inventory; version 3.1.0; only marriage GUI collides with vanilla'

    foreach ($file in $runtime) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        Assert-True ($bytes.Length -ge 3) "Empty runtime file: $($file.Name)"
        $bom = $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
        $needBom = $file.Extension -ne '.gui'
        Assert-True ($bom -eq $needBom) "Wrong UTF-8 BOM policy: $($file.FullName)"
        $offset = if ($bom) { 3 } else { 0 }
        $payload = $Utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset)
        Assert-True (-not $payload.Contains([string][char]0xFEFF)) "Interior U+FEFF: $($file.FullName)"
        Assert-True (-not $payload.Contains([string][char]13)) "Runtime text must be LF-only: $($file.FullName)"
        Assert-True ($payload.EndsWith($Lf)) "Missing final LF: $($file.FullName)"
    }
    Pass 'strict UTF-8, BOM for TXT/YML/descriptor only, LF, no interior BOM'

    $marriagePath = Join-Path $mod 'gui/interaction_marriage.gui'
    $vanillaPath = Join-Path $game 'gui/interaction_marriage.gui'
    $patchPath = Join-Path $PSScriptRoot 'interaction_marriage.ck3-1.20.patch'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $vanillaPath).Hash -ceq '8AB7AA6C6B4B778E8AAD62B06768B166996E9DAB5B5400CDDD56C7F5822CF6AD') 'Vanilla marriage GUI fingerprint changed; review patch against the new game file'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash -ceq '06BEA5CA90317C4ADFDE1F5E1713F7333683717ADB07284B418A3ADE4FF8A695') 'Frozen marriage patch changed'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $marriagePath).Hash -ceq 'AA033AE800C5F23ED7BFBFA58FFAC6A7E972B796498F9FD9738778087948163E') 'Production marriage GUI fingerprint changed; review and regenerate its frozen patch'
    $marriage = Read-Utf8 $marriagePath
    $rebuilt = Apply-FrozenPatchInMemory (Read-Utf8 $vanillaPath) (Read-Utf8 $patchPath)
    Assert-True ($rebuilt -ceq $marriage) 'Frozen patch does not reconstruct the exact LF production GUI'
    Pass 'pinned vanilla + frozen patch reconstruct exact production GUI in memory'

    $row = Read-Utf8 (Join-Path $mod 'gui/tnt_ma_character_list_item.gui')
    $carrier = Get-NamedBlock $row 'widget' 'tnt_ma_grade_carrier'
    $carrierProps = $carrier.Substring(0, $carrier.IndexOf('text_single'))
    foreach ($pattern in @('size\s*=\s*\{\s*126\s+26\s*\}','min_width\s*=\s*126\b','max_width\s*=\s*126\b','min_height\s*=\s*26\b','max_height\s*=\s*26\b')) {
        Assert-True ((Count-Matches $carrierProps $pattern) -eq 1) "Carrier property missing/duplicated: $pattern"
    }
    Assert-True (-not [regex]::IsMatch($carrierProps, '\bmargin_(left|right)\b')) 'Generic carrier cannot use box-only margins'
    $owners = @('tnt_ma_grade_p','tnt_ma_grade_p_alliance','tnt_ma_grade_r','tnt_ma_grade_r_alliance')
    foreach ($owner in $owners) {
        $body = Get-NamedBlock $row 'text_single' $owner
        foreach ($pattern in @('position\s*=\s*\{\s*6\s+0\s*\}','size\s*=\s*\{\s*112\s+26\s*\}','min_width\s*=\s*112\b','max_width\s*=\s*112\b','min_height\s*=\s*26\b','max_height\s*=\s*26\b','alwaystransparent\s*=\s*no\b','using\s*=\s*Font_Size_Medium\b')) {
            Assert-True ((Count-Matches $body $pattern) -eq 1) "$owner property missing/duplicated: $pattern"
        }
        Assert-True ((Count-Matches $body ('GetScriptValueBreakdown\(''' + $owner + '_value''\)')) -eq 2) "$owner must bind matching owner/popup breakdowns"
        Assert-True ((Count-Matches $body ('\.ScriptValue\(''' + $owner + '_value''\)')) -eq 1) "$owner must display the same grade value"
        Assert-True ((Count-Matches $body 'widget_value_breakdown_tooltip\s*=') -eq 1) "$owner is missing native breakdown tooltip"
    }
    $fonts = Read-Utf8 (Join-Path $game 'gui/preload/fonts.gui')
    Assert-True ([regex]::IsMatch($fonts, '(?s)template\s+Font_Size_Medium\s*\{\s*fontsize\s*=\s*18\b')) 'Native Medium font is no longer 18 px'
    Assert-True ((Count-Matches $row "\.AddScope\('actor',\s*GetPlayer\.MakeScope\)") -eq 16) 'Derived row must have 16 actor bindings'
    Assert-True ((Count-Matches $row '\.GetScriptValueBreakdown\(') -eq 8) 'Derived row must have 8 breakdown bindings'
    Assert-True (-not [regex]::IsMatch($row, "AddScope\('tnt_gr_me'|Font_Size_Tiny|blockoverride\s+""extra_skills""")) 'Retired row binding/layout returned'
    Pass '126 px carrier; four 112x26 interactive 18 px owners; actor16/breakdown8'

    Assert-True ((Count-Matches $marriage '(?m)^\s*tnt_ma_widget_character_list_item\s*=\s*\{') -eq 3) 'Expected native/sorted/pinned derived row sites'
    $columns = @([regex]::Matches($marriage, '(?m)^\s*addcolumn\s*=\s*(\d+)') | ForEach-Object { $_.Groups[1].Value })
    Assert-True ($columns.Count -eq 2 -and @($columns | Where-Object { $_ -cne '630' }).Count -eq 0) 'Native/sorted columns must both stay 630 px'
    Assert-True (-not [regex]::IsMatch($marriage, '\bscrollbox_properties\b|\b(?:650|697)\b|GetID|uint32|tnt_ma_sort_(?:probe_|id_lo|id_hi|trace_entry)')) 'Unexpected viewport override or retired identity/probe path'
    Assert-True ([regex]::IsMatch($marriage, '(?s)name\s*=\s*_show.*?Sound_WindowShow_Standard\s+on_start\s*=\s*"\[GetScriptedGui\(''tnt_ma_sort_clear''\)')) 'Window opening must clear stale saveable snapshots'
    Assert-True ((Count-Matches $marriage "ObjectsEqual\(\s*CharacterListItem\.GetCharacter,\s*Scope\.Char\s*\)") -eq 4) 'Expected row/watchdog identity checks and complements'
    Assert-True ((Count-Matches $marriage "GetList\('tnt_ma_sort_candidates'\)") -eq 2) 'Expected row/watchdog reference projections'
    Assert-True ((Count-Matches $marriage "GetScriptedGui\('tnt_ma_sort_collect'\)\.Execute\(\s*GuiScope\.SetRoot\(\s*CharacterListItem\.GetCharacter\.MakeScope\s*\)\.AddScope\('actor',\s*GetPlayer\.MakeScope\)") -eq 2) 'Both collectors must be candidate-rooted with the player actor'
    foreach ($side in @('left','right')) {
        $label = [regex]::Matches($marriage, '(?s)blockoverride\s+"' + $side + '_character_label"\s*\{([^{}]*)\}')
        Assert-True ($label.Count -eq 1) "Expected one $side spouse label override"
        Assert-True ($label[0].Groups[1].Value.Trim() -ceq 'text = "INTERACTION_SPOUSE"') "$side spouse label must not require a missing Character context"
    }
    Pass 'three marriage-only row sites, 630 px geometry, lifecycle/identity barriers, two neutral spouse labels'

    $sg = Read-Utf8 (Join-Path $mod 'common/scripted_guis/tnt_ma_sort.txt')
    $captures = Read-Utf8 (Join-Path $mod 'common/script_values/tnt_ma_sort_capture.txt')
    $grade = Read-Utf8 (Join-Path $mod 'common/script_values/tnt_ma_52_grade.txt')
    $defaults = Read-Utf8 (Join-Path $mod 'common/script_values/tnt_ma_00_adapter_defaults.txt')
    $gradeNames = @([regex]::Matches($grade, '(?m)^([a-zA-Z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value })
    $expectedGradeNames = @(
        'tnt_ma_grade_p_available_value','tnt_ma_grade_r_available_value',
        'tnt_ma_sg_p_c1_value','tnt_ma_sg_p_c2_value','tnt_ma_sg_p_c3_value','tnt_ma_sg_p_c4_value',
        'tnt_ma_sg_r_c1_value','tnt_ma_sg_r_c2_value','tnt_ma_sg_r_c3_value','tnt_ma_sg_r_c4_value',
        'tnt_ma_ally_ratio_value','tnt_ma_ally_worth_value','tnt_ma_genetic_value',
        'tnt_ma_skill_value','tnt_ma_age_value','tnt_ma_dynasty_value','tnt_ma_claim_value',
        'tnt_ma_grade_p_raw_value','tnt_ma_grade_r_raw_value',
        'tnt_ma_grade_p_value','tnt_ma_grade_p_alliance_value','tnt_ma_grade_r_value','tnt_ma_grade_r_alliance_value',
        'tnt_spouse_grade_value'
    )
    Assert-Set $gradeNames $expectedGradeNames 'Twenty-four core grade value definitions'
    $defaultNames = @([regex]::Matches($defaults, '(?m)^([a-zA-Z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value })
    $expectedDefaultNames = @(
        'tnt_ma_adapter_p_c1_value','tnt_ma_adapter_p_c2_value','tnt_ma_adapter_p_c3_value','tnt_ma_adapter_p_c4_value',
        'tnt_ma_adapter_r_c1_value','tnt_ma_adapter_r_c2_value','tnt_ma_adapter_r_c3_value','tnt_ma_adapter_r_c4_value',
        'tnt_ma_adapter_p_value','tnt_ma_adapter_r_value','tnt_ma_alliance_base_value'
    )
    Assert-Set $defaultNames $expectedDefaultNames 'Eleven core adapter/default definitions'
    foreach ($side in @('p','r')) {
        foreach ($component in 1..4) {
            $name = "tnt_ma_adapter_$($side)_c$($component)_value"
            Assert-True ((Count-Matches $defaults ('(?m)^' + $name + '\s*=\s*\{\s*value\s*=\s*0\s*\}\s*$')) -eq 1) "Adapter $name must be a zero formula, not a static scalar"
        }
    }
    $sgNames = @([regex]::Matches($sg, '(?m)^([a-zA-Z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value })
    Assert-Set $sgNames @('tnt_ma_sort_start','tnt_ma_sort_context_valid','tnt_ma_sort_collect','tnt_ma_sort_finalize','tnt_ma_sort_clear') 'Five private sorter SG definitions'
    $captureNames = @([regex]::Matches($captures, '(?m)^([a-zA-Z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value })
    Assert-Set $captureNames @('tnt_ma_sort_p_capture_value','tnt_ma_sort_p_alliance_capture_value','tnt_ma_sort_r_capture_value','tnt_ma_sort_r_alliance_capture_value') 'Four private capture values'
    $allValueNames = @($gradeNames) + @($defaultNames) + @($captureNames)
    Assert-True ($allValueNames.Count -eq 39 -and @($allValueNames | Sort-Object -Unique -CaseSensitive).Count -eq 39) 'Expected exactly 39 unique core script-value definitions'
    foreach ($side in @('p','r')) {
        foreach ($component in 1..4) {
            $name = "tnt_ma_sg_$($side)_c$($component)_value"
            Assert-True ((Count-Matches $grade ('(?m)^' + $name + '\s*=\s*\{\s*value\s*=\s*0\s*\}\s*$')) -eq 1) "Retired $name must remain an exact zero stub"
            Assert-True ((Count-Matches $grade ('\b' + $name + '\b')) -eq 1) "Retired $name must not feed any active calculation"
        }
    }
    foreach ($component in @('genetic','skill','age','dynasty','claim')) {
        $pattern = 'add\s*=\s*\{\s*value\s*=\s*tnt_ma_' + $component + '_value\s+desc\s*=\s*tnt_ma_grade_' + $component + '\s*\}'
        Assert-True ((Count-Matches $grade $pattern) -eq 6) "Shared $component must be directly described in both raw and all four GUI values"
    }
    $executableGrade = [regex]::Replace($grade, '#[^\n]*', '')
    Assert-True (-not [regex]::IsMatch($executableGrade, '\bopinion\(|\bis_councillor_of\b|\bhas_relation_\w+|\binspiration\b|\bhas_completed_inspiration\b|\btarget_is_liege_or_above\b|\bplayer_heir_position\b|\b(?:health|fertility|age)\s*(?:=|>=|<=|>|<)')) 'Retired acceptance or hidden/calendar-age inputs returned'
    Assert-True ((Count-Matches $grade '(?m)^\s*explicit\s*=\s*yes\s*$') -eq 2) 'Both claim passes must exclude implicit claims'
    Assert-True ((Count-Matches $captures '(?m)^\s*round\s*=\s*yes\s*$') -eq 4) 'All capture values must round to the displayed integer'
    Assert-True ((Count-Matches $captures '(?m)^\s*value\s*=\s*-10000\s*$') -eq 4) 'All capture values need the unavailable sentinel'
    foreach ($side in @('p','p_alliance','r','r_alliance')) {
        Assert-True ((Count-Matches $captures ('(?m)^\s*value\s*=\s*tnt_ma_grade_' + $side + '_value\s*$')) -eq 1) "Capture helper must reuse exact $side grade"
    }
    Assert-True (-not [regex]::IsMatch($sg, '\bdebug_log(?:_scopes)?\b|MCA_SORT_(?:STAGE|NEXT|MATRIX)|tnt_ma_sort_id_(?:lo|hi)')) 'Diagnostic logs or retired limb identity leaked into production'
    Pass '39 unique values, symmetric potential components, eight retired zero stubs, unchanged exact-grade sorting'

    $locKeys = @('tnt_ma_sort_score_button','tnt_ma_sort_native_button','tnt_ma_sort_help','tnt_ma_sort_collecting','tnt_ma_sort_active','tnt_ma_sort_failed')
    $allLocKeys = @(
        'tnt_ma_grade_genetic','tnt_ma_grade_title','tnt_ma_grade_help',
        'tnt_ma_grade_skill','tnt_ma_grade_age','tnt_ma_grade_dynasty','tnt_ma_grade_claim',
        'tnt_ma_grade_p_c1','tnt_ma_grade_p_c2','tnt_ma_grade_p_c3','tnt_ma_grade_p_c4',
        'tnt_ma_grade_r_c1','tnt_ma_grade_r_c2','tnt_ma_grade_r_c3','tnt_ma_grade_r_c4','tnt_ma_grade_alliance'
    ) + $locKeys
    foreach ($lang in $languages) {
        $loc = Read-Utf8 (Join-Path $mod "localization/$lang/tnt_ma_l_$lang.yml")
        Assert-True ($loc.StartsWith("l_$($lang):" + $Lf)) "Wrong locale header: $lang"
        $found = @([regex]::Matches($loc, '(?m)^\s*(tnt_ma_[a-z_0-9]+):\d*\s+') | ForEach-Object { $_.Groups[1].Value })
        Assert-Set $found $allLocKeys "Twenty-two core localization keys in $lang"
        foreach ($key in $allLocKeys) {
            Assert-True ([regex]::IsMatch($loc, '(?m)^\s*' + $key + ':\d*\s+"[^"\r\n]+"\s*$')) "Missing/empty single-line localization $lang/$key"
        }
    }
    Assert-True ((Count-Matches $marriage 'text\s*=\s*"tnt_ma_sort_score_button"') -eq 1) 'Score button localization binding'
    Assert-True ((Count-Matches $marriage 'text\s*=\s*"tnt_ma_sort_native_button"') -eq 1) 'Native button localization binding'
    Assert-True ((Count-Matches $marriage 'tooltip\s*=\s*"tnt_ma_sort_help"') -eq 2) 'Shared sorter help bindings'
    foreach ($key in @('tnt_ma_sort_collecting','tnt_ma_sort_active','tnt_ma_sort_failed')) {
        Assert-True ((Count-Matches $marriage ([regex]::Escape("'" + $key + "'"))) -eq 1) "State label binding: $key"
    }
    Pass 'all 22 core keys exist once in all nine locales; six control keys are GUI-bound'

    foreach ($file in @($runtime | Where-Object { $_.Extension -in @('.txt','.gui','.mod') })) {
        $text = Read-Utf8 $file.FullName
        Assert-Structure $text $file.Name
        if ($file.Extension -eq '.gui') {
            foreach ($match in [regex]::Matches($text, '(?m)^\s*[a-zA-Z_]+\s*=\s*"\[(.*)\]"\s*$')) {
                $depth = 0; $singleQuoted = $false
                foreach ($ch in $match.Groups[1].Value.ToCharArray()) {
                    if ($ch -eq "'") { $singleQuoted = -not $singleQuoted }
                    if (-not $singleQuoted) {
                        if ($ch -eq '(') { $depth++ }
                        if ($ch -eq ')') { $depth--; Assert-True ($depth -ge 0) "$($file.Name) has an unmatched expression ')'" }
                    }
                }
                Assert-True ($depth -eq 0 -and -not $singleQuoted) "$($file.Name) has an unbalanced GUI expression"
            }
        }
    }
    Pass 'static brace/string and GUI expression balance'

    $sources = @{}
    foreach ($file in $runtime) {
        $rel = $file.FullName.Substring($mod.Length + 1).Replace('\','/')
        $sources[$rel] = Read-Utf8 $file.FullName
    }
    $nativeLocKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $game 'localization/english') -Recurse -File -Filter '*.yml') {
        foreach ($match in [regex]::Matches((Read-Utf8 $file.FullName), '(?m)^\s*([A-Za-z_]\w*):\d*\s+')) {
            [void]$nativeLocKeys.Add($match.Groups[1].Value)
        }
    }
    Assert-McaStandalone $sources $allValueNames $sgNames $allLocKeys $nativeLocKeys
    Pass 'standalone closure: no required mod; local values/actions/state and MCA-or-vanilla localization'

    # Mutate in memory so these tests reach closure checks, not frozen GUI hashes.
    # These are real Parley-only names, but no Parley source is needed to run.
    $gradeRel = 'common/script_values/tnt_ma_52_grade.txt'
    $rowRel = 'gui/tnt_ma_character_list_item.gui'
    $locRel = 'localization/english/tnt_ma_l_english.yml'
    $negativeCases = @(
        @{ Label = 'required mod'; File = 'descriptor.mod'; Text = $descriptor + "dependencies = { `"Parley: The Negotiating Table`" }`n"; Error = 'Standalone dependency:' },
        @{ Label = 'Parley script value'; File = $gradeRel; Text = $grade.Replace('value = tnt_ma_skill_value', 'value = tnt_balance_value'); Error = 'Standalone value: unresolved tnt_balance_value' },
        @{ Label = 'Parley GUI value after markup'; File = $rowRel; Text = $row + "`ntext_single = { raw_text = `"#low [GuiScope.ScriptValue('tnt_balance_value')]#!`" }`n"; Error = 'Standalone value: unresolved tnt_balance_value' },
        @{ Label = 'Parley GUI action'; File = $rowRel; Text = $row + "`nbutton = { onclick = `"[GetScriptedGui('tnt_pick_marriage_open').Execute( GuiScope.End )]`" }`n"; Error = 'Standalone scripted GUI: unresolved tnt_pick_marriage_open' },
        @{ Label = 'Parley GUI localization'; File = $rowRel; Text = $row.Replace('text = tnt_ma_grade_title', 'text = tnt_window_title'); Error = 'Standalone localization: unresolved tnt_window_title' },
        @{ Label = 'Parley localization substitution'; File = $locRel; Text = $sources[$locRel].Replace('Candidate gameplay potential', 'Candidate gameplay potential $tnt_window_title$'); Error = 'Standalone localization: unresolved tnt_window_title' },
        @{ Label = 'computed localization alternatives'; File = $rowRel; Text = $row + "`ntext_single = { text = `"[SelectLocalization( True, 'external_parley_label', Select_CString( True, 'tnt_ma_grade_title', 'another_external_label' ) )]`" }`n"; Error = 'Standalone localization: unresolved external_parley_label' },
        @{ Label = 'Parley session variable'; File = $rowRel; Text = $row + "`nwidget = { visible = `"[GetPlayer.MakeScope.HasVariable('tnt_open')]`" }`n"; Error = 'Standalone custom symbol: unresolved tnt_open' },
        @{ Label = 'widget name masking Parley session variable'; File = $rowRel; Text = $row + "`nwidget = { name = `"tnt_open`" visible = `"[GetPlayer.MakeScope.HasVariable('tnt_open')]`" }`n"; Error = 'Standalone custom symbol: unresolved tnt_open' },
        @{ Label = 'unguarded adapter description'; File = $gradeRel; Text = $grade.Replace('tnt_ma_adapter_p_c1_value != 0', 'tnt_ma_adapter_p_c1_value >= 0'); Error = 'Standalone adapter: unguarded description tnt_ma_adapter_p_c1' },
        @{ Label = 'active standalone adapter'; File = 'common/script_values/tnt_ma_00_adapter_defaults.txt'; Text = $defaults.Replace('tnt_ma_adapter_p_c1_value = { value = 0 }', 'tnt_ma_adapter_p_c1_value = { value = 1 }'); Error = 'Standalone adapter: tnt_ma_adapter_p_c1_value must default to formula zero' }
    )
    foreach ($case in $negativeCases) {
        Assert-True ($case.Text -cne $sources[$case.File]) "Standalone negative fixture did not mutate: $($case.Label)"
        $mutated = $sources.Clone()
        $mutated[$case.File] = $case.Text
        $failure = ''
        try { Assert-McaStandalone $mutated $allValueNames $sgNames $allLocKeys $nativeLocKeys }
        catch { $failure = $_.Exception.Message }
        Assert-True ($failure.StartsWith($case.Error, [System.StringComparison]::Ordinal)) "Standalone negative '$($case.Label)' expected '$($case.Error)', got '$failure'"
    }
    $commentOnly = $sources.Clone()
    $commentOnly[$rowRel] += "`n# tnt_balance_value tnt_pick_marriage_open tnt_window_title TntMacro() dependencies = {}`n"
    Assert-McaStandalone $commentOnly $allValueNames $sgNames $allLocKeys $nativeLocKeys
    Pass "standalone negative fixtures: $($negativeCases.Count) foreign/dependency/adapter mutations rejected; comment-only control passes"
    Write-Output "MCA source checks: $script:CheckCount/10 PASS. Static checks only; CK3 parser/UI validation remains separate."
    exit 0
}
catch {
    [Console]::Error.WriteLine("MCA source checks FAILED: $($_.Exception.Message)")
    exit 1
}
