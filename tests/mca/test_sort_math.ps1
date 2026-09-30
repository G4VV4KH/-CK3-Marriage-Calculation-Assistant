# Standalone, read-only property tests for MCA snapshot-sort arithmetic.
# This models exact Int64/Decimal arithmetic, NOT CK3 CFixedPoint precision,
# GUI lifecycle, script parser behavior, or persistence/multiplayer semantics.
# Run: pwsh -NoProfile -File tests/mca/test_sort_math.ps1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sortMathTimer = [Diagnostics.Stopwatch]::StartNew()
$script:SortMathAssertions = [long]0

function Assert-SortMath {
    param([bool]$Condition, [string]$Message)
    $script:SortMathAssertions++
    if (-not $Condition) { throw "MCA sort math assertion failed: $Message" }
}

function Test-SortPermutation {
    param([long[]]$Indices, [int]$Expected)
    if ($Expected -lt 1 -or $Expected -gt 9999 -or $Indices.Count -ne $Expected) {
        return $false
    }
    $sortMathOrdered = @($Indices | Sort-Object -Descending)
    for ($sortMathPosition = 0; $sortMathPosition -lt $Expected; $sortMathPosition++) {
        if ($sortMathOrdered[$sortMathPosition] -ne ($Expected - 1 - $sortMathPosition)) {
            return $false
        }
    }
    return $true
}

# Exhaust every allowed count, both index boundaries, and score boundaries /
# sign changes. The modulo computation is exact integer arithmetic; division
# uses Decimal + Floor to avoid PowerShell's rounded integer-cast semantics.
$sortMathScoreCases = @([long]-10000, -9999, -1, 0, 1, 9999, 10000)
$sortMathScoreRecords = [long]0
for ($sortMathCount = 1; $sortMathCount -le 9999; $sortMathCount++) {
    foreach ($sortMathIndex in @([long]0, [long]($sortMathCount - 1))) {
        foreach ($sortMathScore in $sortMathScoreCases) {
            $sortMathKey = [long](($sortMathScore + 10000L) * 10000L + 9999L - $sortMathIndex)
            $sortMathDecodedIndex = 9999L - ($sortMathKey % 10000L)
            $sortMathDecodedScore = [long]([Math]::Floor([decimal]$sortMathKey / 10000D)) - 10000L
            $sortMathDecodedScoreExactMultiple = [long](([decimal]($sortMathKey - ($sortMathKey % 10000L))) / 10000D) - 10000L
            Assert-SortMath ($sortMathKey -ge 1 -and $sortMathKey -le 200009999L) 'score-key bounds'
            Assert-SortMath ($sortMathDecodedIndex -eq $sortMathIndex) 'score-key index round trip'
            Assert-SortMath ($sortMathDecodedScore -eq $sortMathScore) 'score-key score round trip'
            Assert-SortMath ($sortMathDecodedScoreExactMultiple -eq $sortMathScore) 'score-key remainder-first score round trip'
            $sortMathScoreRecords++
        }
    }
}

# Compare packed-key ordering against its semantic definition, including
# negative scores, frequent ties, sentinel unscored rows, and the maximum N.
$sortMathOrderRecords = [long]0
foreach ($sortMathCount in @(1, 2, 3, 17, 256, 9999)) {
    $sortMathRows = @(
        for ($sortMathIndex = 0; $sortMathIndex -lt $sortMathCount; $sortMathIndex++) {
            $sortMathScore = [long](($sortMathIndex * 37) % 199 - 99)
            if (($sortMathIndex % 23) -eq 0) { $sortMathScore = -10000L }
            if (($sortMathIndex % 47) -eq 0) { $sortMathScore = 10000L }
            [pscustomobject]@{
                Index = [long]$sortMathIndex
                Score = $sortMathScore
                Key = [long](($sortMathScore + 10000L) * 10000L + 9999L - $sortMathIndex)
            }
        }
    )
    $sortMathPackedOrder = @($sortMathRows | Sort-Object -Property Key -Descending)
    $sortMathSemanticOrder = @($sortMathRows | Sort-Object -Property @(
        @{ Expression = 'Score'; Descending = $true },
        @{ Expression = 'Index'; Descending = $false }
    ))
    for ($sortMathPosition = 0; $sortMathPosition -lt $sortMathCount; $sortMathPosition++) {
        Assert-SortMath ($sortMathPackedOrder[$sortMathPosition].Index -eq $sortMathSemanticOrder[$sortMathPosition].Index) 'score-descending, native-index-ascending order'
        $sortMathOrderRecords++
    }
    Assert-SortMath (Test-SortPermutation -Indices @($sortMathPackedOrder.Index) -Expected $sortMathCount) 'sorted output is a complete native-index permutation'
}

# Explicit adversarial inputs: matching cardinality alone is insufficient.
$sortMathPermutationCases = @(
    @{ Name = 'singleton'; Indices = @(0L); Expected = 1; Valid = $true },
    @{ Name = 'unordered complete'; Indices = @(2L, 0L, 1L); Expected = 3; Valid = $true },
    @{ Name = 'duplicate, same count'; Indices = @(0L, 0L, 2L); Expected = 3; Valid = $false },
    @{ Name = 'missing'; Indices = @(0L, 2L); Expected = 3; Valid = $false },
    @{ Name = 'negative'; Indices = @(-1L, 0L, 1L); Expected = 3; Valid = $false },
    @{ Name = 'out of range'; Indices = @(0L, 1L, 3L); Expected = 3; Valid = $false },
    @{ Name = 'extra'; Indices = @(0L, 1L, 2L, 3L); Expected = 3; Valid = $false },
    @{ Name = 'empty'; Indices = @(); Expected = 1; Valid = $false },
    @{ Name = 'zero count'; Indices = @(); Expected = 0; Valid = $false },
    @{ Name = 'oversize count'; Indices = @(); Expected = 10000; Valid = $false }
)
foreach ($sortMathCase in $sortMathPermutationCases) {
    $sortMathActual = Test-SortPermutation -Indices $sortMathCase.Indices -Expected $sortMathCase.Expected
    Assert-SortMath ($sortMathActual -eq $sortMathCase.Valid) "permutation rejection: $($sortMathCase.Name)"
}

# Current identity design stores character references, not numeric IDs. The
# collector accepts one complete monotone traversal, in either direction.
# These plain objects stand for stable character references; ReferenceEquals
# deliberately does not treat equal names/values as the same character.
function New-SortReferenceSnapshot {
    param([int]$Expected)
    [pscustomobject]@{
        State = $(if ($Expected -ge 1 -and $Expected -le 9999) { 1 } else { 3 })
        Expected = $Expected
        Received = 0
        Direction = 0
        References = [Collections.Generic.List[object]]::new()
        Keys = [Collections.Generic.List[long]]::new()
    }
}

function Invoke-SortReferenceCapture {
    param($Snapshot, [long]$Index, $CandidateReference, [long]$Score = 0)
    if ($Snapshot.State -ne 1 -or $Snapshot.Received -ge $Snapshot.Expected) {
        return 'noop'
    }
    if ($Index -lt 0 -or $Index -ge $Snapshot.Expected -or
        $null -eq $CandidateReference -or $Score -lt -10000 -or $Score -gt 10000) {
        $Snapshot.State = 3
        return 'failed'
    }
    if ($Snapshot.Received -eq 0) {
        if ($Index -eq 0) { $Snapshot.Direction = 1 }
        elseif ($Index -eq ($Snapshot.Expected - 1)) { $Snapshot.Direction = -1 }
        else {
            $Snapshot.State = 3
            return 'failed'
        }
    }
    $sortReferenceRequired = if ($Snapshot.Direction -eq 1) {
        $Snapshot.Received
    } else {
        $Snapshot.Expected - 1 - $Snapshot.Received
    }
    if ($Index -ne $sortReferenceRequired) {
        $Snapshot.State = 3
        return 'failed'
    }
    $Snapshot.References.Add($CandidateReference)
    $Snapshot.Keys.Add([long](($Score + 10000L) * 10000L + 9999L - $Index))
    $Snapshot.Received++
    return 'captured'
}

function Complete-SortReferenceSnapshot {
    param($Snapshot)
    if ($Snapshot.State -ne 1) { return 'noop' }
    if ($Snapshot.Received -ne $Snapshot.Expected -or
        $Snapshot.References.Count -ne $Snapshot.Expected -or
        $Snapshot.Keys.Count -ne $Snapshot.Expected -or
        $Snapshot.Direction -notin @(-1, 1)) {
        $Snapshot.State = 3
        return 'failed'
    }
    $Snapshot.State = 2
    return 'ready'
}

function Get-SortReferenceSlot {
    param([int]$NativeIndex, [int]$Expected, [int]$Direction)
    if ($Expected -lt 1 -or $Expected -gt 9999 -or
        $NativeIndex -lt 0 -or $NativeIndex -ge $Expected -or
        $Direction -notin @(-1, 1)) { throw 'Invalid reference slot arguments' }
    if ($Direction -eq 1) { return $NativeIndex }
    return $Expected - 1 - $NativeIndex
}

$sortMathReferenceRecords = 0L
$sortMathTraversalCases = 0
foreach ($sortMathCount in @(1, 2, 3, 17, 256, 9999)) {
    $sortMathNativeReferences = @(
        for ($sortMathIndex = 0; $sortMathIndex -lt $sortMathCount; $sortMathIndex++) {
            [pscustomobject]@{ Name = 'same visible name'; NativeIndex = $sortMathIndex }
        }
    )
    foreach ($sortMathDirection in @(1, -1)) {
        $sortMathSnapshot = New-SortReferenceSnapshot -Expected $sortMathCount
        for ($sortMathPosition = 0; $sortMathPosition -lt $sortMathCount; $sortMathPosition++) {
            $sortMathIndex = if ($sortMathDirection -eq 1) { $sortMathPosition } else { $sortMathCount - 1 - $sortMathPosition }
            $sortMathScore = [long](($sortMathIndex * 37) % 199 - 99)
            $sortMathResult = Invoke-SortReferenceCapture $sortMathSnapshot $sortMathIndex $sortMathNativeReferences[$sortMathIndex] $sortMathScore
            Assert-SortMath ($sortMathResult -eq 'captured') 'strict traversal accepts next ordinal'
        }
        $sortMathEffectiveDirection = if ($sortMathCount -eq 1) { 1 } else { $sortMathDirection }
        Assert-SortMath ($sortMathSnapshot.Direction -eq $sortMathEffectiveDirection) 'direction inferred from first endpoint; singleton chooses +1'
        Assert-SortMath ($sortMathSnapshot.Received -eq $sortMathCount) 'complete reference capture count'

        # Complete capture is still state 1 until finalization. Duplicates and
        # malformed late callbacks cannot poison it or append extra records.
        foreach ($sortMathLateIndex in @(0L, [long]($sortMathCount - 1), -1L, [long]$sortMathCount)) {
            $sortMathResult = Invoke-SortReferenceCapture $sortMathSnapshot $sortMathLateIndex $null 10001
            Assert-SortMath ($sortMathResult -eq 'noop' -and $sortMathSnapshot.State -eq 1) 'late complete-capture callback is no-op before finalize'
            Assert-SortMath ($sortMathSnapshot.Received -eq $sortMathCount -and $sortMathSnapshot.References.Count -eq $sortMathCount -and $sortMathSnapshot.Keys.Count -eq $sortMathCount) 'late callback preserves all complete capture records'
        }
        Assert-SortMath ((Complete-SortReferenceSnapshot $sortMathSnapshot) -eq 'ready') 'complete traversal finalizes'
        Assert-SortMath ((Complete-SortReferenceSnapshot $sortMathSnapshot) -eq 'noop') 'duplicate finalize is no-op'
        Assert-SortMath ((Invoke-SortReferenceCapture $sortMathSnapshot 0 $sortMathNativeReferences[0]) -eq 'noop') 'late ready callback is no-op'
        Assert-SortMath ($sortMathSnapshot.State -eq 2 -and $sortMathSnapshot.Received -eq $sortMathCount) 'ready snapshot remains ready'

        # Decode the sorted native ordinal, then translate to capture-order
        # slot. Identity must be the same object, not merely an equal label.
        $sortMathSortedKeys = @($sortMathSnapshot.Keys | Sort-Object -Descending)
        for ($sortMathPosition = 0; $sortMathPosition -lt $sortMathCount; $sortMathPosition++) {
            $sortMathIndex = [int](9999L - ($sortMathSortedKeys[$sortMathPosition] % 10000L))
            $sortMathSlot = Get-SortReferenceSlot $sortMathIndex $sortMathCount $sortMathSnapshot.Direction
            Assert-SortMath ([object]::ReferenceEquals($sortMathSnapshot.References[$sortMathSlot], $sortMathNativeReferences[$sortMathIndex])) 'sorted native ordinal retrieves exact captured character reference'
            $sortMathImpostor = [pscustomobject]@{ Name = 'same visible name'; NativeIndex = $sortMathIndex }
            Assert-SortMath (-not [object]::ReferenceEquals($sortMathSnapshot.References[$sortMathSlot], $sortMathImpostor)) 'same-count same-name replacement fails identity guard'
            if ($sortMathCount -gt 1) {
                $sortMathOtherIndex = ($sortMathIndex + 1) % $sortMathCount
                Assert-SortMath (-not [object]::ReferenceEquals($sortMathSnapshot.References[$sortMathSlot], $sortMathNativeReferences[$sortMathOtherIndex])) 'same-count reorder fails identity guard'
            }
            $sortMathReferenceRecords++
        }
        $sortMathTraversalCases++
    }
}

# Slot transformation is an involution. Exhaust all N, probing both endpoints
# and a middle index without quadratic traversal of every possible count.
$sortMathSlotCases = 0L
for ($sortMathCount = 1; $sortMathCount -le 9999; $sortMathCount++) {
    foreach ($sortMathIndex in @(0, ($sortMathCount - 1), [int][Math]::Floor($sortMathCount / 2))) {
        foreach ($sortMathDirection in @(1, -1)) {
            $sortMathSlot = Get-SortReferenceSlot $sortMathIndex $sortMathCount $sortMathDirection
            Assert-SortMath ($sortMathSlot -ge 0 -and $sortMathSlot -lt $sortMathCount) 'reference slot stays in bounds'
            Assert-SortMath ((Get-SortReferenceSlot $sortMathSlot $sortMathCount $sortMathDirection) -eq $sortMathIndex) 'capture/native slot transform is its own inverse'
            $sortMathSlotCases++
        }
    }
}

$sortMathRejectedTraversals = @(
    @{ Name = 'first callback in middle'; N = 3; Indices = @(1) },
    @{ Name = 'ascending early duplicate'; N = 3; Indices = @(0, 0) },
    @{ Name = 'descending early duplicate'; N = 3; Indices = @(2, 2) },
    @{ Name = 'ascending skipped index'; N = 4; Indices = @(0, 2) },
    @{ Name = 'descending skipped index'; N = 4; Indices = @(3, 1) },
    @{ Name = 'ascending reversal'; N = 4; Indices = @(0, 1, 0) },
    @{ Name = 'descending reversal'; N = 4; Indices = @(3, 2, 3) },
    @{ Name = 'nonmonotone complete permutation'; N = 4; Indices = @(0, 2, 1, 3) },
    @{ Name = 'negative ordinal'; N = 3; Indices = @(-1) },
    @{ Name = 'ordinal equals count'; N = 3; Indices = @(3) },
    @{ Name = 'singleton rejects nonzero'; N = 1; Indices = @(1) }
)
foreach ($sortMathCase in $sortMathRejectedTraversals) {
    $sortMathSnapshot = New-SortReferenceSnapshot -Expected $sortMathCase.N
    foreach ($sortMathIndex in $sortMathCase.Indices) {
        $sortMathCandidate = [pscustomobject]@{ NativeIndex = $sortMathIndex }
        $null = Invoke-SortReferenceCapture $sortMathSnapshot $sortMathIndex $sortMathCandidate
    }
    Assert-SortMath ($sortMathSnapshot.State -eq 3) "fail closed: $($sortMathCase.Name)"
    $sortMathFailedCount = $sortMathSnapshot.Received
    $sortMathFailedKeys = $sortMathSnapshot.Keys.Count
    Assert-SortMath ((Invoke-SortReferenceCapture $sortMathSnapshot 0 ([pscustomobject]@{})) -eq 'noop') 'failed traversal ignores later callbacks'
    Assert-SortMath ((Complete-SortReferenceSnapshot $sortMathSnapshot) -eq 'noop') 'failed traversal cannot finalize'
    Assert-SortMath ($sortMathSnapshot.State -eq 3 -and $sortMathSnapshot.Received -eq $sortMathFailedCount -and $sortMathSnapshot.Keys.Count -eq $sortMathFailedKeys) 'failed snapshot remains unchanged'
}

foreach ($sortMathCount in @(0, 10000)) {
    $sortMathSnapshot = New-SortReferenceSnapshot -Expected $sortMathCount
    Assert-SortMath ($sortMathSnapshot.State -eq 3) 'invalid count begins failed'
    Assert-SortMath ((Invoke-SortReferenceCapture $sortMathSnapshot 0 ([pscustomobject]@{})) -eq 'noop') 'invalid count never captures'
}
$sortMathSnapshot = New-SortReferenceSnapshot -Expected 3
$null = Invoke-SortReferenceCapture $sortMathSnapshot 0 ([pscustomobject]@{})
Assert-SortMath ((Complete-SortReferenceSnapshot $sortMathSnapshot) -eq 'failed') 'incomplete traversal cannot become ready'
$sortMathSnapshot = New-SortReferenceSnapshot -Expected 1
$sortMathSnapshot.State = 0
Assert-SortMath ((Invoke-SortReferenceCapture $sortMathSnapshot 0 ([pscustomobject]@{})) -eq 'noop') 'callback after clear is no-op'
Assert-SortMath ($sortMathSnapshot.Received -eq 0 -and $sortMathSnapshot.References.Count -eq 0) 'callback after clear preserves empty snapshot'

$sortMathTimer.Stop()
[pscustomobject]@{
    Result = 'PASS'
    Model = 'Exact Int64/Decimal only; CK3 engine precision and GUI behavior NOT proved'
    Assertions = $script:SortMathAssertions
    ScoreBoundaryRecords = $sortMathScoreRecords
    SortedRecords = $sortMathOrderRecords
    PermutationCases = $sortMathPermutationCases.Count
    ReferenceTraversalCases = $sortMathTraversalCases
    ReferenceIdentityRecords = $sortMathReferenceRecords
    ReferenceSlotCases = $sortMathSlotCases
    RejectedTraversalCases = $sortMathRejectedTraversals.Count
    ElapsedSeconds = [Math]::Round($sortMathTimer.Elapsed.TotalSeconds, 3)
}
