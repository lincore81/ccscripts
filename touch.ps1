# sets the last write time to now
# usage: ls -Recursion | .\touch

$now = Get-Date

foreach ($i in $input) {
    $i.LastWriteTime = $now
    echo $i.Name
}