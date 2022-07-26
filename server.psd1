@{
	Port   = 8099
	Url    = 'localhost'
	Server = @{
		FileMonitor = @{
			Enable  = $true
			Include = @("*.ps1")
			Exclude = @("functions.ps1")
		}
	}
}