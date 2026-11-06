// Vault storage statistics endpoint.

import Foundation

public enum StatsApi: ApiModule {
    private struct StatsResponse: Codable {
        let fileCount: Int64
        let folderCount: Int64
        let totalBytes: Int64
        let storedBytes: Int64
        let trashBytes: Int64
        let ratio: Double
        let diskFree: Int64
        let diskTotal: Int64
    }

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // GET /api/stats
        r.add("GET", "/api/stats", auth: true) { _ in
            let stats = try ctx.store.stats()
            let free = ctx.blobs.diskFree()
            let total = ctx.blobs.diskTotal()
            let ratio: Double
            if stats.totalBytes > 0 {
                ratio = Double(stats.storedBytes) / Double(stats.totalBytes)
            } else {
                ratio = 1.0
            }

            let response = StatsResponse(
                fileCount: stats.fileCount,
                folderCount: stats.folderCount,
                totalBytes: stats.totalBytes,
                storedBytes: stats.storedBytes,
                trashBytes: stats.trashBytes,
                ratio: ratio,
                diskFree: free,
                diskTotal: total
            )
            return HttpResponse.json(response)
        }
    }
}
