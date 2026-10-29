#Requires AutoHotkey v2.1-
; #include <Aris/Qriist/QrispASR>
#Include <QrispASR>

crisp := QrispASR()

;always get a serverObj even if a server is already running
serverObj := crisp.StartServer()

crisp.SubmitVoice(serverObj,
    audioPath := A_ScriptDir "\sample voices\Piedmont.wav",
    audioName := "Piedmont",
    transcriptPath := A_ScriptDir "\sample voices\Piedmont.txt",
    1   ;allow overwrite
)