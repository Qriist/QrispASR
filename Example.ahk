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
ttsObject := crisp.ConstructTtsObject(serverObj)
ttsObject["voice"] := "Piedmont"
ttsObject["seed"] := 17

ttsObject["input"] := "Never gonna give you up, never gonna let you down."
destination := A_ScriptDir "\You know the rules.wav"
destFlac := A_ScriptDir "\You know the rules.flac"
crisp.TTS(serverObj, ttsObject, destination)