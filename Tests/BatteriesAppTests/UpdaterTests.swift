@testable import BatteriesApp
import XCTest

final class UpdaterTests: XCTestCase {
  func testVersionOrder() {
    XCTAssertTrue(Updater.isNewer("0.1.10", than: "0.1.9"), "numeric, not text, order")
    XCTAssertTrue(Updater.isNewer("v0.2.0", than: "0.1.3"))
    XCTAssertFalse(Updater.isNewer("0.1.3", than: "0.1.3"))
    XCTAssertFalse(Updater.isNewer("0.1.2", than: "0.1.3"))
    XCTAssertTrue(Updater.isNewer("1.0.0", than: "1.0.0-beta.1"), "a release beats its prerelease")
    XCTAssertFalse(Updater.isNewer("1.0.0-beta.1", than: "1.0.0"))
  }

  func testReleaseAsGitHubSendsIt() throws {
    let json = Data(#"""
    [{"tag_name": "v0.1.3", "body": "- notes", "draft": false,
      "assets": [{"name": "Batteries-0.1.3.zip", "size": 1,
                  "browser_download_url": "https://github.com/erel3/batteries/releases/download/v0.1.3/Batteries-0.1.3.zip"}]}]
    """#.utf8)
    let release = try XCTUnwrap(JSONDecoder().decode([GitHubRelease].self, from: json).first)
    XCTAssertEqual(release.version, "0.1.3")
    XCTAssertEqual(release.assets.first?.browserDownloadURL.lastPathComponent, "Batteries-0.1.3.zip")
  }
}
