$TESTS_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location "$TESTS_DIR"
$results = Invoke-Pester -PassThru
$FailedTestTally = $results.FailedCount
if ($results.FailedCount -eq 0) {
    write-output "All tests passed successfully"
    exit 0
}
else {
    write-output "Some tests failed. Number of failed tests is: $results.FailedCount"
    exit 1
}
