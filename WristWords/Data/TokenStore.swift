protocol TokenStore {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

enum TokenStoreError: Error, Equatable {
    case keychain(Int32)
    case invalidData

    var message: String {
        switch self {
        case .keychain(let status):
            return "本机 Keychain 操作失败（\(status)）。没有改用明文文件存储；仍可输入凭证后仅在本次运行中 Test Connection。"
        case .invalidData:
            return "Keychain 中的凭证数据无效，请删除后重新粘贴。"
        }
    }
}
