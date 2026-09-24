import Foundation

let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let scriptURL = projectDirectory.appendingPathComponent("Scripts/run-both-simulators.sh")

guard FileManager.default.fileExists(atPath: scriptURL.path) else {
    FileHandle.standardError.write(Data("找不到启动脚本：\(scriptURL.path)\n".utf8))
    exit(EXIT_FAILURE)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = [scriptURL.path]
process.currentDirectoryURL = projectDirectory
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    FileHandle.standardError.write(Data("无法启动模拟器：\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
