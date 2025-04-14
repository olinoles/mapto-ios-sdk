// Sources/MyMapboxWrapper/Networking/MapDataLoader.swift

import Foundation
import Combine

@MainActor
class MapDataLoader: ObservableObject {

    enum LoadingState {
        case idle
        case loading
        case success(MapFile)
        case failed(Error)
    }

    @Published private(set) var state: LoadingState = .idle

    private var dataTask: URLSessionDataTask?

    /// Loads the map configuration JSON from the specified URL.
    /// - Parameter url: The URL of the map JSON file.
    func loadMapFile(from url: URL) {
        switch state {
        case .idle, .failed:
            break
        default:
            print("MapDataLoader: Already loading or successfully loaded.")
            return
        }

        state = .loading
        dataTask?.cancel()

        dataTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    if (error as NSError).code == NSURLErrorCancelled {
                        print("MapDataLoader: Data task cancelled.")
                        return
                    }
                    print("MapDataLoader: Network error - \(error.localizedDescription)")
                    self.state = .failed(error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let error = NSError(
                        domain: "HTTPError",
                        code: statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]
                    )
                    print("MapDataLoader: HTTP error - Status code \(statusCode)")
                    self.state = .failed(error)
                    return
                }

                guard let data = data else {
                    let error = NSError(
                        domain: "DataError",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No data received."]
                    )
                    print("MapDataLoader: No data received.")
                    self.state = .failed(error)
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let mapFile = try decoder.decode(MapFile.self, from: data)
                    print("MapDataLoader: Successfully decoded MapFile.")
                    self.state = .success(mapFile)
                } catch {
                    print("MapDataLoader: Decoding error - \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        print("MapDataLoader: Decoding error details - \(decodingError)")
                    }
                    self.state = .failed(error)
                }
            }
        }

        dataTask?.resume()
    }

    func cancel() {
        dataTask?.cancel()
    }
}
