import Foundation
import XCTest
@testable import FCPXMLAlignerCore

func fixtureURL(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
    let url = Bundle.module.url(forResource: name, withExtension: "fcpxmld", subdirectory: "Fixtures")
    return try XCTUnwrap(url, "Missing fixture bundle: \(name).fcpxmld", file: file, line: line)
}

func currentFixtureDocument() throws -> FCPXMLDocument {
    try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fixtureURL("sample-current")))
}

func templateFixtureDocument() throws -> FCPXMLDocument {
    try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fixtureURL("sample-template")))
}

func goldFixtureDocument() throws -> FCPXMLDocument {
    try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fixtureURL("sample-gold")))
}
