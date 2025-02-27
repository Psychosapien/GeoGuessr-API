function Get-GGStats {
    [CmdletBinding()]
    param (

    )

    begin {

        $token = Get-Content $env:temp/ncfa.gg -ErrorAction SilentlyContinue
        If (!$token) {
            Write-host "Please log into GeoGuessr in a browser and then find your _ncfa cookie. This can be found in the dev tools under cookies for www.geoguessr.com" -ForegroundColor Red

            do {
                $ncfa = Read-Host "enter token value..."
            } until (
                $ncfa -ne ""
            )

            $ncfa | Set-Content $env:temp/ncfa.gg
            $token = Get-Content $env:temp/ncfa.gg
        }

        $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $c = New-Object System.Net.Cookie('_ncfa', $token, '/', 'geoguessr.com')
        $s.Cookies.Add($c)

        $guessArray = @()
    }

    process {

        $challengeUrl = "https://www.geoguessr.com/api/v4/feed/private"
        $challenge = Invoke-WebRequest -UseBasicParsing -Uri $challengeUrl -WebSession $s
        $allITems = ($challenge.Content | ConvertFrom-Json).entries

        $regularGames = ($allITems.payload | ConvertFrom-Json).payload.gameToken
        $duelGames = (($allITems.payload | ConvertFrom-Json).payload | Where-Object { $_.GameMode -eq "Duels" }).gameId

        $counter = 1

        # Classic Games
        foreach ($game in $regularGames) {

            Write-Progress -Activity "Working on regular games..." -PercentComplete (($counter / $regularGames.count ) * 100) -Id 1 -Status "$counter of $($regularGames.count)"
            if ($null -ne $game) {
                $gameUrl = "https://www.geoguessr.com/api/v3/games/$game"

                $gameStats = Invoke-WebRequest -UseBasicParsing -Uri $gameUrl -WebSession $s
                $guesses = ($gameStats.content | ConvertFrom-Json).player.guesses
                $rounds = ($gameStats.content | ConvertFrom-Json).rounds

                $i = 0

                foreach ($guess in $guesses) {
                    $countryCode = $guess.streakLocationCode

                    If ($null -eq $countryCode) {
                        $countryCode = $rounds[$i].streakLocationCode
                    }

                    $guessesObject = New-Object psobject
                    add-member -InputObject $guessesObject -MemberType NoteProperty -Name countryCode -Value $countryCode -TypeName string
                    add-member -InputObject $guessesObject -MemberType NoteProperty -Name roundScore -Value $guess.roundScoreInPoints -TypeName string
                    add-member -InputObject $guessesObject -MemberType NoteProperty -Name percentScore -Value $guess.roundScoreInPercentage -TypeName string

                    $guessArray += $guessesObject
                }
            }

            $counter++
        }

        $counter = 1
        # Duels
        foreach ($game in $duelGames) {
            Write-Progress -Activity "Working on duel games..." -PercentComplete (($counter / $duelGames.count ) * 100) -Id 2 -Status "$counter of $($duelGames.count)"

            if ($null -ne $game) {

                $gameUrl = "https://www.geoguessr.com/_next/data/dLcj81abw_a6uvymo9JQs/en/duels/$game/summary.json?token=$game"

                $gameStats = Invoke-WebRequest -UseBasicParsing -Uri $gameUrl -WebSession $s

                $guesses = (($gameStats.Content | ConvertFrom-Json).pageprops.game.teams.players | Where-Object { $_.nick -eq "psychoSapien" }).guesses

                $i = 0

                foreach ($guess in $guesses) {

                    $countryCodeUri = "http://api.geonames.org/countryCodeJSON?lat=$($guess.lat)&lng=$($guess.lng)&username=psychosapien"
                    $countryCode = ((Invoke-WebRequest -Uri $countryCodeUri).Content | ConvertFrom-Json).countryCode

                    $guessesObject = New-Object psobject
                    add-member -InputObject $guessesObject -MemberType NoteProperty -Name countryCode -Value $countryCode -TypeName string
                    add-member -InputObject $guessesObject -MemberType NoteProperty -Name roundScore -Value $guess.score -TypeName string
                    add-member -InputObject $guessesObject -MemberType NoteProperty -Name percentScore -Value ($guess.score / 5000 * 100) -TypeName string

                    $guessArray += $guessesObject
                }
            }

            $counter++
        }

        $countries = $guessArray | Where-Object { $null -ne $_.countryCode } | Group-Object countryCode | Sort-Object count
        $averageArray = @()

        foreach ($country in $countries) {
            $avPercent = ($country.group.PercentScore | Measure-Object -Average).Average
            $avScore = ($country.group.roundScore | Measure-Object -Average).Average
            $avCount = ($country.group.PercentScore | Measure-Object -Average).Count

            $averageObject = New-Object psobject
            add-member -InputObject $averageObject -MemberType NoteProperty -Name "Country" -Value $country.name -TypeName string
            add-member -InputObject $averageObject -MemberType NoteProperty -Name avPercent -Value ([math]::floor($avPercent) )-TypeName int
            add-member -InputObject $averageObject -MemberType NoteProperty -Name "Average Score" -Value ([math]::floor($avScore) )-TypeName int
            add-member -InputObject $averageObject -MemberType NoteProperty -Name "Count" -Value $avCount -TypeName string

            $averageArray += $averageObject
        }

        $worst5 = $averageArray | Where-Object { $_.Count -gt 2 } | Sort-Object avPercent | Select-Object -First 5
        $top3 = $averageArray | Where-Object { $_.Count -gt 2 } | Sort-Object avPercent | Select-Object -Last 3

        Write-Host "------------------------------------------" -ForegroundColor white
        Write-Host "All done!" -ForegroundColor Green
        Write-Host "------------------------------------------`n" -ForegroundColor white

        Write-Host "I have analysed $($regularGames.count + $duelGames.count) games in total." -ForegroundColor Yellow
        Write-Host "------------------------------------------" -ForegroundColor white
        Write-Host "Regular games:$($regularGames.count)" -ForegroundColor Yellow
        Write-Host "Duel games:$($duelGames.count)" -ForegroundColor Yellow
        Write-Host "------------------------------------------`n" -ForegroundColor white

        Write-Host "Here are your worst 5 countries from the last month:" -ForegroundColor Red

        foreach ($entry in $worst5) {
            $countryUrl = "https://restcountries.com/v3.1/alpha/$($entry.country)"
            $countryInfo = Invoke-WebRequest $countryUrl
            $countryName = ($countryInfo.Content | ConvertFrom-Json).name.common

            $entry.country = $countryName
        }

        $worst5 | Select-Object country, "Average Score", count | Format-Table
        Write-Host "------------------------------------------`n" -ForegroundColor white

        Write-Host "`nHere are your top 3 countries from the last month:" -ForegroundColor Cyan

        foreach ($entry in $top3) {
            $countryUrl = "https://restcountries.com/v3.1/alpha/$($entry.country)"
            $countryInfo = Invoke-WebRequest $countryUrl
            $countryName = ($countryInfo.Content | ConvertFrom-Json).name.common

            $entry.country = $countryName
        }

        $top3 | Select-Object country, "Average Score", count | Sort-Object avScore -Descending | Format-Table

    }

    end {
    }
}