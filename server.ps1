if(!(Get-Module -Name Pode -ListAvailable -ErrorAction SilentlyContinue))
{
	throw "You must install the Pode module."
}

$VerbosePreference = "Continue"

########################################################################################
# Import Pode config file manually so we can use some details before starting the server:
$PodeConfigManualImport = Import-PowerShellDataFile -Path ".\server.psd1"

########################################################################################
# Dot source a file with some functions in (ordinarily these would be in a module), and
# get an access token for the bot to send messages to chats.
Write-Verbose -Message "Importing client credentials and getting an access token"
try
{
	. ./functions.ps1
	$ClientConfig = Get-Content -Path "secrets/clientdetails.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
	$BotAccessToken = Get-MicrosoftBotAccessToken -clientid $ClientConfig.clientid -clientsecret $ClientConfig.clientsecret -ErrorAction Stop
	Write-Verbose -Message "Token expires in: $((New-TimeSpan -Seconds $BotAccessToken.expires_in).TotalHours) hours"
}
catch
{
	throw $_
}

########################################################################################
# Start Ngrok. Ideally we'd also update the bot api endpoint but there doesn't appear
# to be a way to do this unless it's the full on 'bot service' service from Azure.
# Whilst developing this, let's assume that if ngrok is already running we don't need to
# start it:
if($Null -eq (Get-Process -Name ngrok -ErrorAction SilentlyContinue))
{
	Write-Verbose -Message "Starting Ngrok and updating manifest file"
	try
	{
		$Ngrok = Start-NGrok -Port $PodeConfigManualImport.Port -ErrorAction Stop
		$Manifest = (Get-Content "bot\manifest.json" | ConvertFrom-Json)
		$Manifest.validDomains = ($Ngrok.http -split 'http://')[1]
		$Manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath "bot\manifest.json" -Force
	}
	catch
	{
		Get-Process -Name ngrok -ErrorAction SilentlyContinue | Stop-Process
		throw $_
	}
}

########################################################################################
Write-Verbose "Calling 'Start-PodeServer'"
Start-PodeServer {

	Write-PodeHost "Calling New-PodeLoggingMethod"
	New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging -Level Error, Debug, Verbose

	########################################################################################
	#Region Server Level Thread Safe 'state' objects
	Lock-PodeObject -ScriptBlock {
		Set-PodeState -Name 'BotAccessToken' -Value @{ 'TokenObject' = $BotAccessToken } | Out-Null
		Set-PodeState -Name 'ApplicationRoot' -Value @{ 'ApplicationRoot' = $PSScriptRoot } | Out-Null
	}
	#EndRegion Server Level Thread Safe Objects

	########################################################################################
	#Region Middleware
	Write-PodeHost "Calling Add-PodeMiddleware"
	Add-PodeMiddleware -Name 'ImportFunctions' -Route '/api/messages' -ScriptBlock {
		# As we're using an old school functions file to make this PoC a bit more portable,
		# we need to make sure that file is imported for each runspace/thread so do that with
		# middleware. We also need to make the functions global (see functions.ps1).
		# Normally our functions would be in a module in a system wide module path.
		$ApplicationRoot = (Get-PodeState -Name ApplicationRoot).ApplicationRoot
		. "$ApplicationRoot\functions.ps1"
	}
	#EndRegion

	########################################################################################
	#Region Scheduled Tasks
	Write-PodeHost "Calling Add-PodeSchedule"
	Add-PodeSchedule -Name 'RefreshMicrosoftBotToken' -Cron '@hourly' -ScriptBlock {
		Write-PodeHost "Scheduled Task: Refreshing Bot Access Token"
		$BotAccessToken = Get-MicrosoftBotAccessToken -clientid $ClientConfig.clientid -clientsecret $ClientConfig.clientsecret -ErrorAction Stop
		Set-PodeState -Name 'BotAccessToken' -Value @{ 'TokenObject' = $BotAccessToken } | Out-Null
	}
	#EndRegion

	########################################################################################
	#Region Routes
	Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
		Write-PodeTextResponse -Value ':)'
	}
	Write-PodeHost "Importing Routes"
	Use-PodeRoutes -Path "routes"
	#EndRegion

	########################################################################################
	#Region Listeners
	Write-PodeHost "Calling Add-PodeEndpoint"
	Add-PodeEndpoint -Address (Get-PodeConfig).Url -Port $(Get-PodeConfig).Port -Protocol Http
	#EndRegion

} -Threads 2