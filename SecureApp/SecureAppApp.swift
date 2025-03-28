//
//  SecureAppApp.swift
//  SecureApp
//
//  Created by Abdulkerim Karaman on 27.03.2025.
//

import SwiftUI
import Security

@main
struct SecureAppApp: App {
    // Private key storage
    private var privateKey: SecKey?
    
    init() {
        // Try to create the private key when app initializes
        do {
            privateKey = try createPrivateKey()
            print("Private key created successfully")
            
            // Özel anahtardan genel anahtarı al
            if let privateKey = privateKey, 
               let publicKey = SecKeyCopyPublicKey(privateKey) {
                print("Public key obtained successfully")
                
                // Genel anahtarı X.509 formatında dışarı aktar
                var error: Unmanaged<CFError>?
                if let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? {
                    // X.509 formatında public key oluştur
                    let publicKeyX509 = createX509PublicKey(from: publicKeyData)
                    
                    print("\nPublic Key (X.509 Base64):")
                    print(publicKeyX509.base64EncodedString())
                    print("\nPublic Key (PEM format):")
                    print("-----BEGIN PUBLIC KEY-----")
                    print(publicKeyX509.base64EncodedString())
                    print("-----END PUBLIC KEY-----")
                    
                    // Örnek veri şifreleme ve çözme
                    do {
                        // Şifrelenecek örnek metin
                        let originalMessage = "Bu gizli bir mesajdır!"
                        print("\nOriginal message: \(originalMessage)")
                        
                        // Metni şifrele (genel anahtar ile)
                        let encryptedData = try encryptMessage(originalMessage, publicKey: publicKey)
                        print("Encrypted data (Base64): \(encryptedData.base64EncodedString())")
                        
                        // Şifrelenmiş veriyi çöz (özel anahtar ile)
                        let decryptedMessage = try decryptMessage(encryptedData, privateKey: privateKey)
                        print("Decrypted message: \(decryptedMessage)")
                        
                        // Orijinal mesaj ile çözülen mesajın karşılaştırılması
                        if originalMessage == decryptedMessage {
                            print("✅ Encryption/Decryption successful - Messages match!")
                        } else {
                            print("❌ Encryption/Decryption failed - Messages don't match")
                        }
                    } catch {
                        print("Encryption/Decryption error: \(error)")
                    }
                } else {
                    if let error = error {
                        print("Error exporting public key: \(error.takeRetainedValue())")
                    }
                }
            } else {
                print("Failed to get public key from private key")
            }
        } catch {
            print("Error creating private key: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    // Mesajı genel anahtar ile şifrele
    private func encryptMessage(_ message: String, publicKey: SecKey) throws -> Data {
        // String'i data'ya dönüştür
        guard let messageData = message.data(using: .utf8) else {
            throw NSError(domain: "Encryption", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to data"])
        }
        
        // Şifreleme algoritması ve seçeneklerini belirle
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorVariableIVX963SHA256AESGCM
        
        // Belirlenen algoritmanın bu anahtar ile kullanılabilir olduğunu kontrol et
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw NSError(domain: "Encryption", code: -2, userInfo: [NSLocalizedDescriptionKey: "Algorithm not supported for encryption"])
        }
        
        // Veriyi şifrele
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, messageData as CFData, &error) as Data? else {
            throw error?.takeRetainedValue() as Error? ?? NSError(domain: "Encryption", code: -3, userInfo: [NSLocalizedDescriptionKey: "Encryption failed"])
        }
        
        return encryptedData
    }
    
    // Şifrelenmiş veriyi özel anahtar ile çöz
    private func decryptMessage(_ encryptedData: Data, privateKey: SecKey) throws -> String {
        // Şifre çözme algoritması ve seçeneklerini belirle
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorVariableIVX963SHA256AESGCM
        
        // Belirlenen algoritmanın bu anahtar ile kullanılabilir olduğunu kontrol et
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            throw NSError(domain: "Decryption", code: -2, userInfo: [NSLocalizedDescriptionKey: "Algorithm not supported for decryption"])
        }
        
        // Veriyi çöz
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, algorithm, encryptedData as CFData, &error) as Data? else {
            throw error?.takeRetainedValue() as Error? ?? NSError(domain: "Decryption", code: -3, userInfo: [NSLocalizedDescriptionKey: "Decryption failed"])
        }
        
        // Data'yı String'e dönüştür
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(domain: "Decryption", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to convert decrypted data to string"])
        }
        
        return decryptedString
    }
    
    // Method to create a private key in the Secure Enclave
    private func createPrivateKey() throws -> SecKey {
        let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil)!
        
        let attributes: NSDictionary = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: "com.secureApp",
                kSecAttrAccessControl: access
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return privateKey
    }
    
    // X.509 formatında public key oluştur
    private func createX509PublicKey(from rawKeyData: Data) -> Data {
        // ASN.1 header for EC public key
        let header: [UInt8] = [
            0x30, 0x59, // SEQUENCE, length 89
            0x30, 0x13, // SEQUENCE, length 19
            0x06, 0x07, // OBJECT IDENTIFIER, length 7
            0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, // OID for prime256v1
            0x06, 0x08, // OBJECT IDENTIFIER, length 8
            0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, // OID for ECDSA with SHA-256
            0x03, 0x42, // BIT STRING, length 66
            0x00 // no padding bits
        ]
        
        var result = Data(header)
        result.append(rawKeyData)
        return result
    }
}
