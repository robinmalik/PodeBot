Write-PodeHost -Object "Adding PodeRoute for /api/messages"
Add-PodeRoute -Method Post -Path '/api/messages' -ContentType 'application/json' -ScriptBlock {
	Write-PodeHost -Object "$($WebEvent.Route.Path) invoked with method: $($WebEvent.Route.Method)"

	# Convert JSON into an object so we can work with it:
	$Data = $WebEvent.Request.Body | ConvertFrom-Json

	# Some of these properties may be empty, depending on the request type.
	# Nevertheless output something for all requests to help with debugging at the terminal.
	Write-PodeHost -Object "Received: Type: $($Data.type) | Name: $($Data.from.name) | ID: $($Data.from.id) | Text: $($Data.text)"

	########################################################################################
	# Handle incoming messages:
	if($Data.type -eq 'message')
	{
		if(!$Data.text)
		{
			Write-PodeHost -Object "Type was $($Data.type) but '.text' was empty. Returning."
			return
		}

		# When messages are sent from within a channel they're prepended with '<at>BotName</at> '. Strip.
		$Text = (($Data.text -replace "<at>.*</a> ", '') -replace "\n", '').Trim()
		Write-PodeHost -Object "Parsed text: $Text"

		# Handle the example conditions. The logic of this could be adapted, obviously.
		if($Text -eq 'pt')
		{
			# Do some work the user has requested and send them a response:
			$JSON = New-TeamsPlainTextMessageJSON -Text "You requested something. Here it is: _________."
		}
		elseif($Text -eq 'ptwu')
		{
			# Let them know you received the request:
			$JSON = New-TeamsPlainTextMessageJSON -Text "Hi, leave it with me 🫡."
			# Do the work later.
			$UpdateRequired = $True
		}
		elseif($Text -eq 'ac')
		{
			# Do some work and send an adaptive card. Let's mock an object to create a factset for the card:
			$FactSet = [PSCustomObject]@{
				Fact1 = "Pode rocks 😁"
				Fact2 = "I want to work from Thailand"
			}
			# Mock a set of actions:
			$Actions = @(
				[pscustomobject]@{
					type  = 'Action.OpenUrl'
					title = 'Link here'
					url   = "https://docs.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/what-are-cards"
				}
				[pscustomobject]@{
					type  = 'Action.OpenUrl'
					title = 'Another link'
					url   = "https://docs.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema"
				}
			)
			# Mock an object if you want to @mention the person:
			$AtMentionObject = [pscustomobject]@{
				'id'   = $Data.from.id
				'name' = $Data.from.name
			}
			$JSON = New-TeamsAdaptiveCardMessageJSON -TitleText "Simple adaptive card!" -Level Success -FactSetObject $FactSet -Actions $Actions -AtMentionObject $AtMentionObject
		}
		else
		{
			Write-PodeHost -Object "Text '$Text' is unhandled. Returning."
			return
		}
	}
	elseif($Data.type -eq 'invoke')
	{
	}
	else
	{
		return
	}

	# At this point, we should have JSON to send the intial response.

	########################################################################################
	# Generate the URL that the bot should send a reply to:
	$ReplyURL = "$($Data.serviceUrl)/v3/conversations/$($Data.conversation.id)/activities"

	# Get the access token and generate some headers for the reply:
	$BotAccessToken = (Get-PodeState -Name BotAccessToken).TokenObject
	$Headers = @{Authorization = "Bearer $($BotAccessToken.access_token)" }

	# Send the response to Teams:
	$SentResponse = Invoke-RestMethod -Method Post -Uri $ReplyURL -Headers $Headers -Body $JSON -ContentType "application/json; charset=UTF-8"

	########################################################################################
	if($UpdateRequired -eq $True)
	{
		if($Text -eq 'ptwu')
		{
			# Do some long running work/task and then update the previous message (replace the contents).
			# You could even update along the way, if you wanted, though I don't know if you'd hit throttling limits.
			Start-Sleep -Seconds 3
			Write-PodeHost -Object "Sending an update to conversation id: $($SentResponse.Id)"
			$UpdateObject = [pscustomobject]@{
				'type'         = 'message'
				'id'           = $SentResponse.Id
				'conversation' = [PSCustomObject]@{
					'id' = $Data.conversation.id
				}
				'text'         = "Finished! 🥳"
			}
			$UpdateURL = "$($Data.serviceUrl)/v3/conversations/$($Data.conversation.id)/activities/$($SentResponse.Id)"
			Invoke-WebRequest -Method Put -Uri $UpdateURL -Headers $Headers -Body $($UpdateObject | ConvertTo-Json) -ContentType "application/json; charset=UTF-8" | Out-Null
		}
	}
}