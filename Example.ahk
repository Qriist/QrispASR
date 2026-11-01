#Requires AutoHotkey v2.1-
; #include <Aris/Qriist/QrispASR>
#Include <QrispASR>

crisp := QrispASR()

;always get a serverObj even if a server is already running
serverObj := crisp.ConstructServerObject("bt2-tts")
serverObj := crisp.StartServer(serverObj)

crisp.SubmitVoice(serverObj,
    audioPath := A_ScriptDir "\sample voices\Piedmont.wav",
    audioName := "Piedmont",
    transcriptPath := A_ScriptDir "\sample voices\Piedmont.txt",
    1   ;allow overwrite
)

;create a ttsObject to default most variables
ttsObject := crisp.ConstructTtsObject(serverObj)
ttsObject["voice"] := "Piedmont"
ttsObject["seed"] := 87

;execute
ttsObject["input"] := "Never gonna give you up, never gonna let you down."
destination := A_ScriptDir "\You know the rules-01.wav"
crisp.TTS(serverObj, ttsObject, destination)

ttsObject["input"] := "Never gonna run around and desert you, never gonna make you cry."
destination := A_ScriptDir "\You know the rules-02.wav"
crisp.TTS(serverObj, ttsObject, destination)

ttsObject["input"] := "Never gonna say goodbye, never gonna tell a lie and hurt you."
destination := A_ScriptDir "\You know the rules-03.wav"
crisp.TTS(serverObj, ttsObject, destination)