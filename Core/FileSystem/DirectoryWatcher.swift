import Darwin
import Foundation

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    deinit {
        stop()
    }

    func watch(url: URL, onChange: @escaping () -> Void) {
        stop()

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: DispatchQueue.main
        )
        newSource.setEventHandler(handler: onChange)
        newSource.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source = newSource
        newSource.resume()
    }

    func stop() {
        guard let source else { return }
        self.source = nil
        fileDescriptor = -1
        source.cancel()
    }
}
