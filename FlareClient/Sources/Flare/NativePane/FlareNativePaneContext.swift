import Foundation

public protocol FlareNativePaneContext: AnyObject {
    func getScreenName() -> String?
    func getAuthToken() -> String?
    func getBaseHttpUrl() -> String?
    func notifyAuthFailure()
    func setVariable(name: String, value: Any)
    func fireAction(actionName: String, payload: [String: Any]?)
}