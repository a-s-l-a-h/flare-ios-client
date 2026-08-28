import Foundation

public struct FlareEnvelope {
    public var screen: String = ""
    public var layout: [String: Any]?
    public var state: [String: Any]?
    public var variables: [VariableDef] = []
    public var scaffold: [String]?

    public struct VariableDef {
        public let name: String
        public let type: String
        public let value: Any?
        public let exported: Bool
    }

    public static func fromInit(_ json: [String: Any]) -> FlareEnvelope {
        var env = FlareEnvelope()
        env.screen = json["screen"] as? String ?? ""

        if let rawLayout = json["layout"] as? [String: Any] {
            if rawLayout["card"] != nil {
                env.layout = rawLayout
            } else {
                env.layout = [
                    "log_id": "flare_\(env.screen)",
                    "card": rawLayout
                ]
            }
        }

        env.state = json["state"] as? [String: Any]
        if let varsArray = json["variables"] as? [[String: Any]] {
            env.variables = varsArray.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                return VariableDef(
                    name: name,
                    type: dict["type"] as? String ?? "string",
                    value: dict["value"],
                    exported: dict["exported"] as? Bool ?? false
                )
            }
        }

        if let scaffoldArr = json["scaffold"] as? [String] {
            env.scaffold = scaffoldArr
        }

        return env
    }

    public static func fromLayoutUpdate(_ json: [String: Any]) -> FlareEnvelope {
        return fromInit(json)
    }
}