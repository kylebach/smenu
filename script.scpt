tell application "Spotify"
    if player state is playing then
        set currentTrack to name of current track
        set currentArtist to artist of current track
        set currentAlbum to album of current track
        
        return "Now playing: " & currentTrack & " by " & currentArtist & " from the album " & currentAlbum
    else
        return "Spotify is not currently playing"
    end if
end tell
