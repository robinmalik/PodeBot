#############################################################################################################
function Start-NGrok
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $False)]
		[String]$Path,
		[Parameter(Mandatory)]
		[Int]$Port
	)

	try
	{
		if(!$Path) { $Path = 'ngrok' }
		if($PSEdition -eq 'Desktop' -or ($PSEdition -eq 'Core' -and $PSVersionTable.OS -match "Windows"))
		{
			Start-Process $Path -ArgumentList "http http://localhost:$Port" -WindowStyle Minimized -ErrorAction Stop
		}
		else
		{
			Start-Process $Path -ArgumentList "http http://localhost:$Port" -ErrorAction Stop
		}
	}
	catch
	{
		throw $_
	}

	Start-Sleep -Seconds 2

	# Query the local process to get the listener urls:
	$Data = Invoke-WebRequest -Uri "http://localhost:4040/grpc/agent.Web/Preloaded" `
		-Method "POST" `
		-Headers @{
		"Pragma"          = "no-cache"
		"Cache-Control"   = "no-cache"
		"x-grpc-web"      = "1"
		"DNT"             = "1"
		"User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.89 Safari/537.36"
		"Accept"          = "*/*"
		"Origin"          = "http://localhost:4040"
		"Sec-Fetch-Site"  = "same-origin"
		"Sec-Fetch-Mode"  = "cors"
		"Sec-Fetch-Dest"  = "empty"
		"Referer"         = "http://localhost:4040/inspect/http"
		"Accept-Encoding" = "gzip, deflate, br"
		"Accept-Language" = "en-GB,en-US;q=0.9,en;q=0.8"
	} `
		-ContentType "application/grpc-web+proto" `
		-Body ([System.Text.Encoding]::UTF8.GetBytes("$([char]0)$([char]0)$([char]0)$([char]0)$([char]0)"))

	$ArrayOfLines = $Data.RawContent -split "`n"
	$NGrokLines = $ArrayOfLines | Where-Object { $_ -match 'ngrok.io' }
	if($NGrokLines)
	{
		$NGrokURLs = $NGrokLines | ForEach-Object { (($_ -split '\.\.')[0]).SubString(1) }
		[PSCustomObject]@{
			"https" = $($NGrokURLs | Where-Object { $_ -match "https:" })
			"http"  = $($NGrokURLs | Where-Object { $_ -match "http:" })
			"port"  = $Port
		}
	}
	else
	{
		Write-Warning "Could not obtain NGrok URLs"
	}
}


#############################################################################################################
function Get-MicrosoftBotAccessToken
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[String]$ClientId,
		[Parameter(Mandatory = $true)]
		[String]$ClientSecret
	)

	$url = "https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token"


	Add-Type -AssemblyName System.Web
	$clientsecretencoded = [System.Web.HttpUtility]::UrlEncode($clientsecret)
	$scopeencoded = [System.Web.HttpUtility]::UrlEncode('https://api.botframework.com/.default')
	$body = "client_id=$clientId&client_secret=$clientsecretencoded&grant_type=client_credentials&scope=$scopeencoded"

	$Access = Invoke-RestMethod $url -Method Post -ContentType "application/x-www-form-urlencoded" -Body $body -ErrorAction Stop

	<#
		This returns a token like so:
        token_type     : Bearer
        expires_in     : 86399
        access_token   : eyJ0eXAiOiJKV1Qi...
    #>
	return $Access
}


#############################################################################################################
function global:New-TeamsAdaptiveCardMessageJSON
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[String]
		$TitleText,

		[Parameter(Mandatory = $true)]
		[ValidateSet('Success', 'Warning', 'Failure')]
		[String]
		$Level,

		[Parameter(Mandatory = $false, ParameterSetName = "Object")]
		[PSCustomObject]
		$FactSetObject,

		[Parameter(Mandatory = $false, ParameterSetName = "Dictionary")]
		[System.Collections.Specialized.OrderedDictionary]
		$DictionaryFactSet,

		[Parameter(Mandatory = $false)]
		[Array]$Actions,

		[Parameter(Mandatory = $false)]
		[PSCustomObject]
		$AtMentionObject
	)

	########################################################################################
	# 'Background' image (that really just creates a highlight bar at the top of the card)
	$BackgroundImageBase64String = switch($Level)
	{
		"Failure" { "iVBORw0KGgoAAAANSUhEUgAABSgAAAAFCAYAAABGmwLHAAAARklEQVR4nO3YMQEAIBDEsANPSMC/AbzwMm5JJHTseuf+AAAAAAAUbNEBAAAAgBaDEgAAAACoMSgBAAAAgBqDEgAAAADoSDL8RAJfcbcsoQAAAABJRU5ErkJggg==" }
		"Warning" { "iVBORw0KGgoAAAANSUhEUgAABSgAAAAFCAYAAABGmwLHAAAARUlEQVR4nO3YMQEAMAzDsGxP+UMasg5GHgmCT599swEAAAAAKLiiAwAAAAAtBiUAAAAAUGNQAgAAAAA1BiUAAAAA0JHkA4XKAtCn5l4wAAAAAElFTkSuQmCC" }
		"Success" { "iVBORw0KGgoAAAANSUhEUgAABSgAAAAFCAYAAABGmwLHAAAARUlEQVR4nO3YMQEAIBDEsAM1GEErMnkZtyQSOnadd38AAAAAAAq26AAAAABAi0EJAAAAANQYlAAAAABAjUEJAAAAAHQkGWMEAh35OF6mAAAAAElFTkSuQmCC" }
		default { "iVBORw0KGgoAAAANSUhEUgAABSgAAAAFCAYAAABGmwLHAAAARklEQVR4nO3YMQEAIBDEsAP/VhgZ0cbLuCWR0LHr3PcDAAAAAFCwRQcAAAAAWgxKAAAAAKDGoAQAAAAAagxKAAAAAKAjyQD61wMo/NtPywAAAABJRU5ErkJggg==" }
	}

	########################################################################################
	# Generate the JSON
	$Body = [ordered]@{
		"type"        = "message"
		"summary"     = $TitleText
		"attachments" = @(
			[ordered]@{
				"contentType" = "application/vnd.microsoft.card.adaptive"
				"content"     =
				[ordered]@{
					"type"            = "AdaptiveCard"
					"body"            = @(
						[ordered]@{
							"type"   = "TextBlock"
							"size"   = "Large"
							"weight" = "Bolder"
							"text"   = $TitleText
							"color"  = "Default"
						}
						[ordered]@{
							"type"    = "ColumnSet"
							"columns" = @(
								[ordered]@{
									"type"  = "Column"
									"items" = @(
										if($AtMentionObject)
										{
											$Text = "**Attention:** <at>$($AtMentionObject.name)</at> | **Data accurate at:** $($(Get-Date -Format s).ToString() -replace 'T',' ')"
										}
										else
										{
											$Text = "**Data accurate at:** $($(Get-Date -Format s).ToString() -replace 'T',' ')"
										}
										[ordered]@{
											"type"   = "TextBlock"
											"weight" = "Default"
											"text"   = $Text
											"wrap"   = $true
											"size"   = "Small"
										}
									)
									"width" = "stretch"
								}
							)
						}
						if($FactSetObject -or $DictionaryFactSet)
						{
							[ordered]@{
								"type"      = "FactSet"
								"facts"     = @(
									if($FactSetObject)
									{
										foreach($Property in $($FactSetObject | Get-Member -MemberType NoteProperty | Select-Object -Expand Name))
										{
											@{
												"title" = "$($Property):"
												"value" = $FactSetObject.$Property
											}
										}
									}
									elseif($DictionaryFactSet)
									{
										foreach($Property in $DictionaryFactSet.GetEnumerator())
										{
											# Don't order this as we often create the dict in a specific order:
											@{
												"title" = "$($Property.Name):"
												"value" = $Property.value
											}
										}
									}
								)
								"separator" = $true
							}
						}

					)
					"separator"       = $true
					"actions"         = @(
						if($Actions)
						{
							foreach($Item in $Actions)
							{
								# As actions can be quite broad it's hard to generalise this so we'll rely on the user submitting well formed objects
								# in accordance with: https://docs.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/cards-actions?tabs=json#adaptive-cards-actions
								$Item
							}
						}
					)
					"msteams"         = [ordered]@{
						"width"    = "Full"
						"entities" = @(
							if($AtMentionObject)
							{
								[ordered]@{
									"type"      = "mention"
									"text"      = "<at>$($AtMentionObject.name)</at>"
									"mentioned" = [ordered]@{
										# @mentions support either the Teams user ID or AAD ID. This PoC is using the
										# Teams ID but you could use AAD ID and make a call to Get-MGUser in the calling
										# script to get supplementary information (e.g. upn/samaccountname/etc).
										"id"   = $AtMentionObject.id
										"name" = $AtMentionObject.name
									}
								}
							}
						)
					}
					"`$schema"        = "http://adaptivecards.io/schemas/adaptive-card.json"
					"version"         = "1.4"
					"backgroundImage" = [ordered]@{
						"horizontalAlignment" = "Center"
						"url"                 = "data:image/jpg;base64,$BackgroundImageBase64String"
						"fillMode"            = "RepeatHorizontally"
					}
				}
			}
		)
	}
	$Body | ConvertTo-Json -Depth 10 #-Compress
}


#############################################################################################################
function global:New-TeamsPlainTextMessageJSON
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[String]
		$Text
	)

	$Body = [pscustomobject]@{
		'type' = "message"
		'text' = $Text
	}
	$Body | ConvertTo-Json -Compress
}