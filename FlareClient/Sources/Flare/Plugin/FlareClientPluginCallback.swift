import Foundation

public protocol FlareClientPluginCallback: AnyObject {
    func onResult(_ result: FlareClientPluginResult)
}