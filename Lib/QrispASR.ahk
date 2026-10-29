#Requires AutoHotkey v2.1-
#include <Aris/Cebolla/Timer> ; Cebolla/Timer@v1.12.0
#include <Aris/Chunjee/adash> ; Chunjee/adash@v0.6.0
#include <Aris/G33kDude/cJson> ; G33kDude/cJson@2.1.0
#include <Aris/GroggyOtter/PeepAHK> ; github:Qriist/PeepAHK@v1.3.0 --main script\Peep.v2.ahk
#include <Aris/Qriist/libmagic> ; github:Qriist/libmagic@v0.80.2 --main Lib\libmagic.ahk
#include <Aris/Qriist/LibQurl> ; Qriist/LibQurl@v1.3.0
#include <Aris/Qriist/Null> ; github:Qriist/Null@v1.0.0 --main Null.ahk
#include <Aris/SKAN/RunCMD> ; SKAN/RunCMD@aadeb56

class QrispASR {
    __New(path?) {
        this.curl := LibQurl()
        this.InstallCrisp(path?)
    }
    InstallCrisp(path := A_ScriptDir "\tools\CrispASR") {
        if !DirExist(path)
            DirCreate(path)

        verMap := this.DetermineLatestCrisp()

        if DirExist(path "\" verMap["version"]) {
            this.crispVersion := verMap["version"]
            this.crispRoot := path
            this.crispDir := this.crispRoot "\" this.crispVersion
            this.crisp := this.crispDir "\crispasr.exe"
            this.voiceDir := this.crispRoot "\voices"
            return
        }

        easy_handle := this.curl.EasyInit()
        url := verMap["url"]
        this.curl.SetOpt("URL", url, easy_handle)
        zipfile := path "\" verMap["version"] ".zip"
        this.curl.WriteToFile(zipfile, easy_handle)
        this.curl.SimSync(easy_handle)
        this.curl.Cleanup(easy_handle)

        DirCreate(path "\temp")
        DirCopy(zipfile, path "\temp", 1)
        DirMove(path "\temp\crispasr-windows-x86_64-cuda", path "\" verMap["version"], 1)
        DirDelete(path "\temp")
        FileDelete(zipfile)

        this.crispRoot := path
        this.crispVersion := verMap["version"]
        this.crispDir := this.crispRoot "\" this.crispVersion
        this.crisp := this.crispDir "\crispasr.exe"
        this.voiceDir := this.crispRoot "\voices"
    }
    DetermineLatestCrisp() {
        retMap := Map()
        easy_handle := this.curl.EasyInit()

        url := "https://api.github.com/repos/CrispStrobe/CrispASR/releases/latest"
        this.curl.SetOpt("URL", url, easy_handle)
        this.curl.SetOpt("USERAGENT", "No.", easy_handle)
        this.curl.Sync(easy_handle)

        jsonObj := json.load(this.curl.GetLastBody(, easy_handle))
        this.curl.EasyCleanup(easy_handle)

        retMap["version"] := jsonObj["tag_name"]

        ;find the windows cuda edition
        name := "crispasr-windows-x86_64-cuda.zip"
        for k, v in jsonObj["assets"] {
            if v["name"] != name
                continue
            retMap["url"] := v["browser_download_url"]
            break
        }
        return retMap
    }
    StartServer(serverObj?, serverUrl?) {
        serverObj ??= this.ConstructServerObject()

        ;ensure voiceDir exists
        if !DirExist(this.voiceDir)
            DirCreate(this.voiceDir)

        ;build server cmd
        cmd := adash.join(serverObj["optArr"], " ")

        ;start server
        crispUrl := serverObj["url"] ":" serverObj["port"]
        if !ProcessExist("crispasr.exe")
            Run(cmd, this.crispDir)

        ;wait for server to get running
        easy_handle := this.curl.EasyInit()
        url := crispUrl "/health"
        this.curl.SetOpt("URL", url, easy_handle)

        loop {
            this.curl.Sync(easy_handle)
            httpCode := this.curl.GetLastStatus(easy_handle)

            if a_index > 10000
                ExitApp

            if !httpCode    ;server not up yet
                continue
            ; MsgBox a_index
            jsonObj := json.Load(this.curl.GetLastBody(, easy_handle))
            if jsonObj["status"] = "ok"
                break
            else
                ExitApp
        }
        this.curl.EasyCleanup(easy_handle)   ;server found, cleanup
        return serverObj
    }
    ConstructServerObject(backend?, url?, port?, talker_model?, codec_model?) {
        ;establish defaults
        backend ??= "qwen3-tts-1.7b-base"
        url ??= "http://127.0.0.1"
        port ??= 8080
        voiceDir := this.voiceDir

        ;instance basic object
        serverObj := Map(
            "backend", backend,
            "url", url,
            "port", port,
            "voiceDir", voiceDir,
            "optArr", optArr := [],  ;for CLI construction
            "easy_handle", this.curl.EasyInit()
        )

        ;add backend-specific info
        switch backend {
            case "qwen3-tts-1.7b-base":
                optArr.Push(
                    this.crisp,
                    "--server",
                    "--backend " backend,
                    "-m auto",  ;todo - model config
                    "--port " port,
                    "--voice-dir " '"' voiceDir '"'
                )

            default:
                return this.GetServerObject()
        }

        ;Crisp requires a bunch of bypass flags
        optArr.Push(
            "--speaker-identity synthetic",
            "--no-watermark",
            "--accept-marking-responsibility",
            "--no-spoken-disclaimer"
        )

        return serverObj
    }
    DeleteServerObject(serverObj) {
        this.curl.EasyCleanup(serverObj["easy_handle"])
        serverObj := unset
    }
    SubmitVoice(serverObj, audioPath, audioName, transcriptPath?, overwrite?) {
        if !DirExist(this.voiceDir)
            DirCreate(this.voiceDir)

        ;prepare audio
        tempPath := this.crispRoot "\" A_NowUTC ".wav"

        af := "adelay=1000:all=1,apad=pad_dur=1"    ;padding filter
        cmd := adash.join([
            "ffmpeg",
            "-i " '"' audioPath '"',
            ; "-ac 1",  ;force mono, not sure if needed so disabled
            "-af " '"' af '"',
            "-ar 24000",    ;auto-force to 24khz
            "-c:a pcm_s16le",
            '"' tempPath '"'
        ], " ")
        RunWait(cmd, this.crispDir, "Hide")
        ; msgbox A_Clipboard := cmd
        ;do the actual submit
        easy_handle := this.curl.EasyInit()
        mime_handle := this.curl.MimeInit(easy_handle)

        voicePart := this.curl.AttachMimePart("voice", FileOpen(tempPath, "r"), mime_handle)
        this.curl.AttachMimePart("name", audioName, mime_handle)
        this.curl.AttachMimePart("consent_attestation", "I have the speaker's consent", mime_handle)
        if IsSet(transcriptPath?)
            this.curl.AttachMimePart("transcript", FileRead(transcriptPath, "UTF-8"), mime_handle)

        url := serverObj["url"] ":" serverObj["port"] "/v1/voices" (IsSet(overwrite?) ? "?force=true" : "")
        this.curl.SetOpt("URL", url, easy_handle)
        this.curl.Sync(easy_handle)
        ; MsgBox this.curl.GetLastStatus(easy_handle)
        ; msgbox this.curl.GetLastBody(, easy_handle)
        this.curl.MimeCleanup(mime_handle)
        this.curl.EasyCleanup(easy_handle)
        FileDelete(tempPath)
    }
    TTS(serverObj, ttsObj, destination) {
        easy_handle := serverObj["easy_handle"]

        url := serverObj["url"] ":" serverObj["port"] "/v1/audio/speech"
        this.curl.SetOpt("URL", url, easy_handle)

        this.curl.SetPost(ttsObj, easy_handle)
        this.curl.WriteToFile(destination, easy_handle)

        this.curl.Sync(easy_handle)

        ; MsgBox this.curl.GetLastHeaders(, easy_handle)
        return
    }
    ConstructTtsObject(serverObj, extended?) {
        switch serverObj["backend"] {
            case "qwen3-tts-1.7b-base":
                retObj := Map(
                    "input", Null(),
                    "model", serverObj["backend"],
                    "voice", Null(),
                    ; "instructions", "", ; VoiceDesign only
                    "seed", 0,
                    "temperature", (!IsSet(extended?) ? unset : 0.0),
                    "max_new_tokens", (!IsSet(extended?) ? unset : 0),
                    ; "max_speech_tokens", 0, ; MOSS-TTS only
                    ; "min_speech_tokens", 0, ; MOSS-TTS only
                    "frequency_penalty", (!IsSet(extended?) ? unset : 0.0),
                    ; "top_p", 0.0, ; Backend-specific: TADA/Chatterbox
                    ; "min_p", 0.0, ; Backend-specific sampling
                    ; "top_k", 0, ; Honored by TADA
                    ; "repetition_penalty", 1.0, ; TADA/Chatterbox
                    ; "do_sample", true, ; Honored by TADA
                    ; "num_candidates", 1, ; TADA only
                    ; "num_steps", 10, ; TADA/Chatterbox/F5
                    ; "cfg_scale", 1.0, ; TADA/Chatterbox/F5
                    ; "noise_temp", 0.9, ; TADA only
                    ; "noise_scale", 0.667, ; Piper only
                    ; "noise_w", 0.8, ; Piper only
                    ; "exaggeration", 0.5, ; Chatterbox only
                    ; "speaker_id", 0, ; Piper only
                    ; "phonemes", "", ; Kokoro/Piper only
                    "pad_silence_ms", (!IsSet(extended?) ? unset : 0),
                    "stream", JSON.False,
                    ; "speed", (!IsSet(extended?) ? unset : 1.0),
                    ; "duration", 0, ; OmniVoice only
                    "response_format", "wav",
                    "consent_attestation", "I have the speaker's consent",
                    ; "ref_text", "", ; TADA cloning reference transcript
                    "language", "English",
                    ; "source_lang", "", ; CosyVoice3 only
                    "speaker_identity", "synthetic",
                    "spoken_disclaimer", JSON.False,
                    "marking_attestation", (!IsSet(extended?) ? unset : "I will disclose this is AI-generated")
                )
        }
        return retObj
    }
}
