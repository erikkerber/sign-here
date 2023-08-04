//
//  ListDevicesResponse.swift
//  Models
//
//  Created by Maxwell Elliott on 04/04/23.
//

import Foundation

internal struct ListProfileIDsResponse: Codable {
    internal struct Profile: Codable {
        internal struct Attributes: Codable {
            var name: String
            var platform: String
            var profileContent: String
            var uuid: String
            var createdDate: Date
            var profileState: String
            var profileType: String
            var expirationDate: Date
        }

        var id: String
        var type: String
        var attributes: Attributes
    }

    internal struct ListProfilesPagedDocumentLinks: Codable {
        var next: String?
        var `self`: String
    }

    var data: [Profile]
    var links: ListProfilesPagedDocumentLinks
}
