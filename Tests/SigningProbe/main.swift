import Foundation
import Security

func require(_ status: OSStatus) {
    guard status == errSecSuccess else {
        fputs("Signing keychain probe failed (OSStatus \(status)).\n", stderr)
        exit(1)
    }
}

require(SecKeychainSetUserInteractionAllowed(false))
let path = CommandLine.arguments[1]
let seed = CommandLine.arguments[2] == "seed"
let password = "isolated-test-keychain-only"
var keychain: SecKeychain?
password.withCString { bytes in
    if seed {
        require(SecKeychainCreate(path, UInt32(password.utf8.count), bytes, false, nil, &keychain))
    } else {
        require(SecKeychainOpen(path, &keychain))
    }
    require(SecKeychainUnlock(keychain, UInt32(password.utf8.count), bytes, true))
}
let service = "ManaBar signing continuity test"
let account = "test-only"
let value = "synthetic-no-account-data"
if seed {
    service.withCString { serviceBytes in
        account.withCString { accountBytes in
            value.withCString { valueBytes in
                require(SecKeychainAddGenericPassword(keychain, UInt32(service.utf8.count), serviceBytes,
                    UInt32(account.utf8.count), accountBytes, UInt32(value.utf8.count), valueBytes, nil))
            }
        }
    }
}
var length: UInt32 = 0
var result: UnsafeMutableRawPointer?
service.withCString { serviceBytes in
    account.withCString { accountBytes in
        require(SecKeychainFindGenericPassword(keychain, UInt32(service.utf8.count), serviceBytes,
            UInt32(account.utf8.count), accountBytes, &length, &result, nil))
    }
}
assert(Data(bytes: result!, count: Int(length)) == Data(value.utf8))
SecKeychainItemFreeContent(nil, result)
#if SECOND_BUILD
print("Second signed build read the original ACL-protected test item without UI.")
#else
print("First signed build created and read its ACL-protected test item without UI.")
#endif
