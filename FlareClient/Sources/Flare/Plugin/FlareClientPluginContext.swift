import Foundation

public protocol FlareClientPluginContext: AnyObject {
    func getAuthToken() -> String?
    func getBaseHttpUrl() -> String?
    func getScreenName() -> String?
    func notifyAuthFailure()
}