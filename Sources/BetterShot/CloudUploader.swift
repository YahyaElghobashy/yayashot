//
//  CloudUploader.swift
//  YayaShot (sealed build)
//
//  Upstream BetterShot uploaded captures to a Cloudflare R2 bucket and copied a
//  public share link. YayaShot removes that pipeline entirely: the R2 uploader,
//  the credential store, the share manifest and the Sharing settings tab are
//  deleted. This stub keeps the editors' call sites compiling while making
//  cloud sharing permanently unavailable, so every cloud "Share" entry point
//  stays hidden. Sharing a file goes through LocalShareSheet instead.
//

import Foundation

struct CloudUploadResult: Sendable {
    let id: String
    let url: String
    let filename: String
    let size: Int
}

struct CloudSharingRemoved: LocalizedError {
    var errorDescription: String? {
        "Cloud sharing is not part of YayaShot. Use Share to send the file with the macOS share sheet."
    }
}

@MainActor
@Observable
final class CloudUploader {
    static let shared = CloudUploader()

    private init() {}

    /// Always false: there is no cloud destination in this build.
    var canShare: Bool { false }

    var uploadProgress: [UUID: Double] { [:] }

    func upload(itemID: UUID, fileURL: URL, named name: String, title: String? = nil) async throws -> CloudUploadResult {
        throw CloudSharingRemoved()
    }

    func cancelUpload(for itemID: UUID) {}
}
