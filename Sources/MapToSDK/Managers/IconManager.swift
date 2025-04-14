// Sources/MyMapboxWrapper/Managers/IconManager.swift

import UIKit
import MapboxMaps
import Combine // Or use async/await

/// Manages downloading, caching, and adding icons (UIImages) to the Mapbox map style.
@MainActor // Ensure map interactions happen on the main thread
class IconManager {
    // Simple cache for downloaded images. Use NSCache for better memory management.
    private var imageCache = NSCache<NSString, UIImage>()
    private var pendingTasks = [String: Task<UIImage?, Error>]() // Track ongoing downloads

    // Base URL for constructing icon URLs. Should be configurable.
    private let cdnBaseURL: URL

    init(cdnBaseURL: URL) {
        // Ensure base URL ends with a slash if needed, or handle joining carefully
        self.cdnBaseURL = cdnBaseURL
        print("IconManager initialized with base URL: \(cdnBaseURL)")
    }

    /// Loads a set of icons by name, downloads if necessary, and adds them to the map style.
    /// - Parameters:
    ///   - iconNames: A set of unique icon names (e.g., "icon_file.png").
    ///   - map: The MapboxMap instance to add images to.
    /// - Returns: A dictionary mapping icon names to loaded UIImages.
    /// - Throws: An error if any icon fails to load definitively (e.g., network error after retries).
    func loadAndAddIcons(names iconNames: Set<String>, to map: MapboxMap) async throws -> [String: UIImage] {
        var loadedImages: [String: UIImage] = [:]
        var tasks: [String: Task<UIImage?, Error>] = [:]

        for name in iconNames {
            // 1. Check if already added to map style
            if map.style.imageExists(withId: name) {
                 print("Icon '\(name)' already exists in map style.")
                 // Optionally retrieve from cache if needed elsewhere, otherwise skip
                 if let cachedImage = imageCache.object(forKey: name as NSString) {
                     loadedImages[name] = cachedImage
                 } else {
                     // If it's in the style but not cache, we might not need the UIImage object itself now
                 }
                 continue
            }

            // 2. Check cache
            if let cachedImage = imageCache.object(forKey: name as NSString) {
                print("Icon '\(name)' found in cache.")
                // Add to map style if not already there (though previous check should cover this)
                if !map.style.imageExists(withId: name) {
                    try map.style.addImage(cachedImage, id: name, sdf: false, stretchX: [], stretchY: [], content: nil)
                    print("Added cached icon '\(name)' to map style.")
                }
                loadedImages[name] = cachedImage
                continue
            }

            // 3. Check for pending download task
            if let existingTask = pendingTasks[name] {
                print("Icon '\(name)' download already pending.")
                tasks[name] = existingTask // Add to the list of tasks to await
                continue
            }

            // 4. Initiate download
            print("Initiating download for icon '\(name)'...")
            let iconURL = cdnBaseURL.appendingPathComponent("icon").appendingPathComponent(name) // Adjust path as needed
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
                    // Remove from pending tasks on failure before throwing
                    self.pendingTasks.removeValue(forKey: name)
                    throw error // Re-throw the error
                }
            }

            pendingTasks[name] = downloadTask
            tasks[name] = downloadTask
        }

        // Await all necessary download tasks
        var downloadErrors: [Error] = []
        for (name, task) in tasks {
            do {
                if let image = try await task.value {
                    print("Successfully downloaded icon '\(name)'.")
                    // Add to cache and map style
                    self.imageCache.setObject(image, forKey: name as NSString)
                    // Ensure adding to style happens on main actor (already guaranteed by class annotation)
                    try map.style.addImage(image, id: name, sdf: false, stretchX: [], stretchY: [], content: nil)
                    print("Added downloaded icon '\(name)' to map style.")
                    loadedImages[name] = image
                } else {
                     // Should not happen if task throws on error, but handle defensively
                     print("Warning: Download task for icon '\(name)' completed without image or error.")
                }
            } catch {
                print("Failed to complete download or add icon '\(name)': \(error)")
                downloadErrors.append(error)
                // Don't add to loadedImages on failure
            }
            // Remove task from pending list once completed (success or failure)
            self.pendingTasks.removeValue(forKey: name)
        }

        // Check if any essential icons failed
        if !downloadErrors.isEmpty {
            // Decide on error handling: throw the first error, a combined error, or handle partially loaded state?
            // For now, let's throw the first error encountered.
            throw downloadErrors.first!
        }

        print("Icon loading process completed.")
        return loadedImages
    }
}
