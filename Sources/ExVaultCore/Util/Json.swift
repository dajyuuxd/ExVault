// Standard JSON encoder/decoder utilities strictly compatible with iOS 12.0+.

import Foundation

public enum Json {
    public static func encode<T: Encodable>(_ v: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(v)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    public static func object(_ dict: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }

    public static func toDictionary(_ data: Data) throws -> [String: Any] {
        guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected JSON object")
            )
        }
        return dict
    }
}
