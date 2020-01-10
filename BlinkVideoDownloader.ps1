#######################################################################################################################
#
# Author: Nayrk
# Date: 12/28/2018
# Last Updated: 6/12/2019
# Purpose: To download all Blink videos locally to the PC. Existing videos will be skipped.
# Output: All Blink videos downloaded in the following directory format.
#         Default Location Desktop - "C:\Users\<UserName>\Desktop"
#         Sub-Folders - Blink --> Home Network Name --> Camera Name #1
#                                                   --> Camera Name #2
#
# Notes: You can change anything below this section.
# Credits: https://github.com/MattTW/BlinkMonitorProtocol
#
#######################################################################################################################

# Change saveDirectory directory if you want the Blink Files to be saved somewhere else, default is user Desktop
$saveDirectory = "C:\Users\$env:UserName\Desktop"

# Blink Credentials. Please fill in!
# Please keep the quotation marks "
$email = "Your Email Here"
$password = "Your Password Here"

# Blink's API Server, this is the URL you are directed to when you are prompted for IFTTT Integration to "Grant Access"
# You can verify this yourself to make sure you are sending the data where you expect it to be
$blinkAPIServer = 'prod.immedia-semi.com'

# Use this server below if you are in Germany. Remove the # symbol below.
# $blinkAPIServer = 'prde.immedia-semi.com'

#######################################################################################################################
#
# Do not change anything below unless you know what you are doing or you want to...
#
#######################################################################################################################

if($email -eq "Your Email Here") { Write-Host 'Please enter your email by modifying the line: $email = "Your Email Here"'; pause; exit;}
if($password -eq "Your Password Here") { Write-Host 'Please enter your password by modifying the line: $password = "Your Password Here"'; pause; exit;}

# Headers to send to Blink's server for authentication
$headers = @{
    "Host" = "$blinkAPIServer"
    "Content-Type" = "application/json"
}

# Credential data to send
$body = @{
    "email" = "$email"
    "password" = "$password"
} | ConvertTo-Json

# Login URL of Blink API
$uri = "https://$blinkAPIServer/login"

# Authenticate credentials with Blink Server and get our token for future requests
$response = Invoke-RestMethod -UseBasicParsing $uri -Method Post -Headers $headers -Body $body
if(-not $response){
    echo "Invalid credentials provided. Please verify email and password."
    pause
    exit
}

# Get the object data
$region = $response.region.psobject.properties.name
$authToken = $response.authtoken.authtoken
$accountID = $response.account.id

# Headers to send to Blink's server after authentication with our token
$headers = @{
    "Host" = "$blinkAPIServer"
    "TOKEN_AUTH" = "$authToken"
}

# Get list of networks
$uri = 'https://rest-'+ $region +".immedia-semi.com/api/v1/camera/usage"

# Use old endpoint to get list of cameras with respect to network id
$sync_units = Invoke-RestMethod -UseBasicParsing $uri -Method Get -Headers $headers
foreach($sync_unit in $sync_units.networks)
{
    $network_id = $sync_unit.network_id
    $networkName = $sync_unit.name
    
    foreach($camera in $sync_unit.cameras){
        $cameraName = $camera.name
        $cameraId = $camera.id
        $uri = 'https://rest-'+ $region +".immedia-semi.com/network/$network_id/camera/$cameraId"
     
        $camera = Invoke-RestMethod -UseBasicParsing $uri -Method Get -Headers $headers
        $cameraThumbnail = $camera.camera_status.thumbnail

        # Create Blink Directory to store videos if it doesn't exist
        $path = "$saveDirectory\Blink\$networkName\$cameraName"
        if (-not (Test-Path $path)){
            $folder = New-Item  -ItemType Directory -Path $path
        }

        # Download camera thumbnail
        $thumbURL = 'https://rest-'+ $region +'.immedia-semi.com' + $cameraThumbnail + ".jpg"
        $thumbPath = "$path\" + "thumbnail_" + $cameraThumbnail.Split("/")[-1] + ".jpg"
        
        # Skip if already downloaded
        if (-not (Test-Path $thumbPath)){
            echo "Downloading thumbnail for $cameraName camera in $networkName."
            Invoke-RestMethod -UseBasicParsing $thumbURL -Method Get -Headers $headers -OutFile $thumbPath
        }
    }
}

$pageNum = 1

# Continue to download videos from each page until all are downloaded
while ( 1 )
{
    # List of videos from Blink's server
    # $uri = 'https://rest-'+ $region +'.immedia-semi.com/api/v2/videos/page/' + $pageNum
    
    # Changed to use old endpoint
    #$uri = 'https://rest-'+ $region +'.immedia-semi.com/api/v2/videos/changed?since=2016-01-01T23:11:21+0000&page=' + $pageNum

    # Changed endpoint again
    $uri = 'https://rest-'+ $region +'.immedia-semi.com/api/v1/accounts/'+ $accountID +'/media/changed?since=2020-01-01T00:00:00+0000&page=' + $pageNum

    Write-Output $uri

    # Get the list of video clip information from each page from Blink
    $response = Invoke-RestMethod -UseBasicParsing $uri -Method Get -Headers $headers
    
    # No more videos to download, exit from loop
    if(-not $response.media){
        Write-Debug("No media to download.")
        break
    }

    # Go through each video information and get the download link and relevant information
    foreach($video in $response.media){
        Write-Debug ("Should download " + $video.media + " for $camera camera in $network?")

        # Video clip information
        $address = $video.media
        $timestamp = $video.created_at
        $network = $video.network_name
        $camera = $video.device_name
        $camera_id = $video.camera_id
        $deleted = $video.deleted
        if($deleted -eq "True"){
            continue
        }
       
        Write-Debug ("Downloading " + $video.media + " for $camera camera in $network.")

        # Get video timestamp in local time
        $videoTime = Get-Date -Date $timestamp -Format "yyyy-MM-dd_HH-mm-ss"

        # Download address of video clip
        $videoURL = 'https://rest-'+ $region +'.immedia-semi.com' + $address
        
        # Download video if it is new
        $path = "$saveDirectory\Blink\$network\$camera"
        $videoPath = "$path\$videoTime.mp4"
        if (-not (Test-Path $videoPath)){
            try {
                Invoke-RestMethod -UseBasicParsing $videoURL -Method Get -Headers $headers -OutFile $videoPath 
                $httpCode = $_.Exception.Response.StatusCode.value__        
                if($httpCode -ne 404){
                    Write-Debug ("Downloading {0} for {1} camera in {2} to {3}." -f $video.media,$camera,$network,$videoPath)
                } else{
                    Write-Output ("Video not found")
                }
            } catch { 
                $msg = "Error while downloading {0} for {1} camera in {2} to {3}." -f $video.media,$camera,$network,$videoPath
                $httpCode = "{0}" -f $httpCode
                $exMsg = "{0}" -f $_.Exception.Message
                Write-Output ($httpCode + $exMsg + $msg)
            }
        }

        Write-Debug ("Downloaded " + $video.media +" for $camera camera in $network to $videoPath.")
    }
    $pageNum += 1
}
Write-Output ("All new videos and thumbnails downloaded to $saveDirectory\Blink\")

# Remove "pause" command below for automation through Windows Scheduler
pause
