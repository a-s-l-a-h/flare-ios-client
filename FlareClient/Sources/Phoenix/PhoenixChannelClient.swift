import Foundation

/// Full Phoenix Channels 2.0 (vsn=2.0.0) Client Implementation.
/// Designed for strict thread safety using a dedicated background serial queue ("dev.flareframework.socket").
public class PhoenixChannelClient {

    public typealias MessageCallback = (_ payload: [String: Any], _ ref: String?, _ joinRef: String?) -> Void
    public typealias ErrorCallback = (_ reason: String) -> Void
    public typealias OpenCallback = () -> Void
    public typealias CloseCallback = (_ code: Int, _ reason: String) -> Void
    public typealias PhoenixLogger = (_ tag: String, _ msg: String) -> Void

    public protocol MessageDecoder {
        func decode(text: String) throws -> String?
        func decode(data: Data) throws -> String?
    }

    public class DefaultMessageDecoder: MessageDecoder {
        public init() {}
        public func decode(text: String) throws -> String? { return text }
        public func decode(data: Data) throws -> String? { return String(data: data, encoding: .utf8) }
    }

    // MARK: - Exponential Backoff Timer
    public final class RetryTimer {
        public typealias Calc = (_ tries: Int) -> TimeInterval

        private let callback: () -> Void
        private let calc: Calc
        private let queue: DispatchQueue
        private var tries: Int = 0
        private var pendingItem: DispatchWorkItem?

        public init(queue: DispatchQueue, callback: @escaping () -> Void, calc: @escaping Calc) {
            self.queue = queue
            self.callback = callback
            self.calc = calc
        }

        public func reset() {
            tries = 0
            cancelPending()
        }

        public func scheduleTimeout() {
            cancelPending()
            let delay = calc(tries + 1)
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.tries += 1
                self.pendingItem = nil
                self.callback()
            }
            pendingItem = item
            queue.asyncAfter(deadline: .now() + delay, execute: item)
        }

        private func cancelPending() {
            pendingItem?.cancel()
            pendingItem = nil
        }
    }

    // MARK: - Protocol Constants
    public struct ChannelEvent {
        public static let close = "phx_close"
        public static let error = "phx_error"
        public static let join  = "phx_join"
        public static let reply = "phx_reply"
        public static let leave = "phx_leave"

        public static func isLifecycleEvent(_ event: String) -> Bool {
            return event == close || event == error || event == join || event == reply || event == leave
        }
        private init() {}
    }

    public enum ChannelState {
        case closed, errored, joined, joining, leaving
    }

    // MARK: - Push Object
    public final class PhoenixPush {
        private weak var channel: PhoenixChannel?
        private let event: String
        private let payload: [String: Any]
        public private(set) var ref: String?
        private var refEvent: String?
        private var receivedResp: [String: Any]?
        public private(set) var isSent: Bool = false
        private var bindingId: Int = -1
        private let timeoutMs: TimeInterval
        private var timeoutItem: DispatchWorkItem?
        private var hookStatuses = [String]()
        private var hookCallbacks = [MessageCallback]()

        init(channel: PhoenixChannel, event: String, payload: [String: Any]?, timeoutMs: TimeInterval) {
            self.channel = channel
            self.event = event
            self.payload = payload ?? [:]
            self.timeoutMs = timeoutMs
        }

        @discardableResult
        public func receive(_ status: String, callback: @escaping MessageCallback) -> PhoenixPush {
            if let resp = receivedResp {
                let received = resp["status"] as? String ?? ""
                if received == status {
                    let response = resp["response"] as? [String: Any] ?? [:]
                    callback(response, ref, nil)
                }
            }
            hookStatuses.append(status)
            hookCallbacks.append(callback)
            return self
        }

        func trigger(status: String, response: [String: Any]?) {
            let resp: [String: Any] = ["status": status, "response": response ?? [:]]
            if let refEvent = refEvent, let ch = channel {
                ch.triggerInternal(event: refEvent, payload: resp, ref: ref, joinRef: nil)
            }
        }

        func resend(newTimeout: TimeInterval) {
            reset()
            send()
        }

        func send() {
            guard let channel = channel, let socket = channel.getSocket() else { return }
            if hasReceived("timeout") { return }
            startTimeout()
            isSent = true
            socket.pushMessage(
                topic: channel.topic,
                event: event,
                payload: payload,
                ref: ref,
                joinRef: channel.joinRef()
            )
        }

        func startTimeout() {
            guard let channel = channel, let socket = channel.getSocket() else { return }
            cancelTimeout()
            cancelRefEvent()
            let allocatedRef = socket.makeRef()
            self.ref = allocatedRef
            let rEvent = PhoenixSocket.replyEventName(ref: allocatedRef)
            self.refEvent = rEvent

            bindingId = channel.addBinding(event: rEvent) { [weak self] replyPayload, _, _ in
                guard let self = self else { return }
                self.cancelRefEvent()
                self.cancelTimeout()
                self.receivedResp = replyPayload
                self.matchReceive(resp: replyPayload)
            }

            let item = DispatchWorkItem { [weak self] in
                guard let self = self, let ch = self.channel else { return }
                let resp: [String: Any] = ["status": "timeout", "response": [:]]
                if let refEvent = self.refEvent {
                    ch.triggerInternal(event: refEvent, payload: resp, ref: allocatedRef, joinRef: nil)
                }
            }
            timeoutItem = item
            socket.queue.asyncAfter(deadline: .now() + (timeoutMs / 1000.0), execute: item)
        }

        func cancelTimeout() {
            timeoutItem?.cancel()
            timeoutItem = nil
        }

        func cancelRefEvent() {
            if bindingId >= 0, let refEvent = refEvent, let ch = channel {
                ch.removeBinding(event: refEvent, id: bindingId)
                bindingId = -1
            }
        }

        func reset() {
            cancelRefEvent()
            cancelTimeout()
            ref = nil
            refEvent = nil
            receivedResp = nil
            isSent = false
        }

        private func matchReceive(resp: [String: Any]?) {
            guard let resp = resp else { return }
            let status = resp["status"] as? String ?? ""
            let response = resp["response"] as? [String: Any] ?? [:]
            for i in 0..<hookStatuses.count where hookStatuses[i] == status {
                hookCallbacks[i](response, ref, nil)
            }
        }

        func hasReceived(_ status: String) -> Bool {
            return (receivedResp?["status"] as? String) == status
        }
    }

    // MARK: - Channel Object
    public final class PhoenixChannel {
        public private(set) var state: ChannelState = .closed
        public let topic: String
        public let params: [String: Any]
        private weak var socket: PhoenixSocket?
        private var timeout: TimeInterval

        struct Binding {
            let event: String
            let id: Int
            let callback: MessageCallback
        }

        private var bindings = [Binding]()
        private var nextBindingId = 0
        private var joinedOnce = false
        private var joinPush: PhoenixPush!
        private var pushBuffer = [PhoenixPush]()
        private var rejoinTimer: RetryTimer!
        private var socketOnErrorRef = -1
        private var socketOnOpenRef = -1

        init(topic: String, params: [String: Any]?, socket: PhoenixSocket) {
            self.topic = topic
            self.params = params ?? [:]
            self.socket = socket
            self.timeout = socket.timeout
            self.joinPush = PhoenixPush(channel: self, event: ChannelEvent.join, payload: self.params, timeoutMs: timeout)

            self.rejoinTimer = RetryTimer(
                queue: socket.queue,
                callback: { [weak self, weak socket] in
                    guard let self = self, let socket = socket else { return }
                    if socket.isConnected { self.rejoin() }
                },
                calc: { tries in
                    let delays: [TimeInterval] = [1.0, 2.0, 5.0]
                    return (tries <= delays.count) ? delays[tries - 1] : 10.0
                }
            )

            joinPush.receive("ok") { [weak self] _, _, _ in
                guard let self = self else { return }
                self.state = .joined
                self.rejoinTimer.reset()
                let toFlush = self.pushBuffer
                self.pushBuffer.removeAll()
                toFlush.forEach { $0.send() }
            }

            joinPush.receive("error") { [weak self] _, _, _ in
                guard let self = self, let socket = self.socket else { return }
                self.state = .errored
                if socket.isConnected { self.rejoinTimer.scheduleTimeout() }
            }

            joinPush.receive("timeout") { [weak self] _, _, _ in
                guard let self = self, let socket = self.socket else { return }
                PhoenixPush(channel: self, event: ChannelEvent.leave, payload: [:], timeoutMs: self.timeout).send()
                self.state = .errored
                self.joinPush.reset()
                if socket.isConnected { self.rejoinTimer.scheduleTimeout() }
            }

            _ = addBinding(event: ChannelEvent.close) { [weak self] _, _, _ in
                guard let self = self else { return }
                self.rejoinTimer.reset()
                self.state = .closed
                self.socket?.removeChannel(self)
            }

            _ = addBinding(event: ChannelEvent.error) { [weak self] _, _, _ in
                guard let self = self, let socket = self.socket else { return }
                if self.isJoining { self.joinPush.reset() }
                self.state = .errored
                if socket.isConnected { self.rejoinTimer.scheduleTimeout() }
            }

            _ = addBinding(event: ChannelEvent.reply) { [weak self] payload, ref, joinRef in
                guard let self = self, let ref = ref else { return }
                self.triggerInternal(event: PhoenixSocket.replyEventName(ref: ref), payload: payload, ref: ref, joinRef: joinRef)
            }

            socketOnErrorRef = socket.onError { [weak self] _ in self?.rejoinTimer.reset() }
            socketOnOpenRef = socket.onOpen { [weak self] in
                guard let self = self else { return }
                self.rejoinTimer.reset()
                if self.isErrored { self.rejoin() }
            }
        }

        @discardableResult
        public func join(timeoutMs: TimeInterval? = nil) -> PhoenixPush {
            if joinedOnce { fatalError("join() called more than once on channel \(topic)") }
            joinedOnce = true
            if let t = timeoutMs { self.timeout = t }
            socket?.queue.async { [weak self] in self?.rejoin() }
            return joinPush
        }

        @discardableResult
        public func push(event: String, payload: [String: Any]? = nil, timeoutMs: TimeInterval? = nil) -> PhoenixPush {
            let pushTimeout = timeoutMs ?? self.timeout
            let push = PhoenixPush(channel: self, event: event, payload: payload ?? [:], timeoutMs: pushTimeout)
            socket?.queue.async { [weak self] in
                guard let self = self else { return }
                if self.canPush {
                    push.send()
                } else {
                    push.startTimeout()
                    self.pushBuffer.append(push)
                }
            }
            return push
        }

        @discardableResult
        public func leave(timeoutMs: TimeInterval? = nil) -> PhoenixPush {
            let leaveTimeout = timeoutMs ?? self.timeout
            let leavePush = PhoenixPush(channel: self, event: ChannelEvent.leave, payload: [:], timeoutMs: leaveTimeout)
            socket?.queue.async { [weak self] in
                guard let self = self else { return }
                self.rejoinTimer.reset()
                self.joinPush.cancelTimeout()
                self.state = .leaving
                let onLeave: () -> Void = { [weak self] in
                    self?.triggerInternal(event: ChannelEvent.close, payload: [:], ref: nil, joinRef: nil)
                }
                leavePush.receive("ok") { _, _, _ in onLeave() }
                leavePush.receive("timeout") { _, _, _ in onLeave() }
                leavePush.send()
                if !self.canPush { leavePush.trigger(status: "ok", response: [:]) }
            }
            return leavePush
        }

        @discardableResult
        public func on(event: String, callback: @escaping MessageCallback) -> Int {
            let id = nextBindingId
            nextBindingId += 1
            socket?.queue.async { [weak self] in
                self?.bindings.append(Binding(event: event, id: id, callback: callback))
            }
            return id
        }

        public func off(_ event: String, bindingId: Int? = nil) {
            socket?.queue.async { [weak self] in
                if let id = bindingId {
                    self?.removeBinding(event: event, id: id)
                } else {
                    self?.bindings.removeAll { $0.event == event }
                }
            }
        }

        public var isClosed: Bool  { return state == .closed }
        public var isErrored: Bool { return state == .errored }
        public var isJoined: Bool  { return state == .joined }
        public var isJoining: Bool { return state == .joining }
        public var isLeaving: Bool { return state == .leaving }

        func addBinding(event: String, callback: @escaping MessageCallback) -> Int {
            let id = nextBindingId
            nextBindingId += 1
            bindings.append(Binding(event: event, id: id, callback: callback))
            return id
        }

        func removeBinding(event: String, id: Int) {
            bindings.removeAll { $0.event == event && $0.id == id }
        }

        func triggerInternal(event: String, payload: [String: Any], ref: String?, joinRef: String?) {
            let snapshot = bindings
            for b in snapshot where b.event == event {
                b.callback(payload, ref, joinRef ?? self.joinRef())
            }
        }

        func isMember(msgTopic: String, msgEvent: String, payload: [String: Any], msgJoinRef: String?) -> Bool {
            if self.topic != msgTopic { return false }
            if let msgJoinRef = msgJoinRef, let currentJoinRef = self.joinRef(),
               msgJoinRef != currentJoinRef, ChannelEvent.isLifecycleEvent(msgEvent) {
                return false
            }
            return true
        }

        public func joinRef() -> String? { return joinPush.ref }

        func rejoin() {
            if isLeaving { return }
            socket?.leaveOpenTopic(topic: topic)
            state = .joining
            joinPush.resend(newTimeout: timeout)
        }

        func destroy() {
            rejoinTimer.reset()
            if socketOnErrorRef >= 0 { socket?.removeStateChangeCallback(id: socketOnErrorRef, type: "error") }
            if socketOnOpenRef >= 0 { socket?.removeStateChangeCallback(id: socketOnOpenRef, type: "open") }
        }

        var canPush: Bool { return (socket?.isConnected ?? false) && isJoined }
        func getSocket() -> PhoenixSocket? { return socket }
    }

    // MARK: - Socket Object
    public final class PhoenixSocket: NSObject, URLSessionWebSocketDelegate {
        public static let vsn = "2.0.0"
        public static let defaultTimeoutMs: TimeInterval = 10_000.0
        public static let heartbeatIntervalMs: TimeInterval = 30_000.0
        public static let heartbeatTimeoutMs: TimeInterval = 30_000.0

        private static let reconnectDelays: [TimeInterval] = [0.01, 0.05, 0.1, 0.15, 0.2, 0.25, 0.5, 1.0, 2.0]

        public final class Builder {
            private let endpointBase: String
            private var params = [String: String]()
            private var timeout: TimeInterval = defaultTimeoutMs
            private var heartbeatMs: TimeInterval = PhoenixSocket.heartbeatIntervalMs
            private var logger: PhoenixLogger? = nil
            private var decoder: MessageDecoder = DefaultMessageDecoder()

            public init(endpointBase: String) { self.endpointBase = endpointBase }
            public func param(key: String, value: String) -> Builder { params[key] = value; return self }
            public func timeout(_ ms: TimeInterval) -> Builder { self.timeout = ms; return self }
            public func heartbeatIntervalMs(_ ms: TimeInterval) -> Builder { self.heartbeatMs = ms; return self }
            public func logger(_ logger: @escaping PhoenixLogger) -> Builder { self.logger = logger; return self }
            public func decoder(_ decoder: MessageDecoder) -> Builder { self.decoder = decoder; return self }
            public func build() -> PhoenixSocket {
                return PhoenixSocket(endpointBase: endpointBase, params: params, timeout: timeout, heartbeatIntervalMs: heartbeatMs, logger: logger, decoder: decoder)
            }
        }

        let endpointBase: String
        let params: [String: String]
        let timeout: TimeInterval
        let heartbeatIntervalMs: TimeInterval
        let logger: PhoenixLogger?
        let decoder: MessageDecoder

        private var wsTask: URLSessionWebSocketTask?
        private var urlSession: URLSession?
        private var channels = [PhoenixChannel]()
        private var sendBuffer = [() -> Void]()
        private var refCounter: Int = 0

        private var pendingHeartbeatRef: String?
        private var heartbeatWorkItem: DispatchWorkItem?
        private var heartbeatTimeoutItem: DispatchWorkItem?

        private var closeWasClean = false
        private var disconnecting = false
        private var connectClock = 0
        private var establishedConns = 0
        private var pageHidden = false
        private var backgroundDisconnectItem: DispatchWorkItem?
        private var reconnectTimer: RetryTimer!

        let queue = DispatchQueue(label: "dev.flareframework.socket")

        private var openIds = [Int](), openCbs = [OpenCallback]()
        private var closeIds = [Int](), closeCbs = [CloseCallback]()
        private var errorIds = [Int](), errorCbs = [ErrorCallback]()
        private var nextStateChangeRef = 0

        init(endpointBase: String, params: [String: String], timeout: TimeInterval, heartbeatIntervalMs: TimeInterval, logger: PhoenixLogger?, decoder: MessageDecoder) {
            var url = endpointBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !url.hasSuffix("/websocket") { url += "/websocket" }
            self.endpointBase = url
            self.params = params
            self.timeout = timeout
            self.heartbeatIntervalMs = heartbeatIntervalMs
            self.logger = logger
            self.decoder = decoder
            super.init()

            self.reconnectTimer = RetryTimer(
                queue: self.queue,
                callback: { [weak self] in
                    guard let self = self else { return }
                    if self.pageHidden { return }
                    self.teardown(onDone: { self.transportConnect() }, triesLeft: 5)
                },
                calc: { tries in
                    return (tries <= PhoenixSocket.reconnectDelays.count) ? PhoenixSocket.reconnectDelays[tries - 1] : 5.0
                }
            )
        }

        public func connect() {
            queue.async { [weak self] in
                guard let self = self else { return }
                if self.wsTask != nil && !self.disconnecting { return }
                self.transportConnect()
            }
        }

        public func disconnect(callback: (() -> Void)? = nil) {
            queue.async { [weak self] in
                guard let self = self else { return }
                self.connectClock += 1
                self.disconnecting = true
                self.closeWasClean = true
                self.reconnectTimer.reset()
                self.clearHeartbeats()
                self.teardown(onDone: {
                    self.disconnecting = false
                    callback?()
                }, triesLeft: 5)
            }
        }

        public func shutdown() {
            disconnect { [weak self] in self?.urlSession?.invalidateAndCancel() }
        }

        public func onActivityPause() {
            queue.async { [weak self] in
                guard let self = self else { return }
                self.pageHidden = true
                self.closeWasClean = false
                self.reconnectTimer.reset()
                self.clearHeartbeats()
                self.backgroundDisconnectItem?.cancel()

                if self.wsTask == nil { return }
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if self.pageHidden && self.wsTask != nil { self.teardown(onDone: nil, triesLeft: 5) }
                    self.backgroundDisconnectItem = nil
                }
                self.backgroundDisconnectItem = item
                self.queue.asyncAfter(deadline: .now() + 30.0, execute: item)
            }
        }

        public func onActivityResume() {
            queue.async { [weak self] in
                guard let self = self else { return }
                self.pageHidden = false
                self.backgroundDisconnectItem?.cancel()
                self.backgroundDisconnectItem = nil

                if !self.isConnected && !self.closeWasClean {
                    self.teardown(onDone: { self.transportConnect() }, triesLeft: 5)
                }
            }
        }

        public func channel(_ topic: String, chanParams: [String: Any]? = nil) -> PhoenixChannel {
            let chan = PhoenixChannel(topic: topic, params: chanParams, socket: self)
            queue.async { [weak self] in self?.channels.append(chan) }
            return chan
        }

        @discardableResult
        public func onOpen(_ callback: @escaping OpenCallback) -> Int {
            let id = nextStateChangeRef; nextStateChangeRef += 1
            queue.async { [weak self] in self?.openIds.append(id); self?.openCbs.append(callback) }
            return id
        }

        @discardableResult
        public func onClose(_ callback: @escaping CloseCallback) -> Int {
            let id = nextStateChangeRef; nextStateChangeRef += 1
            queue.async { [weak self] in self?.closeIds.append(id); self?.closeCbs.append(callback) }
            return id
        }

        @discardableResult
        public func onError(_ callback: @escaping ErrorCallback) -> Int {
            let id = nextStateChangeRef; nextStateChangeRef += 1
            queue.async { [weak self] in self?.errorIds.append(id); self?.errorCbs.append(callback) }
            return id
        }

        public var isConnected: Bool {
            return wsTask != nil && wsTask?.state == .running
        }

        private func transportConnect() {
            connectClock += 1
            closeWasClean = false
            let clock = connectClock
            guard let url = URL(string: buildUrl()) else { return }

            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.urlSession = session
            let task = session.webSocketTask(with: url)
            self.wsTask = task
            task.resume()
            listenWebSocket(task: task, clock: clock)
        }

        private func listenWebSocket(task: URLSessionWebSocketTask, clock: Int) {
            task.receive { [weak self] result in
                guard let self = self else { return }
                self.queue.async {
                    if clock != self.connectClock { return }
                    switch result {
                    case .success(let message):
                        switch message {
                        case .string(let text):
                            if let decoded = try? self.decoder.decode(text: text), !decoded.isEmpty {
                                self.onConnMessage(text: decoded)
                            }
                        case .data(let data):
                            if let decoded = try? self.decoder.decode(data: data), !decoded.isEmpty {
                                self.onConnMessage(text: decoded)
                            }
                        @unknown default: break
                        }
                        self.listenWebSocket(task: task, clock: clock)
                    case .failure(let error):
                        self.wsTask = nil
                        self.onConnError(reason: error.localizedDescription)
                        if !self.closeWasClean { self.reconnectTimer.scheduleTimeout() }
                    }
                }
            }
        }

        public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            queue.async { [weak self] in
                guard let self = self, webSocketTask === self.wsTask else { return }
                self.onConnOpen()
            }
        }

        public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            let code = closeCode.rawValue
            let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            queue.async { [weak self] in
                guard let self = self, webSocketTask === self.wsTask else { return }
                self.wsTask = nil
                self.onConnClose(code: code, reason: reasonStr)
            }
        }

        private func teardown(onDone: (() -> Void)?, triesLeft: Int) {
            clearHeartbeats()
            if wsTask == nil {
                if let onDone = onDone { queue.async(execute: onDone) }
                return
            }
            let toClose = wsTask
            wsTask = nil
            toClose?.cancel(with: .normalClosure, reason: nil)
            if let onDone = onDone { queue.async(execute: onDone) }
        }

        private func onConnOpen() {
            closeWasClean = false
            disconnecting = false
            establishedConns += 1
            flushSendBuffer()
            reconnectTimer.reset()
            resetHeartbeat()
            openCbs.forEach { $0() }
        }

        private func onConnClose(code: Int, reason: String) {
            triggerChanError()
            clearHeartbeats()
            if !closeWasClean && code != 1000 { reconnectTimer.scheduleTimeout() }
            closeCbs.forEach { $0(code, reason) }
        }

        private func onConnError(reason: String) {
            errorCbs.forEach { $0(reason) }
            triggerChanError()
        }

        private func onConnMessage(text: String) {
            guard let data = text.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any],
                  arr.count >= 5 else { return }

            let joinRef = arr[0] is NSNull ? nil : arr[0] as? String
            let ref     = arr[1] is NSNull ? nil : arr[1] as? String
            let topic   = arr[2] as? String ?? ""
            let event   = arr[3] as? String ?? ""
            let payload = arr[4] as? [String: Any] ?? [:]

            if let ref = ref, ref == pendingHeartbeatRef {
                clearHeartbeats()
                pendingHeartbeatRef = nil
                scheduleNextHeartbeat()
                return
            }

            let snapshot = channels
            for ch in snapshot where ch.isMember(msgTopic: topic, msgEvent: event, payload: payload, msgJoinRef: joinRef) {
                ch.triggerInternal(event: event, payload: payload, ref: ref, joinRef: joinRef)
            }
        }

        private func resetHeartbeat() {
            pendingHeartbeatRef = nil
            clearHeartbeats()
            scheduleNextHeartbeat()
        }

        private func scheduleNextHeartbeat() {
            let item = DispatchWorkItem { [weak self] in self?.sendHeartbeat() }
            heartbeatWorkItem = item
            queue.asyncAfter(deadline: .now() + (heartbeatIntervalMs / 1000.0), execute: item)
        }

        private func sendHeartbeat() {
            if !isConnected { return }
            if pendingHeartbeatRef != nil {
                pendingHeartbeatRef = nil
                triggerChanError()
                closeWasClean = false
                teardown(onDone: { [weak self] in self?.reconnectTimer.scheduleTimeout() }, triesLeft: 5)
                return
            }

            let hRef = makeRef()
            pendingHeartbeatRef = hRef
            pushRaw(topic: "phoenix", event: "heartbeat", payload: [:], ref: hRef, joinRef: nil)

            let timeoutItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.pendingHeartbeatRef == nil { return }
                self.pendingHeartbeatRef = nil
                self.triggerChanError()
                self.closeWasClean = false
                self.teardown(onDone: { self.reconnectTimer.scheduleTimeout() }, triesLeft: 5)
            }
            self.heartbeatTimeoutItem = timeoutItem
            queue.asyncAfter(deadline: .now() + (PhoenixSocket.heartbeatTimeoutMs / 1000.0), execute: timeoutItem)
        }

        private func clearHeartbeats() {
            heartbeatWorkItem?.cancel()
            heartbeatWorkItem = nil
            heartbeatTimeoutItem?.cancel()
            heartbeatTimeoutItem = nil
        }

        func pushMessage(topic: String, event: String, payload: [String: Any], ref: String?, joinRef: String?) {
            let encoded = encode(topic: topic, event: event, payload: payload, ref: ref, joinRef: joinRef)
            if isConnected {
                wsTask?.send(.string(encoded)) { _ in }
            } else {
                sendBuffer.append { [weak self] in self?.wsTask?.send(.string(encoded)) { _ in } }
            }
        }

        private func pushRaw(topic: String, event: String, payload: [String: Any], ref: String?, joinRef: String?) {
            if isConnected {
                let encoded = encode(topic: topic, event: event, payload: payload, ref: ref, joinRef: joinRef)
                wsTask?.send(.string(encoded)) { _ in }
            }
        }

        private func flushSendBuffer() {
            guard isConnected else { return }
            sendBuffer.forEach { $0() }
            sendBuffer.removeAll()
        }

        private func encode(topic: String, event: String, payload: [String: Any], ref: String?, joinRef: String?) -> String {
            let arr: [Any] = [joinRef ?? NSNull(), ref ?? NSNull(), topic, event, payload]
            if let data = try? JSONSerialization.data(withJSONObject: arr, options: []),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "[]"
        }

        func leaveOpenTopic(topic: String) {
            for ch in channels where ch.topic == topic && (ch.isJoined || ch.isJoining) {
                ch.leave()
                break
            }
        }

        func removeChannel(_ channel: PhoenixChannel) {
            queue.async { [weak self] in
                channel.destroy()
                self?.channels.removeAll { $0 === channel }
            }
        }

        private func triggerChanError() {
            channels.filter { !$0.isErrored && !$0.isLeaving && !$0.isClosed }.forEach {
                $0.triggerInternal(event: ChannelEvent.error, payload: [:], ref: nil, joinRef: nil)
            }
        }

        func removeStateChangeCallback(id: Int, type: String) {
            queue.async { [weak self] in
                guard let self = self else { return }
                switch type {
                case "open":
                    if let idx = self.openIds.firstIndex(of: id) {
                        self.openIds.remove(at: idx)
                        self.openCbs.remove(at: idx)
                    }
                case "close":
                    if let idx = self.closeIds.firstIndex(of: id) {
                        self.closeIds.remove(at: idx)
                        self.closeCbs.remove(at: idx)
                    }
                case "error":
                    if let idx = self.errorIds.firstIndex(of: id) {
                        self.errorIds.remove(at: idx)
                        self.errorCbs.remove(at: idx)
                    }
                default: break
                }
            }
        }

        func makeRef() -> String {
            refCounter = (refCounter >= Int.max - 1) ? 1 : refCounter + 1
            return String(refCounter)
        }

        static func replyEventName(ref: String) -> String { return "chan_reply_\(ref)" }

        private func buildUrl() -> String {
            var components = URLComponents(string: endpointBase)
            var queryItems = [URLQueryItem(name: "vsn", value: PhoenixSocket.vsn)]
            for (k, v) in params { queryItems.append(URLQueryItem(name: k, value: v)) }
            components?.queryItems = queryItems
            return components?.url?.absoluteString ?? endpointBase
        }

        func log(tag: String, msg: String) { logger?(tag, msg) }
    }

    // MARK: - Phoenix Presence CRDT
    public final class PhoenixPresence {
        public typealias PresenceChangeCallback = (_ id: String, _ currentPresence: [String: Any]?, _ newPresence: [String: Any]) -> Void

        private let channel: PhoenixChannel
        public private(set) var state = [String: [String: Any]]()
        private var pendingDiffs = [[String: Any]]()
        private var joinRef: String? = nil

        private var onJoinCallback: PresenceChangeCallback?
        private var onLeaveCallback: PresenceChangeCallback?
        private var onSyncCallback: (() -> Void)?

        public init(channel: PhoenixChannel) {
            self.channel = channel

            _ = channel.on(event: "presence_state") { [weak self] newState, _, _ in
                guard let self = self else { return }
                self.joinRef = self.channel.joinRef()
                self.syncState(newState: newState)
                for diff in self.pendingDiffs {
                    self.syncDiff(diff: diff)
                }
                self.pendingDiffs.removeAll()
                self.onSyncCallback?()
            }

            _ = channel.on(event: "presence_diff") { [weak self] diff, _, _ in
                guard let self = self else { return }
                if self.inPendingSyncState() {
                    self.pendingDiffs.append(diff)
                } else {
                    self.syncDiff(diff: diff)
                    self.onSyncCallback?()
                }
            }
        }

        public func onJoin(_ callback: @escaping PresenceChangeCallback) { self.onJoinCallback = callback }
        public func onLeave(_ callback: @escaping PresenceChangeCallback) { self.onLeaveCallback = callback }
        public func onSync(_ callback: @escaping () -> Void) { self.onSyncCallback = callback }

        private func inPendingSyncState() -> Bool {
            return joinRef == nil || joinRef != channel.joinRef()
        }

        private func syncState(newState: [String: Any]) {
            var joins = [String: Any]()
            var leaves = [String: Any]()

            for key in state.keys where newState[key] == nil {
                leaves[key] = state[key]
            }

            for (key, val) in newState {
                guard let newPresence = val as? [String: Any] else { continue }
                let curPresence = state[key]

                if let curPresence = curPresence {
                    let newMetas = newPresence["metas"] as? [[String: Any]] ?? []
                    let curMetas = curPresence["metas"] as? [[String: Any]] ?? []

                    var joinedMetas = [[String: Any]]()
                    for m in newMetas {
                        let phxRef = m["phx_ref"] as? String ?? ""
                        if !PhoenixPresence.containsRef(metas: curMetas, phxRef: phxRef) { joinedMetas.append(m) }
                    }
                    if !joinedMetas.isEmpty {
                        var joinEntry = newPresence
                        joinEntry["metas"] = joinedMetas
                        joins[key] = joinEntry
                    }

                    var leftMetas = [[String: Any]]()
                    for m in curMetas {
                        let phxRef = m["phx_ref"] as? String ?? ""
                        if !PhoenixPresence.containsRef(metas: newMetas, phxRef: phxRef) { leftMetas.append(m) }
                    }
                    if !leftMetas.isEmpty {
                        var leaveEntry = curPresence
                        leaveEntry["metas"] = leftMetas
                        leaves[key] = leaveEntry
                    }
                } else {
                    joins[key] = newPresence
                }
            }

            let diff: [String: Any] = ["joins": joins, "leaves": leaves]
            syncDiff(diff: diff)
        }

        private func syncDiff(diff: [String: Any]) {
            if let joins = diff["joins"] as? [String: [String: Any]] {
                for (key, newPresence) in joins {
                    let curPresence = state[key]
                    var updated = newPresence
                    if let curPresence = curPresence {
                        let joinedRefs = updated["metas"] as? [[String: Any]] ?? []
                        let curMetas = curPresence["metas"] as? [[String: Any]] ?? []
                        var merged = [[String: Any]]()
                        for m in curMetas {
                            let phxRef = m["phx_ref"] as? String ?? ""
                            if !PhoenixPresence.containsRef(metas: joinedRefs, phxRef: phxRef) { merged.append(m) }
                        }
                        merged.append(contentsOf: joinedRefs)
                        updated["metas"] = merged
                    }
                    state[key] = updated
                    onJoinCallback?(key, curPresence, newPresence)
                }
            }

            if let leaves = diff["leaves"] as? [String: [String: Any]] {
                for (key, leftPresence) in leaves {
                    guard var curPresence = state[key] else { continue }
                    let refsToRemove = leftPresence["metas"] as? [[String: Any]] ?? []
                    let curMetas = curPresence["metas"] as? [[String: Any]] ?? []
                    var keptMetas = [[String: Any]]()

                    for m in curMetas {
                        let phxRef = m["phx_ref"] as? String ?? ""
                        if !PhoenixPresence.containsRef(metas: refsToRemove, phxRef: phxRef) { keptMetas.append(m) }
                    }
                    curPresence["metas"] = keptMetas
                    onLeaveCallback?(key, curPresence, leftPresence)

                    if keptMetas.isEmpty { state.removeValue(forKey: key) }
                    else { state[key] = curPresence }
                }
            }
        }

        private static func containsRef(metas: [[String: Any]], phxRef: String) -> Bool {
            return metas.contains { ($0["phx_ref"] as? String) == phxRef }
        }
    }
}