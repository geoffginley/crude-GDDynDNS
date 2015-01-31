
$workDir = 'C:\ps_Gd_Dns\'

$gdrtrLoginName = 'login name or customer id' # need to be updated
$gdLoginPassword = 'password' # need to be updated

function GetWanIp() {
	# Get WAN IP from External Service
	# http://www.whatsmyip.org/ - <Header> - "For IP API, visit http://www.realip.info/api/p/realip.php" 
	$wanLoop1 = $false
	[int]$wanRetryCount1 = 0
	while (!$wanLoop1) {
		try { 
			$webWanIp = (irm -Uri 'http://www.realip.info/api/p/realip.php').IP 
			Write-Host "Successfully retrieved IP: $webWanIp from realip"
			$wanLoop1 = $true
		}catch { 
			if ($wanRetryCount1 -ge 3){
				Write-Host "Error while getting wan ip from realip, after 3 retrys."
				Write-Host $_.Exception.Message
				$wanLoop1 = $true
			}else {
				Write-Host "Error while getting wan ip from realip, retrying in 10 seconds..."
				sleep -Seconds 10
				$wanRetryCount1++
			}
		}
	}
	# 2nd source 'http://myip.dnsomatic.com/'
	if(!$webWanIp) {
		$wanLoop2 = $false
		[int]$wanRetryCount2 = "0"
		while (!$wanLoop2) {
			try { 
				$webWanIp = irm -Uri 'http://myip.dnsomatic.com/' 
				Write-Host "Successfully got IP: $webWanIp from dnsomatic"
				$wanLoop2 = $true
			}catch { 
				if ($wanRetryCount2 -ge 3){
					Write-Host "Error while getting wan ip from realip, after 3 retrys."
					Write-Host $_.Exception.Message
					$wanLoop2 = $true
					return $null
				}else {
					Write-Host "Error while getting wan ip from realip, retrying in 10 seconds..."
					sleep -Seconds 10
					$wanRetryCount2++
				}
			}
		}
	}else { $wanIp = $webWanIp }

	return $wanIp
}

function GetGdRecords() {
	$loginParams = @{loginname= $gdrtrLoginName;password= $gdLoginPassword}
	
	$gd1Loop = $false
	[int]$gd1RetryCount = 0
	
	while(!$gd1Loop) {
		try { 
			$reqDnsUri = iwr -Uri 'https://dns.godaddy.com/ZoneFile.aspx?zone=theginleys.com&zoneType=0&sa=' -Method POST -Body $loginParams -SessionVariable gdSession 
			# Login_userEntryPanel2_divUserPrompt - successful or not still get ResponseUri required
			$gd1Loop = $true
		}catch { 
			if ($gd1RetryCount -ge 3){
				Write-Host "Initial attempt to login to Godaddy failed, after 3 retrys."
				$gd1Loop = $true
				return $null
			}else {
				Write-Host "Initial attempt to login to Godaddy failed, retrying in 10 seconds..."
				Write-Host $_.Exception.Message
				$gd1RetryCount++
				sleep -Seconds 10
			}
		}
	}

	$reqRecords = $null
	$reqRecords = @{}
	
	$gd2Loop = $false
	[int]$gd2RetryCount = 0
	
	while(!$gd2Loop) {
		try { 
			$reqRecords = (iwr -Uri $reqDnsURI.BaseResponse.ResponseUri.AbsoluteUri -WebSession $gdSession -Method POST -Body $loginParams).Forms[0].Fields
			If($reqRecords.keys -match 'tblARecords') {
				Write-Host 'Successfully grabbed records from Godaddy zone edit'
				$gd2Loop = $true
			} else { Write-Host 'Issue gathering necessary fields, most likely a login issue'; throw 'Record fields missing' }
		}catch { 
			if ($gd2RetryCount -ge 3){
				Write-Host "Zone edit login to Godaddy failed, after 3 retrys."
				$gd2Loop = $true
				return $null
			}else {
				Write-Host "Zone edit login to Godaddy failed, retrying in 10 seconds..."
				Write-Host $_.Exception.Message
				$gd2RetryCount++
				sleep -Seconds 10
			}
		}
	}
	
	$aRecords = @{}
	
	foreach($r in $reqRecords.Keys) {
		if($r -match "ARecords" -and $r -match "Records_\d_" -and $r -notmatch '_chk') {
			$ar = $null; $ar = @(); $ar = $r.Split('_')
			$aRec = $ar[0] + '_' + $ar[1]
			$aRecord = $null; $aRecord = @{}; $aRecord.Add($r,$reqRecords[$r])
			$aRecords[$aRec] += $aRecord
		}
	}
	if(!$aRecords) { Write-Host "There doesn't appear to be any A record on Godaddy"; return $null }
	else { return $aRecords }
}

function UpdateGdDns() {
	
	param(
		[Parameter(Position = 0)]
		$ip,
		[Parameter(Position = 1)]
		$updates
	)
	$ieLoop = $false
	[int]$ieRetryCount = 0

	$ie = New-Object -COM InternetExplorer.Application
	$ie.Visible = $true
	$ie.Navigate('https://sso.godaddy.com?path=sso%2freturn&amp;app=www')

	While ($ie.Busy) {Sleep 15}

	if($ie.Document.title -eq "You’re not connected to a network") {
		Write-Host $ie.Document.title
		return $false 
	}else {
		while (!$ieLoop) {
			try { 
				$ie.Document.getElementById("username").value = $gdrtrLoginName
				$ie.Document.getElementById("password").value = $gdLoginPassword
				$ie.Document.getElementById("login-form").submit()
				
				While ($ie.Busy) {Sleep 15}
				
				# Check to see if logged in
				if($ieErr1 = $ie.Document.getElementById('errorMessage').innerText) {
					throw $ieErr1
					# 2 known for now - retry below - 2nd needs additional logic
					# Authentication failed. You entered an incorrect username, or password.
					# Looks like you're having trouble logging in. Please wait 23 secs before trying again.
				}else { 
					Write-Host 'Successfully logged in through IE' 
					$ie.Navigate('https://dns.godaddy.com/ZoneFile.aspx?zone=theginleys.com&zoneType=0&sa=')

					While ($ie.Busy) {Sleep 15}

					if($ie.Document.title -ne 'DNS Manager - Zone File Editor') { 
						$ie.Navigate('https://sso.godaddy.com?path=sso%2freturn&amp;app=www')
						
						While ($ie.Busy) {Sleep 15}
						
						throw "$($ie.Document.title) != DNS Manager - Zone File Editor"
					}else {
						$ip = "'$ip'"
						Write-Host 'Attempting to update records'
						foreach($u in $updates.keys) {
							$record = $null; $record = "'$u'"
							$hostName = $null; $ttl = $null
							foreach($k in $updates[$u].keys) { 
								if($k -match 'ttl') { $ttl = $updates[$u][$k]; $ttl = "'$ttl'" }
								if($k -match 'host') { $hostName = $updates[$u][$k]; $hostName = "'$hostName'" }
							}
							$jsDelCmd = "DeleteARecord($record);"
							$jsAddCmd = "ARecordQuickAddPage($hostName,$ip,$ttl);"
							
							$ie.Navigate("javascript:$jsDelCmd")
							$ie.Navigate("javascript:$jsAddCmd")
							While ($ie.Busy) {Sleep 15}
						}
						# Does NOT work? - While ($ie.Busy -and ($ie.readyState -eq 4 -or $ie.readyState -eq 'complete')) {Sleep 5}
						$ie.Navigate("javascript:SaveChanges();")
						sleep 5
						$ie.Navigate("javascript:Popin.OnOkTwo();")
						sleep 5
						$ie.Navigate("javascript:Popin.OnOkTwo();")
						sleep 5
						$ie.quit()
						$ieLoop = $true; return $true
					}	
				} 
			}catch { 
				if ($ieRetryCount -ge 3){
					Write-Host "Error while attempting to update records, after 3 retrys."
					$ieLoop = $true; return $false
				}else {
					Write-Host "Error while attempting to update records, retrying in 10 seconds..."
					Write-Host $_.Exception.Message
					sleep -Seconds 10
					$ieRetryCount++
				}
			}
		}
	}return $true
}

function Main() {
	$currentWanIp = $null; $existingWanIp = $null
	#check if there is file (state record) of last known IP
	if($existingWanIp = (gci $workDir | ?{$_ -match "~\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}~"}).Name.Trim('~')) {
		Write-Host "Existing IP: $existingWanIp found from file"
		$currentWanIp = GetWanIp
		if(!$currentWanIp) { break }
		#if there is, does it match current
		if($existingWanIp -eq $currentWanIp) { write 'Records appear to be up to date';break }
		#if it doesn't, work to do
		else {
			$updateRecords = $null;$updateRecords = @{}
			$recsToRemove = $null;$recsToRemove = @()		
			$currentGdRecords = GetGdRecords
			if(!$currentGdRecords) { break }
			elseif($numExistRec = ($currentGdRecords.values.values | ?{$_ -match $existingWanIp}).count) {
				Write-Host "There appears to be $numExistRec records on Godaddy with the old IP: $existingWanIp" 
				#Iterate through the recorrds returned see what records match old ip
				foreach($rec in $currentGdRecords.keys) {
					foreach($read in $currentGdRecords[$rec]) {
						#Create list of records that don't match old ip, to remove 
						if(!($read.values -match $existingWanIp)) {
						$recsToRemove += $rec 
						} 
					}
				}
				foreach($r in $recsToRemove) { $currentGdRecords.remove($r) }
				$updateRecords = $currentGdRecords
			}else { Write-Host "There doesn't appear to be any records on Godaddy with the old IP: $existingWanIp";break }
		}
		$updated = UpdateGdDns $currentWanIp $updateRecords
		if(!$updated) { break }
		#verify changes
		Write-Host 'Verifying records where updated'
		$verifyGdRecords = GetGdRecords
		if(!$verifyGdRecords) { break }
		elseif($numNewRec = ($verifyGdRecords.values.values | ?{$_ -match $currentWanIp}).count) {
			if($numNewRec -eq $numExistRec) {
				ni -Path $workDir -name "~$currentWanIp~" -ItemType 'file' -Force
				mi -Path "$workDir~$existingWanIp~" -Destination "$workDir\updated\~$existingWanIp~" -Force
			}else { "$numNewRec records created but $numExistRec existed" }
		}else { 'oops' }
	}else { Write-Host 'Reference IP is Missing, see Instructions'}
}

Main
