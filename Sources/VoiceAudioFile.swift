import Foundation
import Darwin

enum VoiceAudioFile {
    static let limit=25_000_000
    static func read(_ url:URL)throws->Data {
        let formats=["mp3","mp4","mpeg","mpga","m4a","wav","webm"]
        guard url.isFileURL,formats.contains(url.pathExtension.lowercased()) else{throw VoiceServiceError(message:T.s("Choose a supported local audio/video file.","Elige un archivo local de audio/vídeo compatible."))}
        // Open once, reject links/devices/FIFOs, inspect the opened file and cap the actual bytes read.
        // A changing file or misleading path metadata cannot bypass the provider limit or block on a pipe.
        let fd=Darwin.open(url.path,O_RDONLY|O_CLOEXEC|O_NONBLOCK|O_NOFOLLOW)
        guard fd>=0 else{throw VoiceServiceError(message:T.s("Cannot open this file. Choose the original audio file instead of a link.","No se puede abrir este archivo. Elige el audio original en vez de un enlace."))}
        defer{Darwin.close(fd)}
        var info=stat()
        guard fstat(fd,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_size>0,info.st_size<=limit else{throw VoiceServiceError(message:T.s("Choose a regular audio/video file up to 25 MB.","Elige un archivo de audio/vídeo de hasta 25 MB."))}
        let file=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
        var data=Data()
        while data.count<=limit {
            let chunk=try file.read(upToCount:min(64*1024,limit+1-data.count)) ?? Data()
            if chunk.isEmpty{break}
            data.append(chunk)
        }
        guard !data.isEmpty,data.count<=limit else{throw VoiceServiceError(message:T.s("The file grew beyond 25 MB while reading. Nothing was uploaded.","El archivo superó 25 MB durante la lectura. No se ha subido nada."))}
        return data
    }
}
