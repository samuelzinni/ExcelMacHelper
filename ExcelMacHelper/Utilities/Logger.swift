import Foundation
import os

/// Centralized logging for ExcelMacHelper
enum Logger {
    private static let logger = os.Logger(subsystem: Constants.bundleIdentifier, category: "ExcelMacHelper")

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("[ExcelMacHelper] \(message)")
        #endif
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        #if DEBUG
        print("[ExcelMacHelper ERROR] \(message)")
        #endif
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
        print("[ExcelMacHelper DEBUG] \(message)")
        #endif
    }
}
