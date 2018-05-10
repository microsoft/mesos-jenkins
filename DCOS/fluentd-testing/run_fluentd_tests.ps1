
$results = Invoke-Pester -PassThru
$FailedTestTally = $results.FailedCount
if ($FailedTestTally -eq 0) {
	write-output "All tests passed successfully"
	exit 0
}
else {
	write-output "Some tests failed. Number of failed tests is: $FailedTestTally"
	exit 1
}
