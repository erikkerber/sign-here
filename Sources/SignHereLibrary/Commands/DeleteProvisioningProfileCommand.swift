//
//  DeleteProvisioningProfileCommand.swift
//  Commands
//
//  Created by Maxwell Elliott on 04/24/23.
//

import ArgumentParser
import CoreLibrary
import Foundation
import PathKit

internal struct DeleteProvisioningProfileCommand: ParsableCommand {

    internal static var configuration: CommandConfiguration =
        .init(commandName: "delete-provisioning-profile",
              abstract: "Use this command to delete a provisioning profile using its iTunes Connect API ID",
              discussion: """
              This command can be used in conjunction with the `create-provisioning-profile` command to create and delete provisioning profiles.
              """)

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundleIdentifier"
        case bundleIdentifierName = "bundleIdentifierName"
        case keyIdentifier = "keyIdentifier"
        case issuerID = "issuerID"
        case itunesConnectKeyPath = "itunesConnectKeyPath"
        case profileType = "profileType"
    }

    @Option(help: "The bundle identifier of the app for which you want to delete a provisioning profile for")
    internal var bundleIdentifier: String

    @Option(help: "The bundle identifier name for the desired bundle identifier, this is optional but if it is not set the logic will select the first bundle id it finds that matches `--bundle-identifier`")
    internal var bundleIdentifierName: String?

    @Option(help: "The key identifier of the private key (https://developer.apple.com/documentation/appstoreconnectapi/generating_tokens_for_api_requests)")
    internal var keyIdentifier: String

    @Option(help: "The issuer id of the private key (https://developer.apple.com/documentation/appstoreconnectapi/generating_tokens_for_api_requests)")
    internal var issuerID: String

    @Option(help: "The path to the private key (https://developer.apple.com/documentation/appstoreconnectapi/generating_tokens_for_api_requests)")
    internal var itunesConnectKeyPath: String

    @Option(help: "The profile type which you wish to delete (https://developer.apple.com/documentation/appstoreconnectapi/profile/attributes)")
    internal var profileType: String

    private let files: Files
    private let jsonWebTokenService: JSONWebTokenService
    private let iTunesConnectService: iTunesConnectService

    internal init() {
        let filesImp: Files = FilesImp()
        files = filesImp
        jsonWebTokenService = JSONWebTokenServiceImp(clock: ClockImp())
        iTunesConnectService = iTunesConnectServiceImp(
            network: NetworkImp(),
            files: filesImp,
            shell: ShellImp(),
            clock: ClockImp()
        )
    }

    internal init(
        files: Files,
        jsonWebTokenService: JSONWebTokenService,
        iTunesConnectService: iTunesConnectService,
        bundleIdentifier: String,   
        keyIdentifier: String,
        issuerID: String,
        itunesConnectKeyPath: String,
        profileType: String,
        bundleIdentifierName: String?
    ) {
        self.files = files
        self.jsonWebTokenService = jsonWebTokenService
        self.iTunesConnectService = iTunesConnectService
        self.bundleIdentifier = bundleIdentifier
        self.keyIdentifier = keyIdentifier
        self.issuerID = issuerID
        self.itunesConnectKeyPath = itunesConnectKeyPath
        self.profileType = profileType
        self.bundleIdentifierName = bundleIdentifierName
    }

    internal init(from decoder: Decoder) throws {
        let filesImp: Files = FilesImp()
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            files: filesImp,
            jsonWebTokenService: JSONWebTokenServiceImp(clock: ClockImp()),
            iTunesConnectService: iTunesConnectServiceImp(
                network: NetworkImp(),
                files: filesImp,
                shell: ShellImp(),
                clock: ClockImp()
            ),
            bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier),
            keyIdentifier: try container.decode(String.self, forKey: .keyIdentifier),
            issuerID: try container.decode(String.self, forKey: .issuerID),
            itunesConnectKeyPath: try container.decode(String.self, forKey: .itunesConnectKeyPath),
            profileType: try container.decode(String.self, forKey: .profileType),
            bundleIdentifierName: try container.decodeIfPresent(String.self, forKey: .bundleIdentifierName)
        )
    }

    internal func run() throws {
        let jsonWebToken: String = try jsonWebTokenService.createToken(
            keyIdentifier: keyIdentifier,
            issuerID: issuerID,
            secretKey: try files.read(Path(itunesConnectKeyPath))
        )
        let profileIDs: Set<String> =
            try iTunesConnectService.fetchProfileIdsfromBundleId(
                jsonWebToken: jsonWebToken,  
                id: try iTunesConnectService.determineBundleIdITCId(
                        jsonWebToken: jsonWebToken,
                        bundleIdentifier: bundleIdentifier,
                        bundleIdentifierName: bundleIdentifierName
                    ),
                profileType: profileType
            )
        for profile in profileIDs {
            try iTunesConnectService.deleteProvisioningProfile(
                jsonWebToken: jsonWebToken,
                id: profile        
            )
        }
    }
}
