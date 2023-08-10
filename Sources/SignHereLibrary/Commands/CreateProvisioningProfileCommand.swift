//
//  CreateProvisioningProfileCommand.swift
//  Commands
//
//  Created by Maxwell Elliott on 04/24/23.
//

import ArgumentParser
import CoreLibrary
import Foundation
import PathKit

internal struct CreateProvisioningProfileCommand: ParsableCommand {

    internal static var configuration: CommandConfiguration =
        .init(commandName: "create-provisioning-profile",
              abstract: "Use this command to create a ready to use provisioning profile.",
              discussion: """
              Use this command to create and save a mobile provisioning profile to a specified location. This command
              takes care of all necessary signing work and iTunes Connect API calls to get a ready to use
              mobile provisioning profile.

              The output of this command is the iTunes Connect API ID of the created provisioning profile. This can
              be used with the `delete-provisioning-profile` command to delete it if desired.
              """)

    internal enum Error: Swift.Error, CustomStringConvertible {
        case unableToCreatePrivateKeyAndCSR(output: ShellOutput)
        case unableToCreateP12Identity(output: ShellOutput)
        case unableToBase64DecodeCertificate(displayName: String)
        case unableToCreatePEM(output: ShellOutput)
        case unableToBase64DecodeProfile(name: String)
        case unableToCreateCSR(output: ShellOutput)

        var description: String {
            switch self {
                case let .unableToCreatePrivateKeyAndCSR(output: output):
                    return """
                    [CreateProvisioningProfileCommand] Unable to create private key and CSR
                    - Output: \(output.outputString)
                    - Error: \(output.errorString)
                    """
                case let .unableToCreateP12Identity(output: output):
                    return """
                    [CreateProvisioningProfileCommand] Unable to create P12 identity
                    - Output: \(output.outputString)
                    - Error: \(output.errorString)
                    """
                case let .unableToBase64DecodeCertificate(displayName: displayName):
                    return """
                    [CreateProvisioningProfileCommand] Unable to base 64 decode certificate
                    - Certificate display name: \(displayName)
                    """
                case let .unableToCreatePEM(output: output):
                    return """
                    [CreateProvisioningProfileCommand] Unable to create PEM
                    - Output: \(output.outputString)
                    - Error: \(output.errorString)
                    """
                case let .unableToBase64DecodeProfile(name: name):
                    return """
                    [CreateProvisioningProfileCommand] Unable to base 64 decode profile
                    - Profile name: \(name)
                    """
                case let .unableToCreateCSR(output: output):
                    return """
                    [CreateProvisioningProfileCommand] Unable to create certificate signing request
                    - Output: \(output.outputString)
                    - Error: \(output.errorString)
                    """
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case keyIdentifier = "keyIdentifier"
        case issuerID = "issuerID"
        case privateKeyPath = "privateKeyPath"
        case itunesConnectKeyPath = "itunesConnectKeyPath"
        case bundleIdentifier = "bundleIdentifier"
        case bundleIdentifierName = "bundleIdentifierName"
        case profileType = "profileType"
        case certificateType = "certificateType"
        case outputPath = "outputPath"
        case opensslPath = "opensslPath"
        case certificateSigningRequestSubject = "certificateSigningRequestSubject"
    }

    @Option(help: "The key identifier of the private key (https://developer.apple.com/documentation/appstoreconnectapi/generating_tokens_for_api_requests)")
    internal var keyIdentifier: String

    @Option(help: "The issuer id of the private key (https://developer.apple.com/documentation/appstoreconnectapi/generating_tokens_for_api_requests)")
    internal var issuerID: String

    @Option(help: "The path to a private key to use for generating PEM and P12 files. This key will be attached to any generated certificates or profiles")
    internal var privateKeyPath: String

    @Option(help: "The path to the private key (https://developer.apple.com/documentation/appstoreconnectapi/generating_tokens_for_api_requests)")
    internal var itunesConnectKeyPath: String

    @Option(help: "The bundle identifier of the app for which you want to generate a provisioning profile for")
    internal var bundleIdentifier: String

    @Option(help: "The bundle identifier name for the desired bundle identifier, this is optional but if it is not set the logic will select the first bundle id it finds that matches `--bundle-identifier`")
    internal var bundleIdentifierName: String?

    @Option(help: "The profile type which you wish to create (https://developer.apple.com/documentation/appstoreconnectapi/profilecreaterequest/data/attributes)")
    internal var profileType: String

    @Option(help: "The certificate type which you wish to create (https://developer.apple.com/documentation/appstoreconnectapi/certificatetype)")
    internal var certificateType: String

    @Option(help: "Where to save the created provisioning profile")
    internal var outputPath: String

    @Option(help: "Path to the openssl executable, this is used to generate CSR signing artifacts that are required when creating certificates")
    internal var opensslPath: String

    @Option(help: """
    Subject for the Certificate Signing Request when creating certificates.

    OpenSSL documentation for this flag (https://www.openssl.org/docs/manmaster/man1/openssl-req.html):

    Sets subject name for new request or supersedes the subject name when processing a certificate request.

    The arg must be formatted as '/type0=value0/type1=value1/type2=....'. Special characters may be escaped by '\\' (backslash), whitespace is retained. Empty values are permitted, but the corresponding type will not be included in the request. Giving a single '/' will lead to an empty sequence of RDNs (a NULL-DN). Multi-valued RDNs can be formed by placing a '+' character instead of a '/' between the AttributeValueAssertions (AVAs) that specify the members of the set. Example:

    /DC=org/DC=OpenSSL/DC=users/UID=123456+CN=JohnDoe
    """)
    internal var certificateSigningRequestSubject: String

    private let files: Files
    private let log: Log
    private let shell: Shell
    private let jsonWebTokenService: JSONWebTokenService
    private let uuid: CoreLibrary.UUID
    private let iTunesConnectService: iTunesConnectService

    internal init() {
        let filesImp: Files = FilesImp()
        let clockImp: Clock = ClockImp()
        let shellImp: Shell = ShellImp()
        files = filesImp
        log = LogImp()
        jsonWebTokenService = JSONWebTokenServiceImp(clock: clockImp)
        shell = shellImp
        uuid = UUIDImp()
        iTunesConnectService = iTunesConnectServiceImp(
            network: NetworkImp(),
            files: filesImp,
            shell: shellImp,
            clock: clockImp
        )
    }

    internal init(
        files: Files,
        log: Log,
        jsonWebTokenService: JSONWebTokenService,
        shell: Shell,
        uuid: CoreLibrary.UUID,
        iTunesConnectService: iTunesConnectService,
        keyIdentifier: String,
        issuerID: String,
        privateKeyPath: String,
        itunesConnectKeyPath: String,
        bundleIdentifier: String,
        profileType: String,
        certificateType: String,
        outputPath: String,
        opensslPath: String,
        certificateSigningRequestSubject: String,
        bundleIdentifierName: String?
    ) {
        self.files = files
        self.log = log
        self.jsonWebTokenService = jsonWebTokenService
        self.shell = shell
        self.uuid = uuid
        self.iTunesConnectService = iTunesConnectService
        self.keyIdentifier = keyIdentifier
        self.issuerID = issuerID
        self.privateKeyPath = privateKeyPath
        self.itunesConnectKeyPath = itunesConnectKeyPath
        self.bundleIdentifier = bundleIdentifier
        self.profileType = profileType
        self.certificateType = certificateType
        self.outputPath = outputPath
        self.opensslPath = opensslPath
        self.certificateSigningRequestSubject = certificateSigningRequestSubject
        self.bundleIdentifierName = bundleIdentifierName
    }

    internal init(from decoder: Decoder) throws {
        let filesImp: Files = FilesImp()
        let clockImp: Clock = ClockImp()
        let shellImp: Shell = ShellImp()
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            files: filesImp,
            log: LogImp(),
            jsonWebTokenService: JSONWebTokenServiceImp(clock: clockImp),
            shell: shellImp,
            uuid: UUIDImp(),
            iTunesConnectService: iTunesConnectServiceImp(
                network: NetworkImp(),
                files: filesImp,
                shell: shellImp,
                clock: clockImp
            ),
            keyIdentifier: try container.decode(String.self, forKey: .keyIdentifier),
            issuerID: try container.decode(String.self, forKey: .issuerID),
            privateKeyPath: try container.decode(String.self, forKey: .privateKeyPath),
            itunesConnectKeyPath: try container.decode(String.self, forKey: .itunesConnectKeyPath),
            bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier),
            profileType: try container.decode(String.self, forKey: .profileType),
            certificateType: try container.decode(String.self, forKey: .certificateType),
            outputPath: try container.decode(String.self, forKey: .outputPath),
            opensslPath: try container.decode(String.self, forKey: .opensslPath),
            certificateSigningRequestSubject: try container.decode(String.self, forKey: .certificateSigningRequestSubject),
            bundleIdentifierName: try container.decodeIfPresent(String.self, forKey: .bundleIdentifierName)
        )
    }

    internal func run() throws {
        let privateKey: Path = .init(privateKeyPath)
        let csr: Path = try createCSR(privateKey: privateKey)
        let jsonWebToken: String = try jsonWebTokenService.createToken(
            keyIdentifier: keyIdentifier,
            issuerID: issuerID,
            secretKey: try files.read(Path(itunesConnectKeyPath))
        )
        let fileManager = FileManager.default
        do{
            if !fileManager.fileExists(atPath: outputPath) {
                try fileManager.createDirectory(atPath: outputPath, withIntermediateDirectories: true, attributes: nil)
        }
        } catch {
            print("Error: \(error)")
        }

        let tuple: (cer: Path, certificateId: String) = try fetchOrCreateCertificate(jsonWebToken: jsonWebToken, csr: csr, outputPath: outputPath)
        let certificateId: String = tuple.certificateId
        let deviceIDs: Set<String> = try iTunesConnectService.fetchITCDeviceIDs(jsonWebToken: jsonWebToken)
        let profileResponse: CreateProfileResponse = try iTunesConnectService.createProfile(
            jsonWebToken: jsonWebToken,
            bundleId: try iTunesConnectService.determineBundleIdITCId(
                jsonWebToken: jsonWebToken,
                bundleIdentifier: bundleIdentifier,
                bundleIdentifierName: bundleIdentifierName
            ),
            certificateId: certificateId,
            deviceIDs: deviceIDs,
            profileType: profileType
        )
        guard let profileData: Data = .init(base64Encoded: profileResponse.data.attributes.profileContent)
        else {
            throw Error.unableToBase64DecodeProfile(name: profileResponse.data.attributes.name)
        }

    //    let fileManager = FileManager.default
        let filePath = "\(outputPath)/\(profileResponse.data.attributes.uuid).mobileprovision"
        print(filePath)
        // do{
        //     if !fileManager.fileExists(atPath: outputPath) {
        //         try fileManager.createDirectory(atPath: outputPath, withIntermediateDirectories: true, attributes: nil)
        // }
        try files.write(profileData, to: .init(filePath))
        // } catch {
        //     print("Error: \(error)")
        // }
        // let newPath: String = outputPath + profileResponse.data.attributes.uuid + ".mobileprovision" 
        // print(newPath)
        // try files.write(profileData, to: .init(newPath))
        log.append("cer: " + certificateId)
        log.append("uuid: " +  profileResponse.data.attributes.uuid)
        log.append("profileContent: " + profileResponse.data.attributes.profileContent)
        
    }

    private func createCSR(privateKey: Path) throws -> Path {
        let csr: Path = (try files.uniqueTemporaryPath()) + "certificate_request.csr"
        let output: ShellOutput = shell.execute([
            opensslPath,
            "req",
            "-new",
            "-key",
            privateKey.string,
            "-out",
            csr.string,
            "-subj",
            certificateSigningRequestSubject
        ])
        guard output.isSuccessful else {
            throw Error.unableToCreateCSR(output: output)
        }
        return csr
    }

    private func fetchOrCreateCertificate(
        jsonWebToken: String,
        csr: Path,
        outputPath: String
    ) throws -> (cer: Path, certificateId: String) {
        let cer: Path
        let certificateId: String
        if let fetchedActiveCertificate: DownloadCertificateResponse.DownloadCertificateResponseData = try iTunesConnectService.fetchActiveCertificates(
            jsonWebToken: jsonWebToken,
            opensslPath: opensslPath,
            privateKeyPath: privateKeyPath,
            certificateType: certificateType
        ).first {
            guard let data: Data = .init(base64Encoded: fetchedActiveCertificate.attributes.certificateContent)
            else {
                throw Error.unableToBase64DecodeCertificate(displayName: fetchedActiveCertificate.attributes.displayName)
            }
            cer = try files.uniqueTemporaryPath() + "\(fetchedActiveCertificate.id).cer"
            certificateId = fetchedActiveCertificate.id
            let filePath = "\(outputPath)/\(certificateId).cer"
            try files.write(data, to: .init(filePath))
        } else {
            let createCertificateResponse: CreateCertificateResponse = try iTunesConnectService.createCertificate(
                jsonWebToken: jsonWebToken,
                csr: csr,
                certificateType: certificateType
            )
            guard let cerData: Data = .init(base64Encoded: createCertificateResponse.data.attributes.certificateContent)
            else {
                throw Error.unableToBase64DecodeCertificate(displayName: createCertificateResponse.data.attributes.displayName)
            }
            cer = try files.uniqueTemporaryPath() + "\(createCertificateResponse.data.id).cer"
            try files.write(cerData, to: cer)
            certificateId = createCertificateResponse.data.id
            let filePath = "\(outputPath)/\(certificateId).cer"
            try files.write(cerData, to: .init(filePath))
        }
        return (cer: cer, certificateId: certificateId)
    }

    private func createPEM(cer: Path) throws -> Path {
        let pem: Path = try files.uniqueTemporaryPath() + "certificate.pem"
        let output: ShellOutput = shell.execute([
            opensslPath,
            "x509",
            "-inform",
            "DER",
            "-outform",
            "PEM",
            "-in",
            cer.string,
            "-out",
            pem.string,
        ])
        guard output.isSuccessful
        else {
            throw Error.unableToCreatePEM(output: output)
        }
        return pem
    }

    private func createP12Identity(pem: Path, privateKey: Path, identityPassword: String) throws -> Path {
        let p12Output: Path = try files.uniqueTemporaryPath() + "identity.p12"
        let output: ShellOutput = shell.execute([
            opensslPath,
            "pkcs12",
            "-export",
            "-inkey",
            privateKey.string,
            "-in",
            pem.string,
            "-passout",
            "pass:\(identityPassword)",
            "-out",
            p12Output.string
        ])
        guard output.isSuccessful
        else {
            throw Error.unableToCreateP12Identity(output: output)
        }
        return p12Output
    }

 }
