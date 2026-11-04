import XCTest
@testable import MegaplanHepler

final class ParticipantDirectoryTests: XCTestCase {
    func testNotificationJSONSeedsOwnerInsideCommentSubject() throws {
        let json = Data("""
        {"data":[{"sender":{"id":"1","name":"Иванов Иван"},"subject":{"contentType":"Comment","subject":{"contentType":"Task","owner":{"id":"9","name":"Петров Пётр"}}}}]}
        """.utf8)
        let seeds = ParticipantDirectory.seeds(fromNotificationJSON: json)
        XCTAssertTrue(seeds.contains { $0.id == "1" && $0.name == "Иванов Иван" })
        XCTAssertTrue(seeds.contains { $0.id == "9" && $0.name == "Петров Пётр" })
    }

    func testFallbackAvatarPathsStayTheOnesTheRowUsesToday() {
        // URL.path отбрасывает query, поэтому size=64x64 проверяется вместе с path.
        let paths = ParticipantDirectory.fallbackAvatarPaths(userId: "42").map { url in
            guard let query = url.query, !query.isEmpty else { return url.path }
            return "\(url.path)?\(query)"
        }
        XCTAssertEqual(paths, [
            "/api/v3/user/42/avatar/thumbnail?size=64x64",
            "/api/v3/user/42/avatar",
            "/api/v3/employee/42/avatar/thumbnail?size=64x64",
            "/BumsCommonBundle/images/personal/noavatar_64x64.jpg"
        ])
    }
}
