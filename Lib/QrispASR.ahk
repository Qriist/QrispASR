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
            "optArr", optArr := []  ;for CLI construction
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
            ; "-c:a pcm_s24le",
            ; "-c:a pcm_s32le",
            '"' tempPath '"'
        ], " ")
        RunWait(cmd, this.crispDir)
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
}
