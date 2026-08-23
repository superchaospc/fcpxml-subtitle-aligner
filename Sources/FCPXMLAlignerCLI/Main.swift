import Darwin
import Foundation

@main
struct FCPXMLAlignerMain {
    static func main() {
        let result = CLIApplication().run(arguments: Array(CommandLine.arguments.dropFirst()))
        FileHandle.standardOutput.write(Data(result.stdout.utf8))
        FileHandle.standardError.write(Data(result.stderr.utf8))
        exit(result.exitCode)
    }
}
