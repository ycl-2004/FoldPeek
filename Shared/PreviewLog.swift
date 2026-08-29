import Foundation
import os

/// Records why a page image could not be produced.
///
/// A Quick Look extension cannot be attached to a debugger in the situation
/// that matters — running inside Quick Look, under the sandbox Quick Look
/// gives it — so the reasons a render failed are otherwise invisible. These
/// lines go to the local unified log and nowhere else: nothing is written to
/// disk by this file, nothing is sent anywhere, and no file contents or
/// filenames are recorded, only the stage and the error.
enum PreviewLog {
    private static let logger = Logger(
        subsystem: "com.yichenlin.foldpeek",
        category: "preview"
    )

    static func stage(_ name: StaticString, outcome: String) {
        logger.log("stage=\(name, privacy: .public) outcome=\(outcome, privacy: .public)")
    }

    static func failure(_ name: StaticString, _ error: Error) {
        let code = (error as NSError).code
        let domain = (error as NSError).domain
        logger.log(
            "stage=\(name, privacy: .public) failed domain=\(domain, privacy: .public) code=\(code)"
        )
    }
}
