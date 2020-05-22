#!/bin/bash

InitialiseVariables(){
   # The user ID needs to be the same as the account which owns the pCloud folder, or uploads will fail
   user_id="1000"
   
   # Password to encrypt the uploaded file with
   zip_password="MyPassword1"

   # The locations of the Videos, TV Shows and Music root directories. 
   videos_path="/storage/videos/"
   tvshows_path="/storage/tvshows/"
   music_path="/storage/music/"

   # The Telegram bot token and chat ID for notifications
   telegram_token="<tokenpart1>:<tokenpart2>"
   telegram_chat_id="<chatID>"
   telegram_url="https://api.telegram.org/bot${telegram_token}/sendMessage"   
   
   script_name="$(basename "${0}")"
   lock_file="/run/lock/$(basename "${0}").lock"
   result="Pass"
}

DebugLog(){
   if [ -t 0 ]; then
      echo "$(date '+%c') | ${1}"
   fi
}

CheckParameters(){
   if [ "${1}" = "--force" ]; then
      DebugLog "Force starting script: ${script_name}"
      if [ -e "/run/lock/${script_name}.lock" ]; then rm "/run/lock/${script_name}.lock"; fi
      for process_id in $(pidof -x "${BASH_SOURCE[0]}"); do
         if [ "${process_id}" != $$ ]; then
            kill -9 "${process_id}"
         fi
      done
   else
      DebugLog "Starting script: ${script_name}"
   fi
}

CheckUser(){
   DebugLog "Checking if running as user ID: ${user_id}"
   local uid
   uid="$(id --user)"
   if [ "${uid}" -ne "${user_id}" ]; then
      DebugLog "Script must be run as user ID: ${user_id}"
      exit 1
   fi
}

TestLock(){
   DebugLog "Checking for file lock"
   if [ -f "${lock_file}" ]; then
      DebugLog "Script already running, exiting"
      exit 1
   fi
}

ScriptLock(){
   DebugLog "Locking script"
   echo "${$}" > "${lock_file}"
}

RemoveLock(){
   DebugLog "Removing lock file"
   if [ -f "${lock_file}" ]; then
      rm "${lock_file}"
      exit 0
   fi
}

BuildVideosList(){
   DebugLog "Build Videos list"
   if ! videos=$(find ${videos_path} -mindepth 2 -not -path '*/\.*' -type f -size +50M -printf '%P\n'); then
      result="Fail"
      DebugLog "Failed creating list for Videos"
   else
      echo "${videos}" | sed 's/\// - /' | sort > /tmp/list-Videos.txt
   fi
}

BuildTVShowsList(){
   DebugLog "Build TV Shows list"
   if ! tvshows=$(find ${tvshows_path} -mindepth 2 -not -path '*/\.*' -type f -size +50M -printf '%P\n'); then
      result="Fail"
      DebugLog "Failed creating list for TV Shows"
   else
      echo "${tvshows}" | sed 's/\// - /' | sort > /tmp/list-TVShows.txt
   fi
}

BuildMusicList(){
   DebugLog "Build Music list"
   if ! music=$(find ${music_path} -mindepth 2 -not -path '*/\.*' -type d -printf '%P\n'); then
      result="Fail"
      DebugLog "Failed creating list for Music"
   else
      echo "${music}" | sed 's/\// - /' | sort > /tmp/list-Music.txt
   fi
}

CompressList(){
   DebugLog "Compress list"
   if ! /usr/bin/7za a -p"${zip_password}" -mx9 -l -y /tmp/StorageList-All.7z /tmp/list-*.txt >/dev/null; then
      result="Fail"
      DebugLog "Failed creating compressed file"
   fi
}

CleanUp(){
   DebugLog "Remove Temporary files"
   if ! rm /tmp/list-*.txt; then
      result="Fail"
      DebugLog "Failed removing temp files"
   fi
}

UploadToCloud(){
   DebugLog "Move list to pCloudDrive"
   if ! mv /tmp/StorageList-All.7z "/home/$(id --user --name)/pCloudDrive/"; then
      result="Fail"
      DebugLog "Failed moving compressed file to pCloudDrive"
   fi
}

CompletionNotification(){
   if [ "${result}" = "Pass" ]; then
      DebugLog "Creating Media List Successful"
      SendTelegramNotification "Create Media List" "Indexing Complete" "Successful"
   else
      DebugLog "Creating Media List Failed."
      SendTelegramNotification "Create Media List" "Indexing Complete" "FAILED"
      exit 1
   fi
}

SendTelegramNotification(){
   local application="${HOSTNAME} ${1}"
   local event="${2}"
   local description="${3}"
   # shellcheck disable=SC1083,SC2155
   local encoded_url="$(echo "${4}" | curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" | cut -c 3-)"
   curl --silent --request POST "${telegram_url}" \
      --data chat_id="${telegram_chat_id}" \
      --data parse_mode="markdown" \
      --data text="${application}%0A${event}%0A${description}%0A${encoded_url}" \
      >/dev/null 2>&1
}

##### Start script #####
InitialiseVariables
CheckParameters
# Check script is running as specified user ID
CheckUser
# Check script not already running, exit if it is
TestLock
# Lock the script
ScriptLock
# Send startup notification
DebugLog "Sending startup notification"
SendTelegramNotification "Create Media List" "Indexing Started" "Videos, TV Shows and Music"
# Build Videos list
BuildVideosList
# Build TV Shows list
BuildTVShowsList
# Build Music list
BuildMusicList
# Compress the list and password protect it
CompressList
# Clean up temporary files
CleanUp
# Upload file to pCloudDrive
UploadToCloud
# Make sure everything worked
CompletionNotification
# Remove lock file
RemoveLock
