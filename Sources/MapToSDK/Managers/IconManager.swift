// Sources/MyMapboxWrapper/Managers/IconManager.swift

import UIKit
import MapboxMaps
import Combine

@MainActor
class IconManager {
    private var imageCache = NSCache<NSString, UIImage>()
    private var pendingTasks = [String: Task<UIImage?, Error>]()

    private let cdnBaseURL: URL

    init(cdnBaseURL: URL) {
        self.cdnBaseURL = cdnBaseURL
        print("IconManager initialized with base URL: \(cdnBaseURL)")
    }

    /// Loads a set of icons by name, downloads if necessary, and adds them to the map style.
    /// - Parameters:
    ///   - iconNames: A set of unique image names (e.g., "icon_file.png").
    ///   - map: The MapboxMap instance to add images to.
    /// - Returns: A dictionary mapping icon names to loaded UIImages.
    /// - Throws: An error if any icon fails to load definitively (e.g., network error after retries).
    func loadAndAddIcons(names iconNames: Set<String>, to map: MapboxMap) async throws -> [String: UIImage] {
        var loadedImages: [String: UIImage] = [:]
        var tasks: [String: Task<UIImage?, Error>] = [:]

        for name in iconNames {
            if map.style.imageExists(withId: name) {
                 print("Icon '\(name)' already exists in map style.")
                 if let cachedImage = imageCache.object(forKey: name as NSString) {
                     loadedImages[name] = cachedImage
                 }
                 continue
            }

            if let cachedImage = imageCache.object(forKey: name as NSString) {
                print("Icon '\(name)' found in cache.")
                if !map.style.imageExists(withId: name) {
                    try map.style.addImage(cachedImage, id: name, sdf: false, stretchX: [], stretchY: [], content: nil)
                    print("Added cached icon '\(name)' to map style.")
                }
                loadedImages[name] = cachedImage
                continue
            }

            if let existingTask = pendingTasks[name] {
                print("Icon '\(name)' download already pending.")
                tasks[name] = existingTask
                continue
            }

            print("Initiating download for icon '\(name)'...")
            let iconURL = cdnBaseURL.appendingPathComponent("icon").appendingPathComponent(name)
            let downloadTask = Task { () -> UIImage? in
                do {
                    let (data, response) = try await URLSession.shared.data(from: iconURL)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw NSError(domain: "NetworkError", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download icon \(name)"])
                    }
                    guard let image = UIImage(data: data) else {
                        throw NSError(domain: "DataError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image data for icon \(name)"])
                    }
                    return image
                } catch {
                    print("Error downloading icon '\(name)' from \(iconURL): \(error)")
                    self.pendingTasks.removeValue(forKey: name)
                    throw error
                }
            }

            pendingTasks[name] = downloadTask
            tasks[name] = downloadTask
        }

        var downloadErrors: [Error] = []
        for (name, task) in tasks {
            do {
                if let image = try await task.value {
                    print("Successfully downloaded icon '\(name)'.")
                    self.imageCache.setObject(image, forKey: name as NSString)
                    try map.style.addImage(image, id: name, sdf: false, stretchX: [], stretchY: [], content: nil)
                    print("Added downloaded icon '\(name)' to map style.")
                    loadedImages[name] = image
                } else {
                     print("Warning: Download task for icon '\(name)' completed without image or error.")
                }
            } catch {
                print("Failed to complete download or add icon '\(name)': \(error)")
                downloadErrors.append(error)
            }
            self.pendingTasks.removeValue(forKey: name)
        }

        // Check if any essential icons failed
        if !downloadErrors.isEmpty {
            // TODO handle throwing errors? lets throw the first for now.
            throw downloadErrors.first!
        }

        print("Icon loading process completed.")
        return loadedImages
    }
}
