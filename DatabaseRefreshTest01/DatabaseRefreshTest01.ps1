# Configurations
$TargetSqlServerInstance = "TEST\TEST"                             # Target SQL Server instance
$TargetDb = "AdventureWorks2016"                                   # Target database name
$BackupDir = "\\DC\Fsw\"                                            # Directory where backups are stored
$SourceLogicalDataFileName = "AdventureWorks2016_Data"              # Logical data file name of source database
$SourceLogicalLogFileName = "AdventureWorks2016_log"               # Logical log file name of source database
$TargetLogicalDataFileName = "AdventureWorks2016_Data_New"         # Logical data file name for target database (updated to avoid conflict)
$TargetLogicalLogFileName = "AdventureWorks2016_log_New"           # Logical log file name for target database (updated to avoid conflict)
$TargetPhysicalDataFileName = "M:\Data\AdventureWorks2016_Data.mdf" # Physical path for the data file
$TargetPhysicalLogFileName = "L:\Log\AdventureWorks2016_log.ldf"   # Physical path for the log file
$CompatLevel = 140                                                 # Compatibility level (2017 = 140, 2019 = 150)

# Define the connection string
$ConnectionString = "Server=$TargetSqlServerInstance;Database=AdventureWorks2016;Integrated Security=True;TrustServerCertificate=True;"

# Import SQL Server Module
Import-Module sqlserver

# Create the SMO Server Object
$SqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server($TargetSqlServerInstance)

# Find the latest backup file in the specified directory
$LatestFullBackupFile = Get-ChildItem -Path $BackupDir -Filter *.bak | Sort-Object LastAccessTime -Descending | Select-Object -First 1
$FileToRestore = Join-Path $BackupDir $LatestFullBackupFile.Name

# Terminate active connections to the target database
$KillConnectionsSql = @"
USE master;
ALTER DATABASE [$TargetDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [$TargetDb] SET MULTI_USER;
"@
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $KillConnectionsSql

# Create Restore object and add device (backup file)
$Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
$Restore.Database = $TargetDb
$Restore.Devices.AddDevice($FileToRestore, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)

# Relocate files (adjust paths for the restore)
$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($SourceLogicalDataFileName, $TargetPhysicalDataFileName)
$RelocateLog  = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($SourceLogicalLogFileName, $TargetPhysicalLogFileName)

# Add the relocation options to the restore object
$Restore.RelocateFiles.Add($RelocateData)
$Restore.RelocateFiles.Add($RelocateLog)

# Replace the database if it already exists
$Restore.ReplaceDatabase = $true

# Perform the restore
$Restore.SqlRestore($SqlServer)

# Post-Restore Configuration
# Set database owner to 'sa'
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query "EXEC sp_changedbowner 'sa'"

# Set database compatibility level
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query "ALTER DATABASE [$TargetDb] SET COMPATIBILITY_LEVEL = $CompatLevel"

# Change database recovery model to SIMPLE
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query "ALTER DATABASE [$TargetDb] SET RECOVERY SIMPLE WITH NO_WAIT"

# Rename logical file names to avoid conflicts
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query @"
ALTER DATABASE [$TargetDb] MODIFY FILE (NAME = '$SourceLogicalDataFileName', NEWNAME = '$TargetLogicalDataFileName');
ALTER DATABASE [$TargetDb] MODIFY FILE (NAME = '$SourceLogicalLogFileName', NEWNAME = '$TargetLogicalLogFileName');
"@

# Perform integrity check on the database
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query "DBCC CHECKDB([$TargetDb])"

# Display database metadata
Invoke-Sqlcmd -ConnectionString $ConnectionString -Query "EXEC sp_helpdb [$TargetDb]"

Write-Host "Database [$TargetDb] has been successfully restored and configured."

